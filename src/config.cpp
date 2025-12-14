#include "config.h"
#include <fstream>
#include <glibmm.h>

std::map<std::string, std::string> load_pocket_config() {
    std::map<std::string, std::string> config = {
        {"font", "Monospace"},
        {"font-size", "12"},
        {"icon-theme", ""}
    };

    std::string path = Glib::get_home_dir() + "/.config/pocket/pocketrc";
    std::ifstream file(path);
    if (!file.is_open())
        return config;

    std::string line;
    while (std::getline(file, line)) {
        auto pos = line.find(':');
        if (pos == std::string::npos) continue;

        std::string key = line.substr(0, pos);
        std::string value = line.substr(pos + 1);

        key.erase(0, key.find_first_not_of(" \t"));
        key.erase(key.find_last_not_of(" \t") + 1);
        value.erase(0, value.find_first_not_of(" \t"));
        value.erase(value.find_last_not_of(" \t") + 1);

        config[key] = value;
    }

    return config;
}
