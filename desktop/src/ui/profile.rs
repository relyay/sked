//! Profile: user card, data and about; editing lives in a dialog.

use std::rc::Rc;

use adw::prelude::*;
use gtk::glib;

use super::onboarding::{group_picker_page, subgroup_toggles};
use super::widgets::error_group;
use crate::core::{Profile, Subgroup};
use crate::format;
use crate::i18n::{t, tf};
use crate::state::AppState;

pub fn page(state: &Rc<AppState>, window: &adw::ApplicationWindow) -> gtk::Widget {
    let holder = gtk::Box::builder().orientation(gtk::Orientation::Vertical).build();
    let render = {
        let (state, holder, window) = (Rc::clone(state), holder.clone(), window.clone());
        move || {
            super::widgets::clear(&holder);
            if let Some(profile) = state.profile() {
                holder.append(&main_page(&state, &profile, &window));
            }
        }
    };
    render();
    state.subscribe(render);
    holder.upcast()
}

fn main_page(state: &Rc<AppState>, profile: &Profile, window: &adw::ApplicationWindow) -> adw::PreferencesPage {
    let page = adw::PreferencesPage::builder().vexpand(true).build();

    // The user card: initials, name, "group · course" and the subgroup.
    let card_group = adw::PreferencesGroup::new();
    let mut subtitle = format!("{} · {}", profile.group, tf("course.label", &[&profile.course.to_string()]));
    if profile.subgroup != Subgroup::Unspecified {
        subtitle.push('\n');
        subtitle.push_str(&format::subgroup_name(profile.subgroup));
    }
    let card = adw::ActionRow::builder()
        .title(glib::markup_escape_text(&profile.full_name))
        .subtitle(glib::markup_escape_text(&subtitle))
        .activatable(true)
        .tooltip_text(t("profile.edit"))
        .build();
    card.add_css_class("property");
    let avatar = adw::Avatar::builder().size(56).text(initials(&profile.full_name)).show_initials(true).margin_top(6).margin_bottom(6).build();
    card.add_prefix(&avatar);
    card.add_suffix(&gtk::Image::from_icon_name("go-next-symbolic"));
    card.connect_activated({
        let (state, window) = (Rc::clone(state), window.clone());
        move |_| edit_dialog(&state).present(Some(&window))
    });
    card_group.add(&card);
    page.add(&card_group);

    let data = adw::PreferencesGroup::builder().title(t("profile.data")).build();
    let updated = state.fetched_at().map(format::date_time).unwrap_or_else(|| t("profile.never").to_owned());
    data.add(&property_row(t("profile.dataUpdated"), &updated));
    if let Some(schedule) = state.schedule() {
        if let Ok(parsed) = schedule.parsed_at.parse::<jiff::Timestamp>() {
            data.add(&property_row(t("profile.serverParsed"), &format::date_time(parsed)));
        }
    }
    if let Some(error) = state.stale() {
        let row = adw::ActionRow::builder().title(glib::markup_escape_text(&format::error_title(&error))).build();
        row.add_css_class("error");
        data.add(&row);
    }
    let refresh = adw::ButtonRow::builder().title(t("profile.refreshNow")).sensitive(!state.is_refreshing()).build();
    refresh.connect_activated({
        let state = Rc::clone(state);
        move |_| state.refresh()
    });
    data.add(&refresh);
    page.add(&data);

    let about = adw::PreferencesGroup::builder().title(t("profile.about")).build();
    about.add(&property_row(t("profile.version"), env!("CARGO_PKG_VERSION")));
    page.add(&about);
    page
}

fn property_row(title: &str, value: &str) -> adw::ActionRow {
    let row = adw::ActionRow::builder().title(title).subtitle(glib::markup_escape_text(value)).build();
    row.add_css_class("property");
    row
}

/// "Фамилия Имя Отчество" → "Имя Фамилия", so the avatar shows "ИФ".
fn initials(full_name: &str) -> String {
    let words: Vec<&str> = full_name.split_whitespace().collect();
    match words.as_slice() {
        [last, first, ..] => format!("{first} {last}"),
        _ => full_name.to_owned(),
    }
}

