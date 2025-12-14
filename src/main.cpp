#include <gtkmm/application.h>
#include <gtkmm/settings.h>
#include "pocket.h"
#include "config.h"

int main(int argc, char *argv[]) {
    auto app = Gtk::Application::create(argc, argv, "com.maskedsyntax.pocket");

    auto config = load_pocket_config();

    auto settings = Gtk::Settings::get_default();
    if (settings && config.count("icon-theme")) {
        settings->property_gtk_icon_theme_name() = config["icon-theme"];
    }

    PocketLauncher launcher(config);
    return app->run(launcher);
}
