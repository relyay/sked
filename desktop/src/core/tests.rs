// Mirrors ios/Tests/SkedCoreTests and android/app/src/test so all clients
// follow the same rules.

use jiff::Timestamp;

use super::*;

fn moscow_at(day: &str, time: &str) -> Timestamp {
    moscow_time(day, time).unwrap()
}

fn lesson(pair: i32, start: &str, end: &str, subject: &str) -> Lesson {
    Lesson { pair, start: start.into(), end: Some(end.into()), subject: subject.into(), ..Default::default() }
}

fn friday() -> Day {
    Day {
        date: "2026-10-23".into(),
        building: 1,
        groups: vec![GroupDay {
            group: "ИСП-225а".into(),
            lessons: vec![
                Lesson { room: Some("17/1".into()), subgroup: Some(1), ..lesson(1, "08:30", "10:00", "ОСиС") },
                Lesson { room: Some("119/1".into()), subgroup: Some(2), ..lesson(2, "10:10", "11:40", "Ино. в проф.деят.") },
                Lesson { room: Some("24/1".into()), ..lesson(3, "12:10", "13:40", "ПОПД") },
                Lesson { room: Some("17/1".into()), subgroup: Some(2), ..lesson(4, "13:50", "15:20", "ОСиС") },
            ],
            notes: vec![],
        }],
        ..Default::default()
    }
}

fn saturday() -> Day {
    Day {
        date: "2026-10-24".into(),
        building: 1,
        groups: vec![GroupDay {
            group: "ИСП-225а".into(),
            lessons: vec![
                Lesson { room: Some("24/1".into()), subgroup: Some(2), ..lesson(3, "12:10", "13:10", "ПОПД") },
                Lesson { is_remote: true, subgroup: Some(2), time_source: Some("bells".into()), ..lesson(5, "15:40", "17:10", "ОСиС") },
            ],
            notes: vec![Note { kind: NoteKind::StartsAt, text: "Занятия начинаются с 11:10".into(), time: Some("11:10".into()), subgroup: Some(2), ..Default::default() }],
        }],
        ..Default::default()
    }
}

fn monday() -> Day {
    Day {
        date: "2026-10-26".into(),
        building: 1,
        groups: vec![GroupDay {
            group: "ИСП-225а".into(),
            lessons: vec![
                Lesson { room: Some("24/1".into()), ..lesson(2, "10:10", "11:40", "ПОПД") },
                Lesson { room: Some("24/1".into()), ..lesson(3, "12:10", "13:40", "ПОПД") },
            ],
            notes: vec![],
        }],
        ..Default::default()
    }
}

fn query(subgroup: Subgroup) -> ScheduleQuery {
    ScheduleQuery::new(vec![monday(), saturday(), friday()], "ИСП-225а", subgroup)
}

#[test]
fn ongoing_lesson() {
    match query(Subgroup::First).current(moscow_at("2026-10-23", "09:00")) {
        CurrentLessonState::Ongoing(s) => assert_eq!(s.lesson.pair, 1),
        other => panic!("{other:?}"),
    }
}

#[test]
fn skips_other_subgroup() {
    // Subgroup 1 has nothing in pair 2, so after pair 1 the next is pair 3.
    match query(Subgroup::First).current(moscow_at("2026-10-23", "10:05")) {
        CurrentLessonState::Upcoming(s) => assert_eq!(s.lesson.pair, 3),
        other => panic!("{other:?}"),
    }
}

#[test]
fn break_between_pairs_is_upcoming() {
    match query(Subgroup::Second).current(moscow_at("2026-10-23", "10:00")) {
        CurrentLessonState::Upcoming(s) => {
            assert_eq!(s.lesson.pair, 2);
            assert_eq!(s.start, moscow_at("2026-10-23", "10:10"));
        }
        other => panic!("{other:?}"),
    }
}

#[test]
fn finished_for_today() {
    assert_eq!(query(Subgroup::First).current(moscow_at("2026-10-23", "13:40")), CurrentLessonState::FinishedForToday);
}

