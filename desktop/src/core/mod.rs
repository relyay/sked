//! Schedule rules shared with the iOS (`SkedCore`) and Android
//! (`ru.sked.app.core`) clients. Pure Rust, no GTK, so it is unit-tested on
//! its own; keep the rules identical across the three clients.

mod models;
mod query;

pub use models::*;
pub use query::*;

#[cfg(test)]
mod tests;
