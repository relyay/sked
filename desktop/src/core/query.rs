use jiff::{Timestamp, ToSpan, civil, tz::TimeZone};

use super::{Day, GroupDay, Lesson, Note, NoteKind, Subgroup};

/// The college works on Moscow time; "today" is computed in Europe/Moscow so a
/// computer in another zone does not shift the schedule.
pub fn moscow() -> TimeZone {
    // Moscow has been UTC+3 without DST since 2014; the fixed offset is the
    // fallback if the system has no tzdata.
    TimeZone::get("Europe/Moscow").unwrap_or_else(|_| TimeZone::fixed(jiff::tz::offset(3)))
}

/// "YYYY-MM-DD" of `now` in Moscow.
pub fn day_string(now: Timestamp) -> String {
    now.to_zoned(moscow()).date().to_string()
}

pub fn parse_date(day: &str) -> Option<civil::Date> {
    day.parse().ok()
}

/// A Moscow wall-clock time on a given day.
pub fn moscow_time(day: &str, time: &str) -> Option<Timestamp> {
    let date = parse_date(day)?;
    let (h, m) = time.split_once(':')?;
    let time = civil::time(h.parse().ok()?, m.parse().ok()?, 0, 0);
    date.to_datetime(time).to_zoned(moscow()).ok().map(|z| z.timestamp())
}

/// A lesson placed on the timeline.
#[derive(Clone, Debug, PartialEq)]
pub struct ScheduledLesson {
    pub lesson: Lesson,
    pub day: Day,
    pub start: Timestamp,
    pub end: Timestamp,
}

/// What the "next class" card shows.
#[derive(Clone, Debug, PartialEq)]
pub enum CurrentLessonState {
    Ongoing(ScheduledLesson),
    Upcoming(ScheduledLesson),
    /// Today had lessons and all of them are over.
    FinishedForToday,
    /// No lessons today at all (weekend or empty day).
    NoLessonsToday,
}

/// Answers schedule questions for one group and subgroup.
pub struct ScheduleQuery {
    pub days: Vec<Day>,
    pub group: String,
    pub subgroup: Subgroup,
}

/// A lesson without an end time lasts a standard pair.
const DEFAULT_LENGTH_MINUTES: i64 = 90;

impl ScheduleQuery {
    pub fn new(mut days: Vec<Day>, group: impl Into<String>, subgroup: Subgroup) -> Self {
        days.sort_by(|a, b| a.date.cmp(&b.date));
        Self { days, group: group.into(), subgroup }
    }

    pub fn group_day<'a>(&self, day: &'a Day) -> Option<&'a GroupDay> {
        day.groups.iter().find(|g| g.group == self.group)
    }

    /// Whole-group lessons plus the user's subgroup; everything with no
    /// subgroup chosen.
    pub fn lessons(&self, day: &Day) -> Vec<Lesson> {
        let mut out: Vec<Lesson> = self
            .group_day(day)
            .map(|g| g.lessons.iter().filter(|l| self.is_visible(l)).cloned().collect())
            .unwrap_or_default();
        out.sort_by_key(|l| (l.pair, l.subgroup.unwrap_or(0)));
        out
    }

    pub fn is_visible(&self, lesson: &Lesson) -> bool {
        self.subgroup == Subgroup::Unspecified || lesson.subgroup.is_none() || lesson.subgroup == Some(self.subgroup.number())
    }

    fn note_is_visible(&self, note: &Note) -> bool {
        self.subgroup == Subgroup::Unspecified || note.subgroup.is_none() || note.subgroup == Some(self.subgroup.number())
    }

    /// Buildings the user goes to on a day, from the lessons themselves.
    pub fn buildings(&self, day: &Day) -> Vec<i32> {
        let mut out: Vec<i32> = self.lessons(day).iter().map(|l| l.building_or(day.building)).collect();
        out.sort();
        out.dedup();
        if out.is_empty() { vec![day.building] } else { out }
    }

    /// "Classes start at …" («Занятия начинаются с …») for the user's subgroup,
    /// only when it says something the lessons don't: hidden when the first
    /// in-person class already starts at that time (the server aligns derived
    /// Saturday times with it) or when there is no in-person class that day.
    pub fn starts_at(&self, day: &Day) -> Option<String> {
        let time = self
            .group_day(day)?
            .notes
            .iter()
            .find(|n| n.kind == NoteKind::StartsAt && self.note_is_visible(n))?
            .time
            .clone()?;
        let first_in_person =
            self.lessons(day).into_iter().filter(|l| !l.is_remote && !l.start.is_empty()).map(|l| l.start).min()?;
        (first_in_person != time).then_some(time)
    }

    /// Lunch breaks for the user's subgroup, without duplicates (the PDF often
    /// repeats the same lunch in both subgroup columns), earliest first.
    pub fn lunches(&self, day: &Day) -> Vec<Note> {
        let mut seen = std::collections::HashSet::new();
        let mut out: Vec<Note> = self
            .group_day(day)
            .map(|g| {
                g.notes
                    .iter()
                    .filter(|n| n.kind == NoteKind::Lunch && n.time.is_some() && self.note_is_visible(n))
                    .filter(|n| seen.insert((n.time.clone(), n.end_time.clone())))
                    .cloned()
                    .collect()
            })
            .unwrap_or_default();
        out.sort_by(|a, b| a.time.cmp(&b.time));
        out
    }

    pub fn day(&self, now: Timestamp) -> Option<&Day> {
        let key = day_string(now);
        self.days.iter().find(|d| d.date == key)
    }

    /// Days from today on, as far as the PDF goes.
    pub fn upcoming_days(&self, now: Timestamp) -> Vec<Day> {
        let today = day_string(now);
        self.days.iter().filter(|d| d.date >= today).cloned().collect()
    }

    pub fn scheduled(&self, lesson: &Lesson, day: &Day) -> Option<ScheduledLesson> {
        let start = moscow_time(&day.date, &lesson.start)?;
        let end = lesson
            .end
            .as_deref()
            .and_then(|e| moscow_time(&day.date, e))
            .unwrap_or_else(|| start + DEFAULT_LENGTH_MINUTES.minutes());
        Some(ScheduledLesson { lesson: lesson.clone(), day: day.clone(), start, end })
    }

    fn timeline(&self, day: &Day) -> Vec<ScheduledLesson> {
        let mut out: Vec<ScheduledLesson> = self.lessons(day).iter().filter_map(|l| self.scheduled(l, day)).collect();
        out.sort_by_key(|s| s.start);
        out
    }

    pub fn current(&self, now: Timestamp) -> CurrentLessonState {
        let Some(today) = self.day(now) else { return CurrentLessonState::NoLessonsToday };
        let timeline = self.timeline(today);
        if timeline.is_empty() {
            return CurrentLessonState::NoLessonsToday;
        }
        if let Some(s) = timeline.iter().find(|s| s.start <= now && now < s.end) {
            return CurrentLessonState::Ongoing(s.clone());
        }
        if let Some(s) = timeline.into_iter().find(|s| s.start > now) {
            return CurrentLessonState::Upcoming(s);
        }
        CurrentLessonState::FinishedForToday
    }

    /// The next upcoming lesson after `now`, today only.
    pub fn next_lesson_today(&self, now: Timestamp) -> Option<ScheduledLesson> {
        let today = self.day(now)?;
        self.timeline(today).into_iter().find(|s| s.start > now)
    }
}

