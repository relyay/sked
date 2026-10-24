//! Profile and offline cache on disk (XDG config and cache directories).

use std::fs;
use std::path::PathBuf;

use gtk::glib;
use serde::{Deserialize, Serialize};

use crate::core::{Profile, ScheduleResponse};

fn config_file() -> PathBuf {
    glib::user_config_dir().join("sked").join("profile.json")
}

fn cache_dir() -> PathBuf {
    glib::user_cache_dir().join("sked")
}

/// Writes through a temporary file so a crash never leaves a torn file.
fn write_atomic(path: &PathBuf, contents: &str) {
    let Some(dir) = path.parent() else { return };
    if fs::create_dir_all(dir).is_err() {
        return;
    }
    let tmp = path.with_extension("tmp");
    if fs::write(&tmp, contents).is_ok() {
        let _ = fs::rename(&tmp, path);
    }
}

/// The profile, stored only on this computer.
pub fn load_profile() -> Option<Profile> {
    serde_json::from_str(&fs::read_to_string(config_file()).ok()?).ok()
}

pub fn save_profile(profile: &Profile) {
    if let Ok(json) = serde_json::to_string_pretty(profile) {
        write_atomic(&config_file(), &json);
    }
}

pub fn clear_profile() {
    let _ = fs::remove_file(config_file());
    let _ = fs::remove_dir_all(cache_dir());
}

/// Last successful `/schedule` response of a group, for offline use.
#[derive(Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CachedSchedule {
    /// Unix milliseconds of the download.
    pub fetched_at: i64,
    pub etag: Option<String>,
    pub body: String,
}

impl CachedSchedule {
    pub fn response(&self) -> Option<ScheduleResponse> {
        serde_json::from_str(&self.body).ok()
    }
}

fn cache_file(group: &str) -> PathBuf {
    // Group names are Cyrillic with hyphens; keep only safe characters.
    let name: String = group.chars().map(|c| if c.is_alphanumeric() || c == '-' { c } else { '_' }).collect();
    cache_dir().join(format!("{name}.json"))
}

pub fn load_cache(group: &str) -> Option<CachedSchedule> {
    serde_json::from_str(&fs::read_to_string(cache_file(group)).ok()?).ok()
}

pub fn save_cache(group: &str, cached: &CachedSchedule) {
    if let Ok(json) = serde_json::to_string(cached) {
        write_atomic(&cache_file(group), &json);
    }
}
