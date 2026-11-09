#include "pocket.h"
#include "config.h"
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif
#include <algorithm>
#include <fstream>
#include <iostream>
#include <string>

namespace {

int config_int(const std::map<std::string, std::string>& config, const std::string& key,
               int fallback, int min_value) {
    auto it = config.find(key);
    if (it == config.end())
        return fallback;
    try {
        return std::max(min_value, std::stoi(it->second));
    } catch (const std::exception&) {
        std::cerr << "pocketrc: invalid " << key << " '" << it->second << "', using "
                  << fallback << std::endl;
        return fallback;
    }
}

// Accepts anything GDK understands: #rgb, #rrggbb, rgb(...), rgba(...), names.
std::string config_color(const std::map<std::string, std::string>& config,
                         const std::string& key, const std::string& fallback) {
    auto it = config.find(key);
    if (it == config.end())
        return fallback;
    Gdk::RGBA rgba;
    if (rgba.set(it->second))
        return rgba.to_string();
    std::cerr << "pocketrc: invalid " << key << " '" << it->second << "', using " << fallback
              << std::endl;
    return fallback;
}

} // namespace

PocketLauncher::PocketLauncher(const std::map<std::string, std::string>& config)
    : m_main_box(Gtk::ORIENTATION_VERTICAL), m_columns(), m_config(config) {

    set_title("pocket");
    set_position(Gtk::WIN_POS_CENTER);
    set_decorated(false);
    set_skip_taskbar_hint(true);
    set_keep_above(true);

    // Let a translucent background actually be translucent when a
    // compositor is running.
    auto screen = get_screen();
    if (screen && screen->is_composited()) {
        auto rgba_visual = screen->get_rgba_visual();
        if (rgba_visual)
            gtk_widget_set_visual(GTK_WIDGET(gobj()), rgba_visual->gobj());
    }

    // ui
    add(m_main_box);
    m_main_box.set_spacing(5);
    m_main_box.set_margin_top(10);
    m_main_box.set_margin_bottom(10);
    m_main_box.set_margin_left(10);
    m_main_box.set_margin_right(10);

    m_css_provider = Gtk::CssProvider::create();
    Gtk::StyleContext::add_provider_for_screen(Gdk::Screen::get_default(), m_css_provider,
                                               GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);

    m_main_box.pack_start(m_entry, Gtk::PACK_SHRINK);
    m_entry.set_placeholder_text("Type to search applications...");
    m_entry.signal_changed().connect(sigc::mem_fun(*this, &PocketLauncher::on_entry_changed));

    m_entry.signal_activate().connect([this]() {
        auto selection = m_tree_view.get_selection();
        Gtk::TreeModel::iterator iter = selection->get_selected();
        if (iter) {
            on_row_activated(m_list_store->get_path(iter), nullptr);
        }
    });

    m_columns.add(m_col_name);
    m_columns.add(m_col_exec);
    m_columns.add(m_col_icon);
    m_columns.add(m_col_icon_name);

    m_list_store = Gtk::ListStore::create(m_columns);
    m_tree_view.set_model(m_list_store);
    m_tree_view.set_headers_visible(false);

    Gtk::CellRendererPixbuf* icon_renderer = Gtk::manage(new Gtk::CellRendererPixbuf());
    Gtk::TreeViewColumn* icon_column = Gtk::manage(new Gtk::TreeViewColumn("Icon", *icon_renderer));
    icon_column->add_attribute(icon_renderer->property_pixbuf(), m_col_icon);
    icon_column->set_fixed_width(32);
    m_tree_view.append_column(*icon_column);

    m_name_renderer = Gtk::manage(new Gtk::CellRendererText());
    // Long names get "…" instead of forcing the window wider than `width`.
    m_name_renderer->property_ellipsize() = Pango::ELLIPSIZE_END;
    Gtk::TreeViewColumn* name_column =
        Gtk::manage(new Gtk::TreeViewColumn("Name", *m_name_renderer));
    name_column->add_attribute(m_name_renderer->property_text(), m_col_name);
    name_column->set_expand(true);
    m_tree_view.append_column(*name_column);

    m_tree_view.signal_row_activated().connect(
        sigc::mem_fun(*this, &PocketLauncher::on_row_activated));

    m_scrolled_window.add(m_tree_view);
    m_scrolled_window.set_policy(Gtk::POLICY_NEVER, Gtk::POLICY_AUTOMATIC);
    m_main_box.pack_start(m_scrolled_window);

    // Reload icons if the user switches icon theme while Pocket is resident.
    Gtk::IconTheme::get_default()->signal_changed().connect([this]() {
        m_icon_cache.clear();
        m_fallback_icon.reset();
        start_icon_loading();
    });

    remember_config_mtime();
    apply_config();
    load_applications();
    show_all_children();
}

