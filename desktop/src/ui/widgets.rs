//! Small building blocks shared by the pages.

use adw::prelude::*;
use gtk::glib;

use crate::core::{Lesson, Note};
use crate::format;
use crate::i18n::{t, tf};

/// Removes every child of a box (pages rebuild themselves on state changes).
pub fn clear(container: &gtk::Box) {
    while let Some(child) = container.first_child() {
        container.remove(&child);
    }
}

/// Rebuilds the box while keeping the scroll position, so the minute tick and
/// background refreshes don't jump the list back to the top.
pub fn rebuild_keeping_scroll(scrolled: &gtk::ScrolledWindow, container: &gtk::Box, build: impl FnOnce(&gtk::Box)) {
    let value = scrolled.vadjustment().value();
    clear(container);
    build(container);
    let adjustment = scrolled.vadjustment();
    glib::idle_add_local_once(move || adjustment.set_value(value));
}

pub fn label(text: &str, classes: &[&str]) -> gtk::Label {
    let label = gtk::Label::builder().label(text).xalign(0.0).wrap(true).wrap_mode(gtk::pango::WrapMode::WordChar).build();
    for c in classes {
        label.add_css_class(c);
    }
    label
}

/// Page content: scrollable, centred and width-limited per the GNOME HIG.
pub fn scrolled_page() -> (gtk::ScrolledWindow, gtk::Box) {
    let content = gtk::Box::builder()
        .orientation(gtk::Orientation::Vertical)
        .spacing(18)
        .margin_top(24)
        .margin_bottom(24)
        .margin_start(12)
        .margin_end(12)
        .build();
    let clamp = adw::Clamp::builder().maximum_size(640).child(&content).build();
    let scrolled = gtk::ScrolledWindow::builder().hscrollbar_policy(gtk::PolicyType::Never).vexpand(true).child(&clamp).build();
    (scrolled, content)
}

/// A rounded "card" container.
pub fn card() -> gtk::Box {
    let card = gtk::Box::builder().orientation(gtk::Orientation::Vertical).spacing(6).build();
    card.add_css_class("card");
    card.add_css_class("sked-card");
    card
}

/// The pair number in a tinted circle.
pub fn pair_number(lesson: &Lesson, compact: bool) -> gtk::Label {
    let label = gtk::Label::builder().label(lesson.pair_label()).valign(gtk::Align::Center).build();
    label.add_css_class("pair-number");
    if compact {
        label.add_css_class("compact");
    }
    label
}

/// One lesson in the day list: subject, then time, then place.
pub fn lesson_row(lesson: &Lesson) -> adw::ActionRow {
    let mut lines = vec![format::time_range(lesson), format::place(lesson)];
    if let Some(note) = &lesson.note {
        lines.push(note.clone());
    }
    let subtitle = lines.into_iter().filter(|l| !l.is_empty()).collect::<Vec<_>>().join("\n");
    let row = adw::ActionRow::builder().title(glib::markup_escape_text(&lesson.subject)).subtitle(glib::markup_escape_text(&subtitle)).build();
    row.add_css_class("property");
    row.add_prefix(&pair_number(lesson, false));
    row.set_tooltip_text(Some(&format::pair_number(lesson)));
    row
}

/// "Занятия начинаются с …" and lunch breaks: the only lines with icons.
pub fn day_notes(starts_at: Option<String>, lunches: &[Note]) -> Option<gtk::Box> {
    if starts_at.is_none() && lunches.is_empty() {
        return None;
    }
    let notes = gtk::Box::builder().orientation(gtk::Orientation::Vertical).spacing(4).build();
    if let Some(time) = starts_at {
        notes.append(&note_line("alarm-symbolic", &tf("home.startsAt", &[&time])));
    }
    for lunch in lunches {
        notes.append(&note_line("emoji-food-symbolic", &format::lunch(lunch)));
    }
    Some(notes)
}

fn note_line(icon: &str, text: &str) -> gtk::Box {
    let line = gtk::Box::builder().spacing(8).build();
    line.append(&gtk::Image::from_icon_name(icon));
    line.append(&label(text, &[]));
    line.add_css_class("dim-label");
    line
}

/// A list with the boxed-list style.
pub fn boxed_list() -> gtk::ListBox {
    let list = gtk::ListBox::builder().selection_mode(gtk::SelectionMode::None).build();
    list.add_css_class("boxed-list");
    list
}

/// Title, recovery hint and Retry inside a preferences group (no icon).
pub fn error_group(title: &str, message: &str, on_retry: impl Fn() + 'static) -> adw::PreferencesGroup {
    let group = adw::PreferencesGroup::builder().title(glib::markup_escape_text(title)).description(glib::markup_escape_text(message)).build();
    let retry = adw::ButtonRow::builder().title(t("action.retry")).build();
    retry.connect_activated(move |_| on_retry());
    group.add(&retry);
    group
}
