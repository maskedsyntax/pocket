#include <cstring>
#include <gtkmm/application.h>
#include <memory>
#include "pocket.h"
#include "config.h"

// Pocket runs as a single resident instance. The first `pocket` process
// becomes the primary instance and stays alive after its window is hidden;
// later invocations just ask it (over D-Bus) to show the window again, which
// skips GTK startup, the app scan and icon loading entirely.
//
//   pocket               show the launcher (starting the instance if needed)
//   pocket --background  start the instance without showing it (for autostart)
int main(int argc, char* argv[]) {
    bool background = false;
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--background") == 0)
            background = true;
    }

    auto app = Gtk::Application::create("com.maskedsyntax.pocket");

    if (background) {
        // Already running: nothing to do, and don't pop the window up.
        app->register_application();
        if (app->is_remote()) {
            // Exiting right away; leak the app so GLib doesn't warn that a
            // registered application was destroyed without being run.
            [[maybe_unused]] auto* leaked = app.release();
            return 0;
        }
    }

    std::unique_ptr<PocketLauncher> launcher;
    bool first_activation = true;

    app->signal_activate().connect([&]() {
        if (!launcher) {
            launcher = std::make_unique<PocketLauncher>(load_pocket_config());
            // Keep running while the window is hidden.
            app->hold();
        }

        bool stay_hidden = first_activation && background;
        first_activation = false;
        if (!stay_hidden)
            launcher->show_launcher();
    });

    return app->run();
}