void PocketLauncher::apply_config() {
    std::string font_family = m_config.count("font") ? m_config["font"] : "Monospace";
    int font_size = config_int(m_config, "font-size", 12, 6);
    std::string background = config_color(m_config, "background", "rgba(40,40,40,0.95)");
    std::string foreground = config_color(m_config, "foreground", "rgb(255,255,255)");
    std::string accent = config_color(m_config, "accent", "rgb(52,101,164)");

    resize(config_int(m_config, "width", 600, 200), config_int(m_config, "height", 400, 100));
    m_max_results = config_int(m_config, "max-results", 0, 0);

    // The entry and list are tinted overlays on the window background, so
    // they follow whatever background colour is configured.
    std::string css = "window { background-color: " + background + "; }";
    css += "entry, treeview, treeview.view, label { font-family: '" + font_family +
           "'; font-size: " + std::to_string(font_size) + "px; }";
    css += "entry { background: alpha(" + foreground + ", 0.08); color: " + foreground +
           "; caret-color: " + foreground + "; border: 1px solid alpha(" + foreground +
           ", 0.2); border-radius: 5px; padding: 8px; }";
    css += "treeview { background: alpha(" + foreground + ", 0.04); color: " + foreground +
           "; }";
    css += "treeview:selected { background: " + accent + "; }";

    try {
        // Replaces whatever the provider held before.
        m_css_provider->load_from_data(css);
    } catch (const Glib::Error& ex) {
        std::cerr << "CSS error: " << ex.what() << std::endl;
    }

    m_name_renderer->property_font() = font_family + " " + std::to_string(font_size);

    // Icon theme: set it when configured, and fall back to the system theme
    // if the key is removed later. A change fires IconTheme::signal_changed,
    // which reloads the icons.
    auto settings = Gtk::Settings::get_default();
    if (settings) {
        std::string icon_theme = m_config.count("icon-theme") ? m_config["icon-theme"] : "";
        if (!icon_theme.empty()) {
            settings->property_gtk_icon_theme_name() = icon_theme;
            m_icon_theme_overridden = true;
        } else if (m_icon_theme_overridden) {
            gtk_settings_reset_property(settings->gobj(), "gtk-icon-theme-name");
            m_icon_theme_overridden = false;
        }
    }

    m_tree_view.queue_resize();
}

void PocketLauncher::remember_config_mtime() {
    std::error_code ec;
    m_config_mtime = std::filesystem::last_write_time(pocket_config_path(), ec);
    m_config_exists = !ec;
}

bool PocketLauncher::config_changed() const {
    std::error_code ec;
    auto mtime = std::filesystem::last_write_time(pocket_config_path(), ec);
    if (ec)
        return m_config_exists;
    return !m_config_exists || mtime != m_config_mtime;
}

void PocketLauncher::reload_config_if_changed() {
    if (!config_changed())
        return;
    remember_config_mtime();
    m_config = load_pocket_config();
    apply_config();
    filter_apps(); // max-results may have changed
}

PocketLauncher::~PocketLauncher() {
    m_icon_idle.disconnect();
}

void PocketLauncher::show_launcher() {
    // A stat or two per show: cheap enough to keep the hotkey instant.
    reload_config_if_changed();
    if (apps_changed())
        load_applications();

    show();
    present();
    m_entry.grab_focus();

#ifdef GDK_WINDOWING_X11
    // When activated over D-Bus by a second `pocket` invocation there is no
    // input event to take a timestamp from, so the window manager's focus
    // stealing prevention may refuse focus. Use the X server's current time.
    auto gdk_window = get_window();
    if (gdk_window && GDK_IS_X11_WINDOW(gdk_window->gobj())) {
        gdk_window->focus(gdk_x11_get_server_time(gdk_window->gobj()));
    }
#endif
}

void PocketLauncher::hide_launcher() {
    hide();
    // Reset now, while hidden, so the next show is instant.
    if (m_entry.get_text().empty())
        filter_apps();
    else
        m_entry.set_text("");
}

bool PocketLauncher::on_delete_event(GdkEventAny*) {
    hide_launcher();
    return true;
}

bool PocketLauncher::apps_changed() const {
    for (const auto& dir : m_app_dirs) {
        std::error_code ec;
        auto mtime = std::filesystem::last_write_time(dir, ec);
        auto it = m_dir_mtimes.find(dir);
        bool known = it != m_dir_mtimes.end();
        if (ec ? known : (!known || it->second != mtime))
            return true;
    }
    return false;
}

void PocketLauncher::load_applications() {
    m_all_apps.clear();
    m_dir_mtimes.clear();
    for (const auto& dir : m_app_dirs) {
        std::error_code ec;
        auto mtime = std::filesystem::last_write_time(dir, ec);
        if (ec)
            continue;
        m_dir_mtimes[dir] = mtime;
        scan_directory(dir);
    }
    std::sort(m_all_apps.begin(), m_all_apps.end(),
              [](const AppInfo& a, const AppInfo& b) { return a.name < b.name; });
    filter_apps();
    start_icon_loading();
}

