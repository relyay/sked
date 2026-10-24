//! Home: greeting and the current / next class.

use std::rc::Rc;

use adw::prelude::*;
use gtk::glib;
use jiff::Timestamp;

use super::widgets::{card, clear, label, scrolled_page};
use crate::core::{CurrentLessonState, Lesson, ScheduledLesson, Subgroup};
use crate::format;
use crate::i18n::{t, tf};
use crate::state::{AppState, ScheduleState};

pub fn page(state: &Rc<AppState>) -> gtk::Widget {
    let stack = gtk::Stack::new();
    let (scrolled, content) = scrolled_page();
    stack.add_named(&scrolled, Some("content"));
    let spinner = adw::Spinner::builder().width_request(32).height_request(32).halign(gtk::Align::Center).valign(gtk::Align::Center).build();
    stack.add_named(&spinner, Some("loading"));
    let failed = adw::StatusPage::new();
    let retry = gtk::Button::builder().label(t("action.retry")).halign(gtk::Align::Center).build();
    retry.add_css_class("pill");
    retry.add_css_class("suggested-action");
    retry.connect_clicked({
        let state = Rc::clone(state);
        move |_| state.refresh()
    });
    failed.set_child(Some(&retry));
    stack.add_named(&failed, Some("failed"));

    let render = {
        let (state, stack) = (Rc::clone(state), stack.clone());
        move || match state.schedule_state() {
            ScheduleState::Idle | ScheduleState::Loading => stack.set_visible_child_name("loading"),
            ScheduleState::Failed(error) => {
                failed.set_title(&format::error_title(&error));
                failed.set_description(Some(&glib::markup_escape_text(&format::error_recovery(&error))));
                stack.set_visible_child_name("failed");
            }
            ScheduleState::Loaded(_) => {
                clear(&content);
                content.append(&label(&greeting(&state), &["title-1"]));
                if let Some(query) = state.query() {
                    let now = Timestamp::now();
                    content.append(&current_card(query.current(now), now));
                }
                stack.set_visible_child_name("content");
            }
        }
    };
    render();
    state.subscribe(render.clone());
    // Re-render every 30 s for the countdown.
    glib::timeout_add_seconds_local(30, move || {
        render();
        glib::ControlFlow::Continue
    });
    stack.upcast()
}

/// "Привет, Имя" from "Фамилия Имя Отчество".
fn greeting(state: &AppState) -> String {
    let name = state.profile().map(|p| p.full_name).unwrap_or_default();
    let words: Vec<&str> = name.split_whitespace().collect();
    match words.get(1).or(words.first()) {
        Some(first) => tf("home.greeting", &[first]),
        None => t("tab.home").to_owned(),
    }
}

fn current_card(state: CurrentLessonState, now: Timestamp) -> gtk::Box {
    match state {
        CurrentLessonState::Ongoing(s) => lesson_card(&s, t("home.ongoing").to_owned(), true),
        CurrentLessonState::Upcoming(s) => lesson_card(&s, format::countdown(now, s.start), false),
        CurrentLessonState::FinishedForToday => message_card(t("home.finished")),
        CurrentLessonState::NoLessonsToday => message_card(t("home.noLessonsToday")),
    }
}

fn lesson_card(s: &ScheduledLesson, status: String, ongoing: bool) -> gtk::Box {
    let lesson = &s.lesson;
    let card = card();
    card.append(&label(&t("home.nextLesson").to_uppercase(), &["caption-heading", "dim-label"]));
    card.append(&label(&headline(lesson, lesson.building_or(s.day.building)), &["title-3"]));
    if let Some(teacher) = &lesson.teacher {
        card.append(&label(teacher, &["dim-label"]));
    }
    if let Some(sub) = lesson.subgroup {
        card.append(&label(&format::subgroup_name(Subgroup::of(sub)), &["dim-label"]));
    }
    let status = label(&status, &["heading", if ongoing { "success" } else { "accent" }]);
    status.set_margin_top(4);
    card.append(&status);
    card
}

/// "2 пара · ОБиЗР · 14:30 · корпус 2, каб. 15/2".
fn headline(lesson: &Lesson, building: i32) -> String {
    let place = if lesson.is_remote {
        t("lesson.remote").to_owned()
    } else if let Some(room) = &lesson.room {
        tf("home.buildingRoom", &[&building.to_string(), room])
    } else {
        format::building(building)
    };
    [format::pair_number(lesson), lesson.subject.clone(), lesson.start.clone(), place].join(" · ")
}

fn message_card(text: &str) -> gtk::Box {
    let card = card();
    card.append(&label(text, &["title-4"]));
    card
}
