//! User-facing formatting of schedule data, in the UI language.

use jiff::{Timestamp, civil::Weekday, tz::TimeZone};

use crate::api::ApiError;
use crate::core::{self, Day, Lesson, Note, Subgroup};
use crate::i18n::{Lang, lang, t, tf};

/// "08:30 – 10:00".
pub fn time_range(lesson: &Lesson) -> String {
    match &lesson.end {
        Some(end) => format!("{} – {}", lesson.start, end),
        None => lesson.start.clone(),
    }
}

/// "каб. 15/2 · Петров С.И." or "дистант · Петров С.И.".
pub fn place(lesson: &Lesson) -> String {
    let mut parts = Vec::new();
    if lesson.is_remote {
        parts.push(t("lesson.remote").to_owned());
    } else if let Some(room) = &lesson.room {
        parts.push(tf("lesson.room", &[room]));
    }
    if let Some(teacher) = &lesson.teacher {
        parts.push(teacher.clone());
    }
    parts.join(" · ")
}

pub fn pair_number(lesson: &Lesson) -> String {
    tf("lesson.pairNumber", &[&lesson.pair_label()])
}

/// "начнётся через 2 ч 13 мин"; rounds up so it never says "0 мин".
pub fn countdown(now: Timestamp, target: Timestamp) -> String {
    let seconds = target.as_second() - now.as_second();
    let minutes = ((seconds + 59) / 60).max(1);
    let text = if minutes >= 24 * 60 {
        tf("duration.dh", &[&(minutes / 1440).to_string(), &((minutes % 1440) / 60).to_string()])
    } else if minutes >= 60 {
        tf("duration.hm", &[&(minutes / 60).to_string(), &(minutes % 60).to_string()])
    } else {
        tf("duration.m", &[&minutes.to_string()])
    };
    tf("countdown.in", &[&text])
}

pub fn building(number: i32) -> String {
    tf("building.short", &[&number.to_string()])
}

/// "корпус 1" or "корпуса 1, 2" when a day spans both.
pub fn buildings(numbers: &[i32]) -> String {
    if numbers.len() > 1 {
        let list = numbers.iter().map(i32::to_string).collect::<Vec<_>>().join(", ");
        tf("building.many", &[&list])
    } else {
        building(numbers.first().copied().unwrap_or(0))
    }
}

/// "Обед 10:55–11:20", or "Обед с 10:55" when the PDF gives no end.
pub fn lunch(note: &Note) -> String {
    match (&note.time, &note.end_time) {
        (Some(time), Some(end)) => tf("lunch.range", &[time, end]),
        (Some(time), None) => tf("lunch.from", &[time]),
        _ => note.text.clone(),
    }
}

pub fn subgroup_name(subgroup: Subgroup) -> String {
    match subgroup {
        Subgroup::Unspecified => t("subgroup.unspecified").to_owned(),
        s => tf("subgroup.badge", &[&s.number().to_string()]),
    }
}

const RU_WEEKDAYS: [&str; 7] = ["понедельник", "вторник", "среда", "четверг", "пятница", "суббота", "воскресенье"];
const RU_WEEKDAYS_SHORT: [&str; 7] = ["пн", "вт", "ср", "чт", "пт", "сб", "вс"];
const EN_WEEKDAYS: [&str; 7] = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
const EN_WEEKDAYS_SHORT: [&str; 7] = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
// Genitive, as in "23 октября".
const RU_MONTHS: [&str; 12] = [
    "января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря",
];
const RU_MONTHS_SHORT: [&str; 12] = ["янв.", "февр.", "мар.", "апр.", "мая", "июн.", "июл.", "авг.", "сент.", "окт.", "нояб.", "дек."];
const EN_MONTHS: [&str; 12] = [
    "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December",
];
const EN_MONTHS_SHORT: [&str; 12] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

fn weekday_index(w: Weekday) -> usize {
    w.to_monday_zero_offset() as usize
}

fn capitalized(s: &str) -> String {
    let mut c = s.chars();
    c.next().map(|f| f.to_uppercase().collect::<String>() + c.as_str()).unwrap_or_default()
}

/// "Пятница, 23 октября" / "Friday, October 23".
pub fn long_day(day: &Day) -> String {
    let Some(d) = core::parse_date(&day.date) else { return day.date.clone() };
    let (w, m) = (weekday_index(d.weekday()), d.month() as usize - 1);
    match lang() {
        Lang::Ru => format!("{}, {} {}", capitalized(RU_WEEKDAYS[w]), d.day(), RU_MONTHS[m]),
        Lang::En => format!("{}, {} {}", EN_WEEKDAYS[w], EN_MONTHS[m], d.day()),
    }
}

/// "Пт, 23.10".
pub fn short_day(day: &Day) -> String {
    let Some(d) = core::parse_date(&day.date) else { return day.date.clone() };
    format!("{}, {:02}.{:02}", chip_weekday(day), d.day(), d.month())
}

/// "Пт" / "Fri".
pub fn chip_weekday(day: &Day) -> String {
    let Some(d) = core::parse_date(&day.date) else { return String::new() };
    let w = weekday_index(d.weekday());
    match lang() {
        Lang::Ru => capitalized(RU_WEEKDAYS_SHORT[w]),
        Lang::En => EN_WEEKDAYS_SHORT[w].to_owned(),
    }
}

pub fn day_number(day: &Day) -> String {
    core::parse_date(&day.date).map(|d| d.day().to_string()).unwrap_or_default()
}

/// "сегодня" / "завтра" relative to now, or None.
pub fn relative_day(day: &Day, now: Timestamp) -> Option<String> {
    let today = now.to_zoned(core::moscow()).date();
    if day.date == today.to_string() {
        Some(t("day.today").to_owned())
    } else if today.tomorrow().ok().map(|d| d.to_string()).as_deref() == Some(day.date.as_str()) {
        Some(t("day.tomorrow").to_owned())
    } else {
        None
    }
}

/// "23 окт., 12:29" in the computer's time zone.
pub fn date_time(ts: Timestamp) -> String {
    let z = ts.to_zoned(TimeZone::system());
    let m = z.month() as usize - 1;
    match lang() {
        Lang::Ru => format!("{} {}, {:02}:{:02}", z.day(), RU_MONTHS_SHORT[m], z.hour(), z.minute()),
        Lang::En => format!("{} {}, {:02}:{:02}", EN_MONTHS_SHORT[m], z.day(), z.hour(), z.minute()),
    }
}

pub fn error_title(error: &ApiError) -> String {
    match error {
        ApiError::CannotConnect(host) => tf("error.cannotConnect", &[host]),
        ApiError::TimedOut => t("error.timedOut").to_owned(),
        ApiError::Offline => t("error.offline").to_owned(),
        ApiError::NotLoadedYet => t("error.notLoadedYet").to_owned(),
        ApiError::Server { status, message: Some(m) } => tf("error.serverMessage", &[&status.to_string(), m]),
        ApiError::Server { status, message: None } => tf("error.server", &[&status.to_string()]),
        ApiError::BadResponse => t("error.badResponse").to_owned(),
    }
}

pub fn error_recovery(error: &ApiError) -> String {
    match error {
        ApiError::CannotConnect(_) => t("error.recovery.checkServer"),
        ApiError::Offline => t("error.recovery.offline"),
        _ => t("error.recovery.retryLater"),
    }
    .to_owned()
}
