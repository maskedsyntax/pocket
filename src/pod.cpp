#include "pod.h"
#include <algorithm>
#include <iostream>

PodLauncher::PodLauncher()
    : m_main_box(Gtk::ORIENTATION_VERTICAL), m_columns() {
  set_title("pod");
  set_default_size(600, 400);
  set_position(Gtk::WIN_POS_CENTER);
  set_decorated(false);
  set_skip_taskbar_hint(true);
  set_keep_above(true);

  load_config();

  // Setup UI
  add(m_main_box);
  m_main_box.set_spacing(5);
  m_main_box.set_margin_top(10);
  m_main_box.set_margin_bottom(10);
  m_main_box.set_margin_left(10);
  m_main_box.set_margin_right(10);

  // Apply styling
  auto css_provider = Gtk::CssProvider::create();
  std::string font_family =
      m_config.count("font") ? m_config["font"] : "Monospace";
  int font_size =
      m_config.count("font-size") ? std::stoi(m_config["font-size"]) : 12;

  std::string css = "window { background-color: rgba(40, 40, 40, 0.95); }";
  css += "entry, treeview { font: " + std::to_string(font_size) + "px '" +
         font_family + "'; }";
  css += "entry { background: rgba(60, 60, 60, 0.9); color: white; border: 1px "
         "solid #555; border-radius: 5px; padding: 8px; }";
  css += "treeview { background: rgba(50, 50, 50, 0.9); color: white; }";
  css += "treeview:selected { background: #3465a4; }";

  try {
    css_provider->load_from_data(css);
    get_style_context()->add_provider_for_screen(
        Gdk::Screen::get_default(), css_provider,
        GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
  } catch (const Gtk::CssProviderError &ex) {
    std::cerr << "CSS error: " << ex.what() << std::endl;
  }

  // Entry
  m_main_box.pack_start(m_entry, Gtk::PACK_SHRINK);
  m_entry.set_placeholder_text("Type to search applications...");
  m_entry.signal_changed().connect(
      sigc::mem_fun(*this, &PodLauncher::on_entry_changed));

  // TreeView
  m_columns.add(m_col_name);
  m_columns.add(m_col_exec);
  m_columns.add(m_col_icon);

  m_list_store = Gtk::ListStore::create(m_columns);
  m_tree_view.set_model(m_list_store);
  m_tree_view.set_headers_visible(false);

  // Icon column
  Gtk::CellRendererPixbuf *icon_renderer =
      Gtk::manage(new Gtk::CellRendererPixbuf());
  Gtk::TreeViewColumn *icon_column =
      Gtk::manage(new Gtk::TreeViewColumn("Icon", *icon_renderer));
  icon_column->add_attribute(icon_renderer->property_pixbuf(), m_col_icon);
  icon_column->set_fixed_width(32);
  m_tree_view.append_column(*icon_column);

  // Name column
  Gtk::CellRendererText *name_renderer =
      Gtk::manage(new Gtk::CellRendererText());
  Gtk::TreeViewColumn *name_column =
      Gtk::manage(new Gtk::TreeViewColumn("Name", *name_renderer));
  name_column->add_attribute(name_renderer->property_text(), m_col_name);
  name_column->set_expand(true);
  m_tree_view.append_column(*name_column);

  m_tree_view.signal_row_activated().connect(
      sigc::mem_fun(*this, &PodLauncher::on_row_activated));

  // Scrolled window
  m_scrolled_window.add(m_tree_view);
  m_scrolled_window.set_policy(Gtk::POLICY_NEVER, Gtk::POLICY_AUTOMATIC);
  m_main_box.pack_start(m_scrolled_window);

  load_applications();
  show_all_children();
}

PodLauncher::~PodLauncher() {}

void PodLauncher::load_config() {
  std::string config_file = Glib::get_home_dir() + "/.config/pod/podrc";
  m_config = {{"font", "JetBrains Mono"}, {"font-size", "12"}, {"icon", ""}};

  std::ifstream file(config_file);
  if (!file.is_open())
    return;

  std::string line;
  while (std::getline(file, line)) {
    size_t pos = line.find(':');
    if (pos != std::string::npos) {
      std::string key = line.substr(0, pos);
      std::string value = line.substr(pos + 1);
      key.erase(0, key.find_first_not_of(" \t"));
      key.erase(key.find_last_not_of(" \t") + 1);
      value.erase(0, value.find_first_not_of(" \t"));
      value.erase(value.find_last_not_of(" \t") + 1);
      m_config[key] = value;
    }
  }
}

void PodLauncher::load_applications() {
  for (const auto &dir : m_app_dirs) {
    if (std::filesystem::exists(dir))
      scan_directory(dir);
  }
  std::sort(m_all_apps.begin(), m_all_apps.end(),
            [](const AppInfo &a, const AppInfo &b) { return a.name < b.name; });
  filter_apps();
}

void PodLauncher::scan_directory(const std::filesystem::path &dir) {
  try {
    for (const auto &entry : std::filesystem::directory_iterator(dir)) {
      if (entry.is_regular_file() && entry.path().extension() == ".desktop") {
        parse_desktop_file(entry.path());
      }
    }
  } catch (const std::filesystem::filesystem_error &ex) {
    std::cerr << "Error scanning " << dir << ": " << ex.what() << std::endl;
  }
}

void PodLauncher::parse_desktop_file(const std::filesystem::path &file_path) {
  std::ifstream file(file_path);
  if (!file.is_open())
    return;

  AppInfo app;
  std::string line;
  bool is_desktop_entry = false;

  while (std::getline(file, line)) {
    if (line.empty() || line[0] == '#')
      continue;

    if (line[0] == '[') {
      is_desktop_entry = (line == "[Desktop Entry]");
      continue;
    }

    if (!is_desktop_entry)
      continue;

    size_t pos = line.find('=');
    if (pos == std::string::npos)
      continue;

    std::string key = line.substr(0, pos);
    std::string value = line.substr(pos + 1);

    if (key == "Name")
      app.name = value;
    else if (key == "Exec")
      app.exec = value;
    else if (key == "Icon")
      app.icon = value;
    else if (key == "NoDisplay" && value == "true")
      return;
    else if (key == "Hidden" && value == "true")
      return;
  }

  if (app.name.empty() || app.exec.empty())
    return;

  size_t pos = app.exec.find('%');
  if (pos != std::string::npos)
    app.exec = app.exec.substr(0, pos);
  app.exec.erase(app.exec.find_last_not_of(" \t") + 1);

  m_all_apps.push_back(app);
}

void PodLauncher::filter_apps() {
  std::string search_text = m_entry.get_text();
  std::transform(search_text.begin(), search_text.end(), search_text.begin(),
                 ::tolower);

  m_list_store->clear();

  for (const auto &app : m_all_apps) {
    std::string app_name_lower = app.name;
    std::transform(app_name_lower.begin(), app_name_lower.end(),
                   app_name_lower.begin(), ::tolower);

    if (search_text.empty() ||
        app_name_lower.find(search_text) != std::string::npos) {
      auto row = *(m_list_store->append());
      row[m_col_name] = app.name;
      row[m_col_exec] = app.exec;

      Glib::RefPtr<Gdk::Pixbuf> icon;
      try {
        if (!app.icon.empty()) {
          auto icon_theme = Gtk::IconTheme::get_default();
          if (Glib::file_test(app.icon, Glib::FILE_TEST_EXISTS)) {
            icon = Gdk::Pixbuf::create_from_file(app.icon, 24, 24);
          } else {
            auto icon_info = icon_theme->lookup_icon(
                app.icon, 24, Gtk::ICON_LOOKUP_FORCE_SIZE);
            if (icon_info)
              icon = icon_info.load_icon();
          }
        }
      } catch (const Glib::Error &ex) {
      }

      if (!icon) {
        try {
          auto icon_theme = Gtk::IconTheme::get_default();
          auto icon_info = icon_theme->lookup_icon(
              "application-x-executable", 24, Gtk::ICON_LOOKUP_FORCE_SIZE);
          if (icon_info)
            icon = icon_info.load_icon();
        } catch (const Glib::Error &ex) {
        }
      }

      row[m_col_icon] = icon;
    }
  }

  if (m_list_store->children().size() > 0) {
    Gtk::TreePath first_path("0");
    m_tree_view.set_cursor(first_path);
  }
}

void PodLauncher::on_entry_changed() { filter_apps(); }

void PodLauncher::on_row_activated(const Gtk::TreeModel::Path &path,
                                   Gtk::TreeViewColumn *column) {
  auto iter = m_list_store->get_iter(path);
  if (iter) {
    Gtk::TreeModel::Row row = *iter;
    Glib::ustring exec_ustring = row[m_col_exec];
    std::string command = std::string(exec_ustring) + " &";
    std::system(command.c_str());
    hide();
  }
}

bool PodLauncher::on_key_press_event(GdkEventKey *event) {
  if (event->keyval == GDK_KEY_Escape)
    hide();
  return Gtk::Window::on_key_press_event(event);
}
