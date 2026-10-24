//! Schedule: a day with date chips, or the whole week.

use std::cell::RefCell;
use std::rc::Rc;

use adw::prelude::*;
use gtk::glib;
use jiff::Timestamp;

use super::widgets::{boxed_list, card, day_notes, label, lesson_row, pair_number, rebuild_keeping_scroll, scrolled_page};
use crate::core::{self, Day, Lesson, ScheduleQuery};
use crate::format;
use crate::i18n::t;
use crate::state::{AppState, ScheduleState};

#[derive(Clone, Copy, PartialEq)]
enum Mode {
    Day,
    Week,
}

pub fn page(state: &Rc<AppState>) -> gtk::Widget {
    let mode = Rc::new(RefCell::new(Mode::Day));
    let selected = Rc::new(RefCell::new(None::<String>));

    let toggles = adw::ToggleGroup::builder().halign(gtk::Align::Center).margin_top(12).build();
    toggles.add(adw::Toggle::builder().name("day").label(t("schedule.day")).build());
    toggles.add(adw::Toggle::builder().name("week").label(t("schedule.week")).build());
    toggles.set_active_name(Some("day"));

    let stack = gtk::Stack::new();
    let (scrolled, content) = scrolled_page();
    stack.add_named(&scrolled, Some("content"));
    let spinner = adw::Spinner::builder().width_request(32).height_request(32).halign(gtk::Align::Center).valign(gtk::Align::Center).build();
    stack.add_named(&spinner, Some("loading"));
    let message = adw::StatusPage::new();
    stack.add_named(&message, Some("message"));

    let outer = gtk::Box::builder().orientation(gtk::Orientation::Vertical).build();
    outer.append(&toggles);
    outer.append(&stack);

    let render: Rc<dyn Fn()> = Rc::new({
        let (state, mode, selected) = (Rc::clone(state), Rc::clone(&mode), Rc::clone(&selected));
        let weak_render: Rc<RefCell<Option<Rc<dyn Fn()>>>> = Rc::new(RefCell::new(None));
        let this = Rc::clone(&weak_render);
        let render = move || {
            match state.schedule_state() {
                ScheduleState::Idle | ScheduleState::Loading => stack.set_visible_child_name("loading"),
                ScheduleState::Failed(error) => {
                    message.set_title(&format::error_title(&error));
                    message.set_description(Some(&glib::markup_escape_text(&format::error_recovery(&error))));
                    stack.set_visible_child_name("message");
                }
                ScheduleState::Loaded(_) => {
                    let Some(query) = state.query() else { return };
                    let now = Timestamp::now();
                    let days = query.upcoming_days(now);
                    if days.is_empty() {
                        message.set_title(t("schedule.noDays"));
                        message.set_description(Some(t("schedule.noDaysHint")));
                        stack.set_visible_child_name("message");
                        return;
                    }
                    let rerender = this.borrow().clone();
                    rebuild_keeping_scroll(&scrolled, &content, |content| match *mode.borrow() {
                        Mode::Day => day_view(content, &query, &days, &selected, now, rerender),
                        Mode::Week => week_view(content, &query, &days, now),
                    });
                    stack.set_visible_child_name("content");
                }
            }
        };
        let render: Rc<dyn Fn()> = Rc::new(render);
        *weak_render.borrow_mut() = Some(Rc::clone(&render));
        move || render()
    });

    toggles.connect_active_name_notify({
        let (mode, render) = (Rc::clone(&mode), Rc::clone(&render));
        move |toggles| {
            *mode.borrow_mut() = if toggles.active_name().as_deref() == Some("week") { Mode::Week } else { Mode::Day };
            render();
        }
    });

    render();
    state.subscribe({
        let render = Rc::clone(&render);
        move || render()
    });
    glib::timeout_add_seconds_local(60, move || {
        render();
        glib::ControlFlow::Continue
    });
    outer.upcast()
}