#[test]
fn no_lessons_on_sunday() {
    assert_eq!(query(Subgroup::First).current(moscow_at("2026-10-25", "09:00")), CurrentLessonState::NoLessonsToday);
}

#[test]
fn unknown_group_has_no_lessons() {
    let q = ScheduleQuery::new(vec![friday()], "НЕТ-000", Subgroup::Unspecified);
    assert_eq!(q.current(moscow_at("2026-10-23", "09:00")), CurrentLessonState::NoLessonsToday);
}

#[test]
fn other_subgroup_is_hidden() {
    assert_eq!(query(Subgroup::First).lessons(&friday()).iter().map(|l| l.pair).collect::<Vec<_>>(), vec![1, 3]);
}

#[test]
fn unspecified_subgroup_sees_everything() {
    assert_eq!(query(Subgroup::Unspecified).lessons(&friday()).len(), 4);
}

#[test]
fn today_uses_moscow_not_local_zone() {
    // 23:30 in Moscow on Friday is already Saturday in Vladivostok.
    let late_friday = moscow_at("2026-10-23", "23:30");
    let vladivostok = jiff::tz::TimeZone::get("Asia/Vladivostok").unwrap();
    assert_eq!(late_friday.to_zoned(vladivostok).day(), 24);
    assert_eq!(query(Subgroup::First).day(late_friday).map(|d| d.date.as_str()), Some("2026-10-23"));
}

#[test]
fn starts_at_follows_subgroup() {
    // Subgroup 2's first in-person class is at 12:10, later than the note.
    assert_eq!(query(Subgroup::Second).starts_at(&saturday()).as_deref(), Some("11:10"));
    assert_eq!(query(Subgroup::First).starts_at(&saturday()), None);
}

#[test]
fn starts_at_hidden_when_redundant() {
    let note = Note { kind: NoteKind::StartsAt, text: "Занятия начинаются с 11:50".into(), time: Some("11:50".into()), ..Default::default() };
    let day = Day {
        date: "2026-10-24".into(),
        building: 2,
        groups: vec![GroupDay {
            group: "ИСП-225ис".into(),
            lessons: vec![
                Lesson { is_remote: true, ..lesson(1, "09:00", "10:00", "ПОПД") },
                Lesson { room: Some("СЗ/2".into()), time_source: Some("startsAt".into()), ..lesson(3, "11:50", "12:50", "Физ. культура") },
            ],
            notes: vec![note.clone()],
        }],
        ..Default::default()
    };
    let remote_only = Day {
        date: "2026-10-31".into(),
        building: 2,
        groups: vec![GroupDay {
            group: "ИСП-225ис".into(),
            lessons: vec![Lesson { is_remote: true, ..lesson(1, "09:00", "10:00", "ПОПД") }],
            notes: vec![note],
        }],
        ..Default::default()
    };
    let q = ScheduleQuery::new(vec![day.clone(), remote_only.clone()], "ИСП-225ис", Subgroup::Unspecified);
    assert_eq!(q.starts_at(&day), None);
    assert_eq!(q.starts_at(&remote_only), None);
}

fn lunch_day() -> Day {
    let lunch = |time: &str, end: &str, pair: i32, subgroup: i32| Note {
        kind: NoteKind::Lunch,
        text: format!("Обед {time}-{end}"),
        time: Some(time.into()),
        end_time: Some(end.into()),
        pair: Some(pair),
        subgroup: Some(subgroup),
    };
    Day {
        date: "2026-10-23".into(),
        building: 1,
        groups: vec![GroupDay {
            group: "ДО-324".into(),
            lessons: vec![],
            notes: vec![
                lunch("10:55", "11:20", 3, 1),
                lunch("10:55", "11:20", 5, 2),
                lunch("11:40", "12:10", 4, 2),
                Note { kind: NoteKind::StartsAt, text: "Занятия начинаются с 11:10".into(), time: Some("11:10".into()), ..Default::default() },
            ],
        }],
        ..Default::default()
    }
}