/// "Edit profile": name, group, subgroup and resetting the profile.
fn edit_dialog(state: &Rc<AppState>) -> adw::Dialog {
    let profile = state.profile().expect("profile");
    let nav = adw::NavigationView::new();
    let dialog = adw::Dialog::builder().title(t("profile.edit")).content_width(460).content_height(600).child(&nav).build();

    let page = adw::PreferencesPage::new();

    let name_group = adw::PreferencesGroup::builder().description(t("onboarding.nameFooter")).build();
    let name = adw::EntryRow::builder().title(t("profile.fullName")).text(&profile.full_name).show_apply_button(true).build();
    // An empty name is not saved; the previous one stays.
    let save_name = {
        let (state, name) = (Rc::clone(state), name.clone());
        move || {
            let text = name.text().trim().to_owned();
            if let Some(mut current) = state.profile() {
                if !text.is_empty() && text != current.full_name {
                    current.full_name = text;
                    state.save(current);
                }
            }
        }
    };
    name.connect_apply({
        let save_name = save_name.clone();
        move |_| save_name()
    });
    dialog.connect_closed(move |_| save_name());
    name_group.add(&name);
    page.add(&name_group);

    let group_group = adw::PreferencesGroup::builder().title(t("profile.group")).build();
    let group_row = adw::ActionRow::builder()
        .title(glib::markup_escape_text(&profile.group))
        .subtitle(tf("course.label", &[&profile.course.to_string()]))
        .activatable(true)
        .build();
    group_row.add_suffix(&gtk::Image::from_icon_name("go-next-symbolic"));
    group_row.connect_activated({
        let (state, nav, group_row) = (Rc::clone(state), nav.clone(), group_row.clone());
        move |_| open_group_picker(&state, &nav, &group_row)
    });
    group_group.add(&group_row);
    page.add(&group_group);

    let subgroup_group = adw::PreferencesGroup::builder().description(t("subgroup.footer")).build();
    subgroup_group.add(&subgroup_toggles(profile.subgroup, {
        let state = Rc::clone(state);
        move |subgroup| {
            if let Some(mut current) = state.profile() {
                if current.subgroup != subgroup {
                    current.subgroup = subgroup;
                    state.save(current);
                }
            }
        }
    }));
    page.add(&subgroup_group);

    let reset_group = adw::PreferencesGroup::new();
    let reset = adw::ButtonRow::builder().title(t("profile.reset")).build();
    reset.add_css_class("destructive-action");
    reset.connect_activated({
        let (state, dialog) = (Rc::clone(state), dialog.clone());
        move |_| confirm_reset(&state, &dialog)
    });
    reset_group.add(&reset);
    page.add(&reset_group);

    let view = adw::ToolbarView::new();
    view.add_top_bar(&adw::HeaderBar::new());
    view.set_content(Some(&page));
    nav.add(&adw::NavigationPage::builder().title(t("profile.edit")).tag("root").child(&view).build());
    dialog
}

fn open_group_picker(state: &Rc<AppState>, nav: &adw::NavigationView, group_row: &adw::ActionRow) {
    let loading = adw::Spinner::builder().width_request(32).height_request(32).halign(gtk::Align::Center).valign(gtk::Align::Center).build();
    let view = adw::ToolbarView::new();
    view.add_top_bar(&adw::HeaderBar::new());
    view.set_content(Some(&loading));
    let placeholder = adw::NavigationPage::builder().title(t("profile.group")).child(&view).build();
    nav.push(&placeholder);

    let (state_inner, nav, group_row) = (Rc::clone(state), nav.clone(), group_row.clone());
    state.load_groups(move |result| match result {
        Ok(groups) => {
            let selection = state_inner.profile().map(|p| p.group);
            let (state, nav_inner) = (Rc::clone(&state_inner), nav.clone());
            let picker = group_picker_page(groups.clone(), selection, move |name| {
                if let (Some(mut current), Some(info)) = (state.profile(), groups.iter().find(|g| g.name == name)) {
                    current.group = info.name.clone();
                    current.course = info.course;
                    group_row.set_title(&glib::markup_escape_text(&current.group));
                    group_row.set_subtitle(&tf("course.label", &[&current.course.to_string()]));
                    state.save(current);
                }
                nav_inner.pop_to_tag("root");
            });
            nav.replace(&[nav.find_page("root").expect("root page"), picker]);
        }
        Err(error) => {
            let page = adw::PreferencesPage::new();
            let (state, nav_retry, group_row) = (Rc::clone(&state_inner), nav.clone(), group_row.clone());
            page.add(&error_group(&format::error_title(&error), &format::error_recovery(&error), move || {
                nav_retry.pop();
                open_group_picker(&state, &nav_retry, &group_row);
            }));
            view.set_content(Some(&page));
        }
    });
}

fn confirm_reset(state: &Rc<AppState>, dialog: &adw::Dialog) {
    let alert = adw::AlertDialog::new(Some(t("profile.resetConfirm")), Some(t("profile.resetMessage")));
    alert.add_response("cancel", t("action.cancel"));
    alert.add_response("reset", t("profile.reset"));
    alert.set_response_appearance("reset", adw::ResponseAppearance::Destructive);
    alert.set_default_response(Some("cancel"));
    alert.set_close_response("cancel");
    let (state, dialog_inner) = (Rc::clone(state), dialog.clone());
    alert.connect_response(Some("reset"), move |_, _| {
        dialog_inner.force_close();
        state.reset();
    });
    alert.present(Some(dialog));
}
