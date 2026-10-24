use serde::{Deserialize, Serialize};

/// A pair (or a run of pairs merged into one cell) as served by `GET /schedule`.
#[derive(Clone, Debug, Default, PartialEq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Lesson {
    pub pair: i32,
    /// Building of this pair; a group may change buildings between days.
    #[serde(default)]
    pub building: Option<i32>,
    /// Last pair of a cell that spans several pairs, e.g. an exam.
    #[serde(default)]
    pub pair_to: Option<i32>,
    /// "HH:mm", Europe/Moscow.
    #[serde(default)]
    pub start: String,
    #[serde(default)]
    pub end: Option<String>,
    pub subject: String,
    #[serde(default)]
    pub teacher: Option<String>,
    #[serde(default)]
    pub room: Option<String>,
    #[serde(default)]
    pub is_remote: bool,
    /// `None` means the whole group.
    #[serde(default)]
    pub subgroup: Option<i32>,
    #[serde(default)]
    pub note: Option<String>,
    /// Set when the PDF had no time for this pair and the server derived it.
    #[serde(default)]
    pub time_source: Option<String>,
}

impl Lesson {
    /// "2" or "1–6" for merged cells.
    pub fn pair_label(&self) -> String {
        match self.pair_to {
            Some(to) if to != self.pair => format!("{}–{}", self.pair, to),
            _ => self.pair.to_string(),
        }
    }

    /// The lesson's building, or `fallback` when the server sent none (or 0).
    pub fn building_or(&self, fallback: i32) -> i32 {
        self.building.filter(|b| *b > 0).unwrap_or(fallback)
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum NoteKind {
    StartsAt,
    Lunch,
    #[default]
    Other,
}

impl<'de> Deserialize<'de> for NoteKind {
    fn deserialize<D: serde::Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        // Unknown kinds from a newer server degrade to Other.
        Ok(match String::deserialize(d)?.as_str() {
            "startsAt" => NoteKind::StartsAt,
            "lunch" => NoteKind::Lunch,
            _ => NoteKind::Other,
        })
    }
}

impl Serialize for NoteKind {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(match self {
            NoteKind::StartsAt => "startsAt",
            NoteKind::Lunch => "lunch",
            NoteKind::Other => "other",
        })
    }
}

#[derive(Clone, Debug, Default, PartialEq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Note {
    #[serde(default)]
    pub kind: NoteKind,
    #[serde(default)]
    pub text: String,
    #[serde(default)]
    pub time: Option<String>,
    #[serde(default)]
    pub end_time: Option<String>,
    #[serde(default)]
    pub pair: Option<i32>,
    #[serde(default)]
    pub subgroup: Option<i32>,
}

#[derive(Clone, Debug, Default, PartialEq, Deserialize, Serialize)]
pub struct GroupDay {
    pub group: String,
    pub lessons: Vec<Lesson>,
    #[serde(default)]
    pub notes: Vec<Note>,
}

#[derive(Clone, Debug, Default, PartialEq, Deserialize, Serialize)]
pub struct Day {
    /// "YYYY-MM-DD".
    pub date: String,
    #[serde(default)]
    pub weekday: Option<String>,
    #[serde(default)]
    pub building: i32,
    pub groups: Vec<GroupDay>,
}

#[derive(Clone, Debug, Default, PartialEq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ScheduleResponse {
    #[serde(default)]
    pub group: Option<String>,
    /// RFC 3339 as sent by the server (Go, nanosecond precision).
    pub parsed_at: String,
    pub days: Vec<Day>,
}

#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
pub struct GroupInfo {
    pub name: String,
    #[serde(default)]
    pub course: i32,
    /// Buildings the group has classes in.
    #[serde(default)]
    pub buildings: Vec<i32>,
}

#[derive(Debug, Deserialize)]
pub struct GroupsResponse {
    pub groups: Vec<GroupInfo>,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Deserialize, Serialize)]
pub enum Subgroup {
    #[default]
    Unspecified,
    First,
    Second,
}

impl Subgroup {
    pub fn number(self) -> i32 {
        match self {
            Subgroup::Unspecified => 0,
            Subgroup::First => 1,
            Subgroup::Second => 2,
        }
    }

    pub fn of(number: i32) -> Self {
        match number {
            1 => Subgroup::First,
            2 => Subgroup::Second,
            _ => Subgroup::Unspecified,
        }
    }
}

/// The student's profile. Stored only on this computer. There is no building:
/// groups move between buildings from day to day, so it comes with each pair.
#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Profile {
    pub full_name: String,
    pub group: String,
    /// Derived from the group number, e.g. "ИСП-324а" → 3.
    pub course: i32,
    pub subgroup: Subgroup,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DraftProblem {
    EmptyName,
    NoGroup,
    UnknownGroup,
}

/// Onboarding input before it becomes a [`Profile`].
#[derive(Clone, Debug, Default)]
pub struct ProfileDraft {
    pub full_name: String,
    pub group: Option<String>,
    pub subgroup: Subgroup,
}

impl ProfileDraft {
    /// Validates against the group list the server returned.
    pub fn validate(&self, groups: &[GroupInfo]) -> Result<Profile, DraftProblem> {
        let name = self.full_name.trim();
        if name.is_empty() {
            return Err(DraftProblem::EmptyName);
        }
        let group = self.group.as_deref().ok_or(DraftProblem::NoGroup)?;
        let info = groups.iter().find(|g| g.name == group).ok_or(DraftProblem::UnknownGroup)?;
        Ok(Profile { full_name: name.to_owned(), group: group.to_owned(), course: info.course, subgroup: self.subgroup })
    }
}