#[test]
fn lunches_filter_by_subgroup() {
    let q = ScheduleQuery::new(vec![lunch_day()], "ДО-324", Subgroup::First);
    assert_eq!(q.lunches(&lunch_day()).iter().map(|n| n.time.clone().unwrap()).collect::<Vec<_>>(), vec!["10:55"]);
}

#[test]
fn lunches_deduplicate_across_subgroups() {
    let q = ScheduleQuery::new(vec![lunch_day()], "ДО-324", Subgroup::Unspecified);
    assert_eq!(q.lunches(&lunch_day()).iter().map(|n| n.time.clone().unwrap()).collect::<Vec<_>>(), vec!["10:55", "11:40"]);
}

#[test]
fn zero_building_falls_back_to_day() {
    assert_eq!(Lesson { building: Some(0), ..lesson(1, "08:30", "10:00", "X") }.building_or(2), 2);
    assert_eq!(Lesson { building: Some(1), ..lesson(1, "08:30", "10:00", "X") }.building_or(2), 1);
}

#[test]
fn building_comes_from_lessons() {
    let day = Day {
        date: "2026-10-24".into(),
        building: 1,
        groups: vec![GroupDay {
            group: "ИСП-225ис".into(),
            lessons: vec![
                Lesson { building: Some(2), is_remote: true, ..lesson(1, "09:00", "10:00", "ПОПД") },
                Lesson { building: Some(2), room: Some("СЗ/2".into()), ..lesson(3, "11:50", "12:50", "Физ. культура") },
            ],
            notes: vec![],
        }],
        ..Default::default()
    };
    assert_eq!(ScheduleQuery::new(vec![day.clone()], "ИСП-225ис", Subgroup::Unspecified).buildings(&day), vec![2]);
}

#[test]
fn decodes_server_payload() {
    let json = r#"
        {"group":"ЭСС-225","parsedAt":"2026-10-23T12:10:49.316279998+03:00",
         "sourceModified":"2026-10-23T08:52:17Z",
         "days":[{"date":"2026-10-24","weekday":"суббота","building":1,"groups":[{"group":"ЭСС-225",
           "lessons":[{"pair":1,"building":2,"pairTo":6,"start":"08:30","end":"18:50","subject":"Экзамен","isRemote":false,"timeSource":"bells"}],
           "notes":[{"kind":"somethingNew","text":"?"}]}]}]}
    "#;
    let r: ScheduleResponse = serde_json::from_str(json).unwrap();
    let group = &r.days[0].groups[0];
    assert_eq!(group.lessons[0].pair_label(), "1–6");
    assert_eq!(group.notes[0].kind, NoteKind::Other);
    assert_eq!(group.lessons[0].building, Some(2));
    let parsed: Timestamp = r.parsed_at.parse().unwrap();
    assert_eq!(parsed.as_millisecond(), 1_792_746_649_316);
}

#[test]
fn requires_name() {
    let groups = vec![GroupInfo { name: "ИСП-225а".into(), course: 2, buildings: vec![1, 2] }];
    let draft = ProfileDraft { full_name: "   ".into(), group: Some("ИСП-225а".into()), ..Default::default() };
    assert_eq!(draft.validate(&groups), Err(DraftProblem::EmptyName));
}

#[test]
fn group_must_come_from_server_list() {
    let groups = vec![GroupInfo { name: "ИСП-225а".into(), course: 2, buildings: vec![1, 2] }];
    let draft = ProfileDraft { full_name: "Иванов Иван".into(), group: Some("ИСП-999".into()), ..Default::default() };
    assert_eq!(draft.validate(&groups), Err(DraftProblem::UnknownGroup));
    let draft = ProfileDraft { full_name: "Иванов Иван".into(), group: Some("ИСП-225а".into()), subgroup: Subgroup::Second };
    assert_eq!(
        draft.validate(&groups),
        Ok(Profile { full_name: "Иванов Иван".into(), group: "ИСП-225а".into(), course: 2, subgroup: Subgroup::Second })
    );
}
