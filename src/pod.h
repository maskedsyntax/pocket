#ifndef POD_H
#define POD_H

#include <filesystem>
#include <fstream>
#include <gtkmm.h>
#include <map>
#include <string>
#include <vector>

struct AppInfo {
  std::string name;
  std::string exec;
  std::string icon;
};

class PodLauncher : public Gtk::Window {
public:
  PodLauncher();
  virtual ~PodLauncher();

protected:
  bool on_key_press_event(GdkEventKey *event) override;
  void on_entry_changed();
  void on_row_activated(const Gtk::TreeModel::Path &path,
                        Gtk::TreeViewColumn *column);

  void load_config();
  void load_applications();
  void scan_directory(const std::filesystem::path &dir);
  void parse_desktop_file(const std::filesystem::path &file_path);
  void filter_apps();

  Gtk::Box m_main_box;
  Gtk::Entry m_entry;
  Gtk::ScrolledWindow m_scrolled_window;
  Gtk::TreeView m_tree_view;

  Glib::RefPtr<Gtk::ListStore> m_list_store;
  Gtk::TreeModel::ColumnRecord m_columns;
  Gtk::TreeModelColumn<Glib::ustring> m_col_name;
  Gtk::TreeModelColumn<Glib::ustring> m_col_exec;
  Gtk::TreeModelColumn<Glib::RefPtr<Gdk::Pixbuf>> m_col_icon;

  std::vector<AppInfo> m_all_apps;
  std::map<std::string, std::string> m_config;

  const std::vector<std::string> m_app_dirs = {
      "/usr/share/applications",
      "/usr/local/share/applications",
      Glib::get_home_dir() + "/.local/share/applications",
      "/var/lib/snapd/desktop/applications",
      Glib::get_home_dir() + "/.local/share/flatpak/exports/share/applications",
      "/var/lib/flatpak/exports/share/applications"};
};

#endif
