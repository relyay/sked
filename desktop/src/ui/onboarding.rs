//! First launch: full name → group → subgroup on a single page, plus the
//! searchable group picker shared with the profile editor.

use std::cell::RefCell;
use std::rc::Rc;

use adw::prelude::*;
use gtk::glib;

use super::widgets::{clear, error_group};
use crate::api::ApiError;
use crate::core::{DraftProblem, GroupInfo, ProfileDraft, Subgroup};
use crate::format;
use crate::i18n::{t, tf};
use crate::state::AppState;

enum Groups {
    Loading,
    Loaded(Vec<GroupInfo>),
    Failed(ApiError),
}

pub fn view(state: &Rc<AppState>, _window: &adw::ApplicationWindow) -> adw::NavigationView {
    let nav = adw::NavigationView::new();
    let draft = Rc::new(RefCell::new(ProfileDraft::default()));
    let groups = Rc::new(RefCell::new(Groups::Loading));

    let page = adw::PreferencesPage::new();

    let name_group = adw::PreferencesGroup::builder().description(t("onboarding.nameFooter")).build();
    let name = adw::EntryRow::builder().title(t("profile.fullName")).build();
    name.connect_changed({
        let draft = Rc::clone(&draft);
        move |row| {
            draft.borrow_mut().full_name = row.text().to_string();
            row.remove_css_class("error");
        }
    });
    name_group.add(&name);
    page.add(&name_group);

    // The group row is rebuilt for loading / failed / loaded states.
    let group_holder = gtk::Box::builder().orientation(gtk::Orientation::Vertical).build();
    let group_section = adw::PreferencesGroup::builder().title(t("profile.group")).build();
    group_section.add(&group_holder);
    page.add(&group_section);

    let subgroup_group = adw::PreferencesGroup::builder().title(t("profile.subgroup")).description(t("subgroup.footer")).build();
    subgroup_group.add(&subgroup_toggles(Subgroup::Unspecified, {
        let draft = Rc::clone(&draft);
        move |s| draft.borrow_mut().subgroup = s
    }));
    page.add(&subgroup_group);

    let save = gtk::Button::builder().label(t("onboarding.save")).halign(gtk::Align::Center).margin_top(12).margin_bottom(12).sensitive(false).build();
    save.add_css_class("pill");
    save.add_css_class("suggested-action");

    // Rebuild the group row; held in a cell so the retry and picker can call it.
    let render_group: Rc<RefCell<Option<Rc<dyn Fn()>>>> = Rc::new(RefCell::new(None));
    let load: Rc<dyn Fn()> = Rc::new({
        let (state, groups, render_group) = (Rc::clone(state), Rc::clone(&groups), Rc::clone(&render_group));
        move || {
            *groups.borrow_mut() = Groups::Loading;
            if let Some(r) = render_group.borrow().clone() {
                r();
            }
            let (groups, render_group) = (Rc::clone(&groups), Rc::clone(&render_group));
            state.load_groups(move |result| {
                *groups.borrow_mut() = match result {
                    Ok(list) => Groups::Loaded(list),
                    Err(e) => Groups::Failed(e),
                };
                if let Some(r) = render_group.borrow().clone() {
                    r();
                }
            });
        }
    });
    let render: Rc<dyn Fn()> = Rc::new({
        let (groups, draft, nav, save, load, holder) =
            (Rc::clone(&groups), Rc::clone(&draft), nav.clone(), save.clone(), Rc::clone(&load), group_holder.clone());
        let self_ref = Rc::clone(&render_group);
        move || {
            clear(&holder);
            save.set_sensitive(draft.borrow().group.is_some());
            match &*groups.borrow() {
                Groups::Loading => {
                    let spinner = adw::Spinner::builder().height_request(32).margin_top(12).margin_bottom(12).build();
                    holder.append(&spinner);
                }
                Groups::Failed(error) => {
                    let load = Rc::clone(&load);
                    holder.append(&error_group(&format::error_title(error), &format::error_recovery(error), move || load()));
                }
                Groups::Loaded(list) => {
                    let list_box = super::widgets::boxed_list();
                    let selection = draft.borrow().group.clone();
                    let row = adw::ActionRow::builder()
                        .title(t("profile.group"))
                        .subtitle(selection.clone().unwrap_or_else(|| t("onboarding.choose").to_owned()))
                        .activatable(true)
                        .build();
                    row.add_suffix(&gtk::Image::from_icon_name("go-next-symbolic"));
                    let (list, nav, draft, self_ref) = (list.clone(), nav.clone(), Rc::clone(&draft), Rc::clone(&self_ref));
                    row.connect_activated(move |_| {
                        let (nav_inner, draft, self_ref) = (nav.clone(), Rc::clone(&draft), Rc::clone(&self_ref));
                        let current = draft.borrow().group.clone();
                        let picker = group_picker_page(list.clone(), current, move |name| {
                            draft.borrow_mut().group = Some(name);
                            nav_inner.pop();
                            if let Some(r) = self_ref.borrow().clone() {
                                r();
                            }
                        });
                        nav.push(&picker);
                    });
                    list_box.append(&row);
                    holder.append(&list_box);
                }
            }
        }
    });
    *render_group.borrow_mut() = Some(Rc::clone(&render));
    load();

    save.connect_clicked({
        let (state, draft, groups, name) = (Rc::clone(state), Rc::clone(&draft), Rc::clone(&groups), name.clone());
        move |_| {
            let list = match &*groups.borrow() {
                Groups::Loaded(list) => list.clone(),
                _ => return,
            };
            let result = draft.borrow().validate(&list);
            match result {
                Ok(profile) => state.save(profile),
                Err(DraftProblem::EmptyName) => {
                    name.add_css_class("error");
                    name.grab_focus();
                    name.set_tooltip_text(Some(t("onboarding.nameRequired")));
                }
                Err(_) => draft.borrow_mut().group = None,
            }
        }
    });

    let view = adw::ToolbarView::new();
    view.add_top_bar(&adw::HeaderBar::new());
    view.set_content(Some(&page));
    view.add_bottom_bar(&save);
    nav.add(&adw::NavigationPage::builder().title(t("onboarding.title")).child(&view).build());
    nav
}

