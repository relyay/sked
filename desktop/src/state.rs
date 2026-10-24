//! App-wide state: the local profile and the schedule. Views subscribe and
//! rebuild themselves when it changes.

use std::cell::{Cell, RefCell};
use std::rc::Rc;

use gtk::{gio, glib, prelude::*};
use jiff::Timestamp;

use crate::api::{Api, ApiError};
use crate::core::{GroupInfo, Profile, ScheduleQuery, ScheduleResponse};
use crate::storage::{self, CachedSchedule};

#[derive(Clone)]
pub enum ScheduleState {
    Idle,
    Loading,
    Loaded(ScheduleResponse),
    /// Network failed and there is no cached snapshot.
    Failed(ApiError),
}

pub struct AppState {
    pub api: Api,
    profile: RefCell<Option<Profile>>,
    schedule: RefCell<ScheduleState>,
    etag: RefCell<Option<String>>,
    /// When the shown schedule was downloaded.
    fetched_at: Cell<Option<Timestamp>>,
    /// Set when the shown schedule came from the offline cache.
    stale: RefCell<Option<ApiError>>,
    refreshing: Cell<bool>,
    listeners: RefCell<Vec<Box<dyn Fn()>>>,
}

impl AppState {
    pub fn new(api: Api) -> Rc<Self> {
        let state = Rc::new(Self {
            api,
            profile: RefCell::new(storage::load_profile()),
            schedule: RefCell::new(ScheduleState::Idle),
            etag: RefCell::new(None),
            fetched_at: Cell::new(None),
            stale: RefCell::new(None),
            refreshing: Cell::new(false),
            listeners: RefCell::new(Vec::new()),
        });
        if let Some(group) = state.profile().map(|p| p.group) {
            state.load_cached(&group);
        }
        state
    }

    pub fn subscribe(&self, f: impl Fn() + 'static) {
        self.listeners.borrow_mut().push(Box::new(f));
    }

    pub fn changed(&self) {
        // Listeners may subscribe new listeners while rebuilding; run a snapshot.
        let listeners = std::mem::take(&mut *self.listeners.borrow_mut());
        for f in &listeners {
            f();
        }
        let mut current = self.listeners.borrow_mut();
        let added = std::mem::take(&mut *current);
        *current = listeners;
        current.extend(added);
    }

    pub fn profile(&self) -> Option<Profile> {
        self.profile.borrow().clone()
    }

    pub fn schedule_state(&self) -> ScheduleState {
        self.schedule.borrow().clone()
    }

    pub fn schedule(&self) -> Option<ScheduleResponse> {
        match &*self.schedule.borrow() {
            ScheduleState::Loaded(r) => Some(r.clone()),
            _ => None,
        }
    }

    pub fn fetched_at(&self) -> Option<Timestamp> {
        self.fetched_at.get()
    }

    pub fn stale(&self) -> Option<ApiError> {
        self.stale.borrow().clone()
    }

    pub fn is_refreshing(&self) -> bool {
        self.refreshing.get()
    }

    pub fn query(&self) -> Option<ScheduleQuery> {
        let profile = self.profile()?;
        Some(ScheduleQuery::new(self.schedule()?.days, profile.group, profile.subgroup))
    }

    fn load_cached(&self, group: &str) {
        if let Some(cached) = storage::load_cache(group) {
            if let Some(response) = cached.response() {
                *self.schedule.borrow_mut() = ScheduleState::Loaded(response);
                *self.etag.borrow_mut() = cached.etag.clone();
                self.fetched_at.set(Timestamp::from_millisecond(cached.fetched_at).ok());
            }
        }
    }

    pub fn save(self: &Rc<Self>, profile: Profile) {
        let group_changed = self.profile().map(|p| p.group) != Some(profile.group.clone());
        storage::save_profile(&profile);
        *self.profile.borrow_mut() = Some(profile.clone());
        if group_changed {
            *self.schedule.borrow_mut() = ScheduleState::Idle;
            *self.etag.borrow_mut() = None;
            self.fetched_at.set(None);
            *self.stale.borrow_mut() = None;
            self.load_cached(&profile.group);
            self.refresh();
        }
        self.changed();
    }

    pub fn reset(&self) {
        storage::clear_profile();
        *self.profile.borrow_mut() = None;
        *self.schedule.borrow_mut() = ScheduleState::Idle;
        *self.etag.borrow_mut() = None;
        self.fetched_at.set(None);
        *self.stale.borrow_mut() = None;
        self.changed();
    }

    /// Downloads the schedule; on failure keeps showing the cached snapshot.
    pub fn refresh(self: &Rc<Self>) {
        let Some(profile) = self.profile() else { return };
        if self.refreshing.replace(true) {
            return;
        }
        if self.schedule().is_none() {
            *self.schedule.borrow_mut() = ScheduleState::Loading;
        }
        self.changed();

        let api = self.api.clone();
        let group = profile.group.clone();
        let etag = self.schedule().and(self.etag.borrow().clone());
        let state = Rc::clone(self);
        glib::spawn_future_local(async move {
            let result = gio::spawn_blocking(move || api.schedule(&group, etag.as_deref())).await;
            state.refreshing.set(false);
            // The profile may have changed while the request was in flight.
            if state.profile().map(|p| p.group) != Some(profile.group.clone()) {
                state.changed();
                return;
            }
            match result.unwrap_or(Err(ApiError::BadResponse)) {
                Ok(Some(fetched)) => {
                    let now = Timestamp::now();
                    storage::save_cache(
                        &profile.group,
                        &CachedSchedule { fetched_at: now.as_millisecond(), etag: fetched.etag.clone(), body: fetched.body },
                    );
                    *state.schedule.borrow_mut() = ScheduleState::Loaded(fetched.response);
                    *state.etag.borrow_mut() = fetched.etag;
                    state.fetched_at.set(Some(now));
                    *state.stale.borrow_mut() = None;
                }
                Ok(None) => {
                    // 304: the cached copy is current.
                    let now = Timestamp::now();
                    if let Some(mut cached) = storage::load_cache(&profile.group) {
                        cached.fetched_at = now.as_millisecond();
                        storage::save_cache(&profile.group, &cached);
                    }
                    state.fetched_at.set(Some(now));
                    *state.stale.borrow_mut() = None;
                }
                Err(e) => {
                    let e = offline_aware(e);
                    if state.schedule().is_some() {
                        *state.stale.borrow_mut() = Some(e);
                    } else {
                        *state.schedule.borrow_mut() = ScheduleState::Failed(e);
                    }
                }
            }
            state.changed();
        });
    }

    /// Loads the group list on a worker thread and calls `done` on the main loop.
    pub fn load_groups(&self, done: impl FnOnce(Result<Vec<GroupInfo>, ApiError>) + 'static) {
        let api = self.api.clone();
        glib::spawn_future_local(async move {
            let result = gio::spawn_blocking(move || api.groups()).await.unwrap_or(Err(ApiError::BadResponse));
            done(result.map_err(offline_aware));
        });
    }
}

/// A connection error with no network at all is reported as "offline".
fn offline_aware(error: ApiError) -> ApiError {
    match error {
        ApiError::CannotConnect(_) if !gio::NetworkMonitor::default().is_network_available() => ApiError::Offline,
        e => e,
    }
}
