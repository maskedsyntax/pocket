#include "pocket.h"
#include <gtkmm/application.h>

int main(int argc, char *argv[]) {
  auto app = Gtk::Application::create(argc, argv, "com.maskedsyntax.pocket");
  PocketLauncher launcher;
  return app->run(launcher);
}