/// Segmented 1 / 2 / Не указана.
pub fn subgroup_toggles(selection: Subgroup, on_change: impl Fn(Subgroup) + 'static) -> adw::ActionRow {
    let toggles = adw::ToggleGroup::builder().valign(gtk::Align::Center).build();
    toggles.add(adw::Toggle::builder().name("1").label("1").build());
    toggles.add(adw::Toggle::builder().name("2").label("2").build());
    toggles.add(adw::Toggle::builder().name("0").label(t("subgroup.unspecified")).build());
    toggles.set_active_name(Some(&selection.number().to_string()));
    toggles.connect_active_name_notify(move |toggles| {
        let number = toggles.active_name().and_then(|n| n.parse().ok()).unwrap_or(0);
        on_change(Subgroup::of(number));
    });
    let row = adw::ActionRow::builder().title(t("profile.subgroup")).build();
    row.add_suffix(&toggles);
    row
}

/// Searchable list of all groups, sectioned by course.
pub fn group_picker_page(groups: Vec<GroupInfo>, selection: Option<String>, on_pick: impl Fn(String) + 'static) -> adw::NavigationPage {
    let on_pick = Rc::new(on_pick);
    let search = gtk::SearchEntry::builder().placeholder_text(t("group.search")).hexpand(true).build();
    let view = adw::ToolbarView::new();
    let groups = Rc::new(groups);

    // Each search builds a fresh page; PreferencesPage has no "remove all".
    let render = {
        let (view, groups, search) = (view.clone(), Rc::clone(&groups), search.clone());
        move || {
            let page = adw::PreferencesPage::new();
            let query = search.text().trim().to_lowercase();
            let filtered: Vec<&GroupInfo> = groups.iter().filter(|g| g.name.to_lowercase().contains(&query)).collect();
            if filtered.is_empty() {
                page.add(&adw::PreferencesGroup::builder().title(t("group.notFound")).build());
            }
            let mut courses: Vec<i32> = filtered.iter().map(|g| g.course).collect();
            courses.sort();
            courses.dedup();
            for course in courses {
                let title = if course > 0 { tf("course.label", &[&course.to_string()]) } else { t("course.other").to_owned() };
                let section = adw::PreferencesGroup::builder().title(title).build();
                for info in filtered.iter().filter(|g| g.course == course) {
                    let row = adw::ActionRow::builder().title(glib::markup_escape_text(&info.name)).activatable(true).build();
                    if selection.as_deref() == Some(info.name.as_str()) {
                        row.add_suffix(&gtk::Image::from_icon_name("object-select-symbolic"));
                    }
                    let (name, on_pick) = (info.name.clone(), Rc::clone(&on_pick));
                    row.connect_activated(move |_| on_pick(name.clone()));
                    section.add(&row);
                }
                page.add(&section);
            }
            view.set_content(Some(&page));
        }
    };
    render();
    search.connect_search_changed(move |_| render());

    let clamp = adw::Clamp::builder().maximum_size(640).child(&search).margin_start(12).margin_end(12).margin_top(6).margin_bottom(6).build();
    view.add_top_bar(&adw::HeaderBar::new());
    view.add_top_bar(&clamp);
    adw::NavigationPage::builder().title(t("profile.group")).child(&view).build()
}
