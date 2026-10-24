//! Talks to the skedd server. Blocking (ureq); the UI calls it through
//! `gio::spawn_blocking`.

use std::time::Duration;

use crate::core::{GroupInfo, GroupsResponse, ScheduleResponse};

/// Production server; `SKED_SERVER_URL` overrides it for development.
pub const PRODUCTION: &str = "https://rasp.relya.ru";

pub fn server_url() -> String {
    std::env::var("SKED_SERVER_URL")
        .ok()
        .filter(|u| u.starts_with("http://") || u.starts_with("https://"))
        .unwrap_or_else(|| PRODUCTION.to_owned())
}

/// Network failures translated into something a student can act on.
#[derive(Clone, Debug, PartialEq)]
pub enum ApiError {
    CannotConnect(String),
    TimedOut,
    Offline,
    NotLoadedYet,
    Server { status: u16, message: Option<String> },
    BadResponse,
}

impl ApiError {
    /// Worth retrying automatically.
    fn is_transient(&self) -> bool {
        matches!(self, ApiError::TimedOut | ApiError::NotLoadedYet) || matches!(self, ApiError::Server { status, .. } if *status >= 500)
    }
}

/// A fetched schedule with what the offline cache needs.
pub struct Fetched {
    pub response: ScheduleResponse,
    pub body: String,
    pub etag: Option<String>,
}

#[derive(Clone)]
pub struct Api {
    base: String,
    agent: ureq::Agent,
}

impl Api {
    pub fn new(base: String) -> Self {
        let agent = ureq::Agent::config_builder()
            .timeout_global(Some(Duration::from_secs(15)))
            .http_status_as_error(false)
            .build()
            .into();
        Self { base, agent }
    }

    /// All groups of both buildings.
    pub fn groups(&self) -> Result<Vec<GroupInfo>, ApiError> {
        let (body, _) = self.get("/groups", None, None)?.ok_or(ApiError::BadResponse)?;
        serde_json::from_str::<GroupsResponse>(&body).map(|r| r.groups).map_err(|_| ApiError::BadResponse)
    }

    /// The whole known schedule of one group across buildings. With the
    /// cached ETag the server answers 304 and `Ok(None)` means "unchanged".
    pub fn schedule(&self, group: &str, etag: Option<&str>) -> Result<Option<Fetched>, ApiError> {
        let Some((body, etag)) = self.get("/schedule", Some(("group", group)), etag)? else { return Ok(None) };
        let response = serde_json::from_str(&body).map_err(|_| ApiError::BadResponse)?;
        Ok(Some(Fetched { response, body, etag }))
    }

    fn get(&self, path: &str, query: Option<(&str, &str)>, etag: Option<&str>) -> Result<Option<(String, Option<String>)>, ApiError> {
        let mut attempt = 0;
        loop {
            attempt += 1;
            match self.fetch(path, query, etag) {
                Err(e) if e.is_transient() && attempt < 3 => {
                    // Exponential backoff: 0.5 s, 1 s…
                    std::thread::sleep(Duration::from_millis(500 << (attempt - 1)));
                }
                other => return other,
            }
        }
    }

    fn fetch(&self, path: &str, query: Option<(&str, &str)>, etag: Option<&str>) -> Result<Option<(String, Option<String>)>, ApiError> {
        let url = format!("{}{}", self.base.trim_end_matches('/'), path);
        let host = url.split("://").nth(1).and_then(|r| r.split(['/', ':']).next()).unwrap_or_default().to_owned();
        let mut request = self.agent.get(&url).header("Accept", "application/json");
        if let Some((key, value)) = query {
            request = request.query(key, value);
        }
        if let Some(etag) = etag {
            request = request.header("If-None-Match", etag);
        }
        let mut response = request.call().map_err(|e| match e {
            ureq::Error::Timeout(_) => ApiError::TimedOut,
            _ => ApiError::CannotConnect(host),
        })?;
        let status = response.status().as_u16();
        let new_etag = response.headers().get("etag").and_then(|v| v.to_str().ok()).map(str::to_owned);
        let body = response.body_mut().read_to_string().map_err(|_| ApiError::BadResponse)?;
        match status {
            200..=299 => Ok(Some((body, new_etag))),
            304 => Ok(None),
            503 => Err(ApiError::NotLoadedYet),
            _ => {
                let message = serde_json::from_str::<serde_json::Value>(&body)
                    .ok()
                    .and_then(|v| v.get("error")?.as_str().map(str::to_owned));
                Err(ApiError::Server { status, message })
            }
        }
    }
}
