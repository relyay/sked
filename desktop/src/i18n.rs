//! Russian (default) and English strings, mirroring the mobile clients'
//! resources. English is used only when the system language is English.

use std::sync::OnceLock;

use gtk::glib;

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Lang {
    Ru,
    En,
}

pub fn lang() -> Lang {
    static LANG: OnceLock<Lang> = OnceLock::new();
    *LANG.get_or_init(|| {
        let first = glib::language_names().into_iter().find(|l| l.as_str() != "C" && l.as_str() != "POSIX");
        match first {
            Some(l) if l.starts_with("en") => Lang::En,
            _ => Lang::Ru,
        }
    })
}

/// A localized string; `{0}`, `{1}` are replaced by `args`.
pub fn tf(key: &str, args: &[&str]) -> String {
    let mut s = t(key).to_owned();
    for (i, a) in args.iter().enumerate() {
        s = s.replace(&format!("{{{i}}}"), a);
    }
    s
}

pub fn t(key: &str) -> &'static str {
    let (ru, en) = match key {
        "tab.home" => ("Главная", "Home"),
        "tab.schedule" => ("Расписание", "Schedule"),
        "tab.profile" => ("Профиль", "Profile"),

        "action.retry" => ("Повторить", "Retry"),
        "action.cancel" => ("Отмена", "Cancel"),

        "error.cannotConnect" => ("Не удалось подключиться к серверу {0}", "Can't connect to server {0}"),
        "error.timedOut" => ("Сервер слишком долго не отвечает", "The server is taking too long to respond"),
        "error.offline" => ("Нет подключения к интернету", "No internet connection"),
        "error.notLoadedYet" => ("Сервер ещё не загрузил расписание", "The server hasn't loaded the schedule yet"),
        "error.server" => ("Сервер ответил ошибкой ({0})", "The server returned an error ({0})"),
        "error.serverMessage" => ("Ошибка сервера ({0}): {1}", "Server error ({0}): {1}"),
        "error.badResponse" => ("Сервер прислал непонятный ответ", "The server sent an unexpected response"),
        "error.recovery.checkServer" => (
            "Проверьте подключение к интернету. Если оно есть, сервер временно недоступен — попробуйте позже.",
            "Check your internet connection. If it works, the server is temporarily unavailable — try again later.",
        ),
        "error.recovery.offline" => ("Подключитесь к сети и попробуйте снова.", "Connect to a network and try again."),
        "error.recovery.retryLater" => ("Попробуйте ещё раз через минуту.", "Try again in a minute."),
        "stale.title" => ("Показаны данные от {0}", "Showing data from {0}"),

        "building.short" => ("корпус {0}", "building {0}"),
        "building.many" => ("корпуса {0}", "buildings {0}"),
        "course.label" => ("{0} курс", "Course {0}"),
        "course.other" => ("Другие группы", "Other groups"),
        "subgroup.badge" => ("{0} подгруппа", "Subgroup {0}"),
        "subgroup.unspecified" => ("Не указана", "Not set"),
        "subgroup.footer" => (
            "Если группа делится пополам (левая/правая колонка в расписании). Пары другой подгруппы не показываются.",
            "If your group is split in half (left/right column in the schedule). The other subgroup's classes are hidden.",
        ),
        "day.today" => ("сегодня", "today"),
        "day.tomorrow" => ("завтра", "tomorrow"),
        "countdown.in" => ("начнётся через {0}", "starts in {0}"),
        "duration.m" => ("{0} мин", "{0} min"),
        "duration.hm" => ("{0} ч {1} мин", "{0} hr {1} min"),
        "duration.dh" => ("{0} д {1} ч", "{0} d {1} hr"),
        "lesson.pairNumber" => ("{0} пара", "Class {0}"),
        "lesson.remote" => ("дистант", "remote"),
        "lesson.room" => ("каб. {0}", "room {0}"),
        "lunch.range" => ("Обед {0}–{1}", "Lunch {0}–{1}"),
        "lunch.from" => ("Обед с {0}", "Lunch from {0}"),

        "onboarding.title" => ("Знакомство", "Welcome"),
        "onboarding.nameFooter" => (
            "ФИО хранится только на этом компьютере и никуда не отправляется.",
            "Your name stays on this computer and is never sent anywhere.",
        ),
        "onboarding.nameRequired" => ("Введите ФИО", "Enter your name"),
        "onboarding.choose" => ("Выберите", "Choose"),
        "onboarding.save" => ("Сохранить и начать", "Save and start"),
        "group.search" => ("Поиск группы", "Search groups"),
        "group.notFound" => ("Ничего не найдено", "Nothing found"),

        "home.greeting" => ("Привет, {0}", "Hi, {0}"),
        "home.nextLesson" => ("Следующая пара", "Next class"),
        "home.ongoing" => ("сейчас идёт", "in progress"),
        "home.finished" => ("На сегодня пар больше нет — отдыхай 🎉", "No more classes today — take a rest 🎉"),
        "home.noLessonsToday" => ("Сегодня пар нет", "No classes today"),
        "home.buildingRoom" => ("корпус {0}, каб. {1}", "building {0}, room {1}"),
        "home.startsAt" => ("Занятия начинаются с {0}", "Classes start at {0}"),

        "schedule.day" => ("День", "Day"),
        "schedule.week" => ("Неделя", "Week"),
        "schedule.next" => ("Следующая", "Next"),
        "schedule.empty" => ("Пар нет", "No classes"),
        "schedule.noDays" => ("Расписание закончилось", "Schedule has ended"),
        "schedule.noDaysHint" => ("Колледж ещё не опубликовал следующие дни.", "The college hasn't published the next days yet."),

        "profile.fullName" => ("ФИО", "Full name"),
        "profile.group" => ("Группа", "Group"),
        "profile.subgroup" => ("Подгруппа", "Subgroup"),
        "profile.edit" => ("Изменить профиль", "Edit profile"),
        "profile.data" => ("Данные", "Data"),
        "profile.dataUpdated" => ("Данные обновлены", "Data updated"),
        "profile.serverParsed" => ("Сервер прочитал PDF", "Server read the PDF"),
        "profile.never" => ("ещё нет", "not yet"),
        "profile.refreshNow" => ("Обновить сейчас", "Refresh now"),
        "profile.about" => ("О приложении", "About"),
        "profile.version" => ("Версия приложения", "App version"),
        "profile.reset" => ("Сбросить профиль", "Reset profile"),
        "profile.resetConfirm" => ("Сбросить профиль?", "Reset profile?"),
        "profile.resetMessage" => (
            "ФИО, группа и сохранённое расписание будут удалены с этого компьютера.",
            "Your name, group and saved schedule will be removed from this computer.",
        ),
        _ => {
            debug_assert!(false, "missing string {key}");
            ("", "")
        }
    };
    match lang() {
        Lang::Ru => ru,
        Lang::En => en,
    }
}
