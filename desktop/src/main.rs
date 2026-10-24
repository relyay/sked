//! Sked for the GNOME desktop: the VKSIT class schedule from the skedd server,
//! mirroring the iOS and Android clients.

mod api;
mod core;
mod format;
mod i18n;
mod state;
mod storage;
mod ui;

use adw::prelude::*;

const APP_ID: &str = "ru.sked.app";

fn main() -> gtk::glib::ExitCode {
    let app = adw::Application::builder().application_id(APP_ID).build();
    app.connect_activate(|app| {
        // A second launch focuses the existing window.
        if let Some(window) = app.active_window() {
            window.present();
            return;
        }
        let state = state::AppState::new(api::Api::new(api::server_url()));
        ui::build_window(app, state);
    });
    app.run()
}
