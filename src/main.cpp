#include "gtkmm/settings.h"
#include "pocket.h"
#include <gtkmm/application.h>

int main(int argc, char *argv[]) {
  auto app = Gtk::Application::create(argc, argv, "com.maskedsyntax.pocket");

  auto settings = Gtk::Settings::get_default();
  if (settings) {
      settings->property_gtk_icon_theme_name() = "Papirus";
  }

  PocketLauncher launcher;
  return app->run(launcher);
}