void PocketLauncher::scan_directory(const std::filesystem::path& dir) {
    try {
        for (const auto& entry : std::filesystem::directory_iterator(dir)) {
            if (entry.is_regular_file() && entry.path().extension() == ".desktop") {
                parse_desktop_file(entry.path());
            }
        }
    } catch (const std::filesystem::filesystem_error& ex) {
        std::cerr << "Error scanning " << dir << ": " << ex.what() << std::endl;
    }
}

void PocketLauncher::parse_desktop_file(const std::filesystem::path& file_path) {
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

void PocketLauncher::filter_apps() {
    std::string search_text = m_entry.get_text();
    std::transform(search_text.begin(), search_text.end(), search_text.begin(), ::tolower);

    m_list_store->clear();

    size_t shown = 0;
    // As on macOS, the empty view always lists every app.
    size_t limit = search_text.empty() ? 0 : m_max_results;

    for (const auto& app : m_all_apps) {
        if (limit && shown >= limit)
            break;

        std::string app_name_lower = app.name;
        std::transform(app_name_lower.begin(), app_name_lower.end(), app_name_lower.begin(),
                       ::tolower);

        if (search_text.empty() || app_name_lower.find(search_text) != std::string::npos) {
            ++shown;
            auto row = *(m_list_store->append());
            row[m_col_name] = app.name;
            row[m_col_exec] = app.exec;

            row[m_col_icon_name] = app.icon;
            row[m_col_icon] = cached_icon(app.icon);
        }
    }

    if (m_list_store->children().size() > 0) {
        Gtk::TreePath first_path("0");
        m_tree_view.set_cursor(first_path);
    }
}

Glib::RefPtr<Gdk::Pixbuf> PocketLauncher::cached_icon(const std::string& name) const {
    auto it = m_icon_cache.find(name);
    return it != m_icon_cache.end() ? it->second : Glib::RefPtr<Gdk::Pixbuf>();
}

Glib::RefPtr<Gdk::Pixbuf> PocketLauncher::load_icon(const std::string& name) {
    auto it = m_icon_cache.find(name);
    if (it != m_icon_cache.end())
        return it->second;

    auto icon_theme = Gtk::IconTheme::get_default();
    Glib::RefPtr<Gdk::Pixbuf> icon;
    try {
        if (!name.empty()) {
            if (Glib::file_test(name, Glib::FILE_TEST_EXISTS)) {
                icon = Gdk::Pixbuf::create_from_file(name, 24, 24);
            } else {
                auto icon_info = icon_theme->lookup_icon(name, 24, Gtk::ICON_LOOKUP_FORCE_SIZE);
                if (icon_info)
                    icon = icon_info.load_icon();
            }
        }
    } catch (const Glib::Error&) {
    }

    if (!icon) {
        if (!m_fallback_icon) {
            try {
                auto icon_info = icon_theme->lookup_icon("application-x-executable", 24,
                                                         Gtk::ICON_LOOKUP_FORCE_SIZE);
                if (icon_info)
                    m_fallback_icon = icon_info.load_icon();
            } catch (const Glib::Error&) {
            }
        }
        icon = m_fallback_icon;
    }

    m_icon_cache[name] = icon;
    return icon;
}

void PocketLauncher::start_icon_loading() {
    m_icon_load_pos = 0;
    if (!m_icon_idle.connected()) {
        m_icon_idle = Glib::signal_idle().connect(
            sigc::mem_fun(*this, &PocketLauncher::load_icon_batch), Glib::PRIORITY_LOW);
    }
}

bool PocketLauncher::load_icon_batch() {
    // Load a few icons per idle cycle so input and drawing stay responsive.
    const size_t batch = 8;
    size_t loaded = 0;
    while (m_icon_load_pos < m_all_apps.size() && loaded < batch) {
        const auto& name = m_all_apps[m_icon_load_pos++].icon;
        if (!m_icon_cache.count(name)) {
            load_icon(name);
            ++loaded;
        }
    }

    if (m_icon_load_pos < m_all_apps.size())
        return true;

    refresh_icons();
    return false;
}

void PocketLauncher::refresh_icons() {
    for (auto& row : m_list_store->children()) {
        Glib::ustring name = row[m_col_icon_name];
        row[m_col_icon] = cached_icon(name);
    }
}

void PocketLauncher::on_entry_changed() {
    filter_apps();
}

void PocketLauncher::on_row_activated(const Gtk::TreeModel::Path& path,
                                      Gtk::TreeViewColumn* column) {
    auto iter = m_list_store->get_iter(path);
    if (iter) {
        Gtk::TreeModel::Row row = *iter;
        Glib::ustring exec_ustring = row[m_col_exec];
        std::string command = std::string(exec_ustring) + " &";
        std::system(command.c_str());
        hide_launcher();
    }
}

bool PocketLauncher::on_key_press_event(GdkEventKey* event) {
    if (event->keyval == GDK_KEY_Escape) {
        hide_launcher();
        return true;
    }
    return Gtk::Window::on_key_press_event(event);
}
