#include "pod.h"
#include <gtkmm/application.h>

int main(int argc, char *argv[]) {
  auto app = Gtk::Application::create(argc, argv, "com.pod.launcher");
  PodLauncher launcher;
  return app->run(launcher);
}
