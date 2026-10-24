//! libadwaita UI following the GNOME HIG: a view switcher (header on wide
//! windows, bottom bar on narrow ones) over Home, Schedule and Profile.

mod home;
mod onboarding;
mod profile;
mod schedule;
mod widgets;

use std::cell::Cell;
use std::rc::Rc;

use adw::prelude::*;
use gtk::glib;

use crate::format;
use crate::i18n::{t, tf};
use crate::state::AppState;

const CSS: &str = include_str!("style.css");

pub fn build_window(app: &adw::Application, state: Rc<AppState>) {
    let provider = gtk::CssProvider::new();
    provider.load_from_string(CSS);
    gtk::style_context_add_provider_for_display(
        &gtk::gdk::Display::default().expect("display"),
        &provider,
        gtk::STYLE_PROVIDER_PRIORITY_APPLICATION,
    );

    let window = adw::ApplicationWindow::builder()
        .application(app)
        .title("Sked")
        .icon_name("ru.sked.app")
        .default_width(860)
        .default_height(720)
        .width_request(360)
        .height_request(480)
        .build();

    let root = gtk::Stack::builder().transition_type(gtk::StackTransitionType::Crossfade).build();
    let main = main_view(&window, &state);
    root.add_named(&main, Some("main"));
    window.set_content(Some(&root));

    // Switch between onboarding and the tabs only when the profile appears or
    // disappears, so onboarding input isn't rebuilt on unrelated changes.
    let had_profile = Rc::new(Cell::new(None::<bool>));
    let show = {
        let (root, state, window) = (root.clone(), Rc::clone(&state), window.clone());
        move || {
            let has = state.profile().is_some();
            if had_profile.replace(Some(has)) == Some(has) {
                return;
            }
            if let Some(old) = root.child_by_name("onboarding") {
                root.remove(&old);
            }
            if has {
                root.set_visible_child_name("main");
            } else {
                let page = onboarding::view(&state, &window);
                root.add_named(&page, Some("onboarding"));
                root.set_visible_child_name("onboarding");
            }
        }
    };
    show();
    state.subscribe(show);

    // Refresh on launch and every 5 minutes; the server polls the PDFs every
    // 2 minutes and 304s keep this cheap.
    state.refresh();
    glib::timeout_add_seconds_local(300, {
        let state = Rc::clone(&state);
        move || {
            state.refresh();
            glib::ControlFlow::Continue
        }
    });

    window.present();
}

fn main_view(window: &adw::ApplicationWindow, state: &Rc<AppState>) -> adw::ToolbarView {
    let stack = adw::ViewStack::new();
    stack.add_titled_with_icon(&home::page(state), Some("home"), t("tab.home"), "go-home-symbolic");
    stack.add_titled_with_icon(&schedule::page(state), Some("schedule"), t("tab.schedule"), "x-office-calendar-symbolic");
    stack.add_titled_with_icon(&profile::page(state, window), Some("profile"), t("tab.profile"), "avatar-default-symbolic");

    let switcher = adw::ViewSwitcher::builder().stack(&stack).policy(adw::ViewSwitcherPolicy::Wide).build();
    let header = adw::HeaderBar::builder().title_widget(&switcher).build();
    let switcher_bar = adw::ViewSwitcherBar::builder().stack(&stack).build();

    // "Показаны данные от …" when the network failed and the cache is shown.
    let banner = adw::Banner::builder().button_label(t("action.retry")).build();
    banner.connect_button_clicked({
        let state = Rc::clone(state);
        move |_| state.refresh()
    });
    let update_banner = {
        let (banner, state) = (banner.clone(), Rc::clone(state));
        move || match state.stale() {
            Some(error) => {
                let mut title = format::error_title(&error);
                if let Some(at) = state.fetched_at() {
                    title = format!("{} · {}", tf("stale.title", &[&format::date_time(at)]), title);
                }
                banner.set_title(&glib::markup_escape_text(&title));
                banner.set_revealed(true);
            }
            None => banner.set_revealed(false),
        }
    };
    update_banner();
    state.subscribe(update_banner);

    let view = adw::ToolbarView::new();
    view.add_top_bar(&header);
    view.add_top_bar(&banner);
    view.set_content(Some(&stack));
    view.add_bottom_bar(&switcher_bar);

    // Narrow windows move the switcher to the bottom, as on GNOME mobile.
    let narrow = adw::Breakpoint::new(adw::BreakpointCondition::parse("max-width: 550sp").expect("breakpoint"));
    narrow.add_setter(&switcher, "visible", Some(&false.to_value()));
    narrow.add_setter(&switcher_bar, "reveal", Some(&true.to_value()));
    window.add_breakpoint(narrow);

    view
}