fn day_view(
    content: &gtk::Box,
    query: &ScheduleQuery,
    days: &[Day],
    selected: &Rc<RefCell<Option<String>>>,
    now: Timestamp,
    rerender: Option<Rc<dyn Fn()>>,
) {
    let current = selected.borrow().clone();
    let day = days.iter().find(|d| Some(&d.date) == current.as_ref()).unwrap_or(&days[0]).clone();

    // Date chips: today onwards, as far as the PDF goes.
    let chips = gtk::Box::builder().spacing(6).build();
    let mut group: Option<gtk::ToggleButton> = None;
    for chip_day in days {
        let inner = gtk::Box::builder().orientation(gtk::Orientation::Vertical).build();
        inner.append(&label_centered(&format::chip_weekday(chip_day), "weekday"));
        inner.append(&label_centered(&format::day_number(chip_day), "number"));
        let button = gtk::ToggleButton::builder().child(&inner).active(chip_day.date == day.date).build();
        button.add_css_class("date-chip");
        button.add_css_class("flat");
        let description = [Some(format::long_day(chip_day)), format::relative_day(chip_day, now)].into_iter().flatten().collect::<Vec<_>>().join(", ");
        button.set_tooltip_text(Some(&description));
        if let Some(first) = &group {
            button.set_group(Some(first));
        } else {
            group = Some(button.clone());
        }
        let (date, selected, rerender) = (chip_day.date.clone(), Rc::clone(selected), rerender.clone());
        button.connect_toggled(move |b| {
            if b.is_active() && selected.borrow().as_deref() != Some(&date) {
                *selected.borrow_mut() = Some(date.clone());
                if let Some(r) = &rerender {
                    // Rebuild after the toggle finishes processing.
                    let r = Rc::clone(r);
                    glib::idle_add_local_once(move || r());
                }
            }
        });
        chips.append(&button);
    }
    let chip_scroll = gtk::ScrolledWindow::builder()
        .vscrollbar_policy(gtk::PolicyType::Never)
        .hscrollbar_policy(gtk::PolicyType::Automatic)
        .child(&chips)
        .build();
    content.append(&chip_scroll);

    // "Пятница, 23 октября · сегодня · корпус 2".
    let title = [Some(format::long_day(&day)), format::relative_day(&day, now), Some(format::buildings(&query.buildings(&day)))]
        .into_iter()
        .flatten()
        .collect::<Vec<_>>()
        .join(" · ");
    content.append(&label(&title, &["title-2"]));

    if day.date == core::day_string(now) {
        if let Some(next) = query.next_lesson_today(now) {
            let hint = card();
            let text = [t("schedule.next").to_owned(), format::pair_number(&next.lesson), format::countdown(now, next.start)].join(" · ");
            hint.append(&label(&text, &["heading", "accent"]));
            content.append(&hint);
        }
    }

    if let Some(notes) = day_notes(query.starts_at(&day), &query.lunches(&day)) {
        content.append(&notes);
    }

    let lessons = query.lessons(&day);
    if lessons.is_empty() {
        let empty = label(t("schedule.empty"), &["title-3", "dim-label"]);
        empty.set_xalign(0.5);
        empty.set_margin_top(48);
        content.append(&empty);
    } else {
        let list = boxed_list();
        for lesson in &lessons {
            list.append(&lesson_row(lesson));
        }
        content.append(&list);
    }
}

fn week_view(content: &gtk::Box, query: &ScheduleQuery, days: &[Day], now: Timestamp) {
    for day in days {
        // "Пт, 23.10 · сегодня · корпус 2".
        let header = [Some(format::short_day(day)), format::relative_day(day, now), Some(format::buildings(&query.buildings(day)))]
            .into_iter()
            .flatten()
            .collect::<Vec<_>>()
            .join(" · ");
        let card = card();
        card.append(&label(&header, &["heading"]));
        if let Some(notes) = day_notes(query.starts_at(day), &query.lunches(day)) {
            card.append(&notes);
        }
        let lessons = query.lessons(day);
        if lessons.is_empty() {
            card.append(&label(t("schedule.empty"), &["dim-label"]));
        } else {
            for lesson in &lessons {
                card.append(&compact_row(lesson));
            }
        }
        content.append(&card);
    }
}

/// Numbered circle, then subject, time range and place.
fn compact_row(lesson: &Lesson) -> gtk::Box {
    let row = gtk::Box::builder().spacing(12).margin_top(4).margin_bottom(4).build();
    row.append(&pair_number(lesson, true));
    let text = gtk::Box::builder().orientation(gtk::Orientation::Vertical).valign(gtk::Align::Center).build();
    text.append(&label(&lesson.subject, &["heading"]));
    text.append(&label(&format::time_range(lesson), &["caption", "dim-label"]));
    let place = format::place(lesson);
    if !place.is_empty() {
        text.append(&label(&place, &["caption", "dim-label"]));
    }
    row.append(&text);
    row
}

fn label_centered(text: &str, class: &str) -> gtk::Label {
    let l = gtk::Label::builder().label(text).build();
    l.add_css_class(class);
    l
}
