#include "config.h"
#include <fstream>
#include <glibmm.h>

static void trim(std::string& s) {
    s.erase(0, s.find_first_not_of(" \t\r"));
    s.erase(s.find_last_not_of(" \t\r") + 1);
}

std::string pocket_config_path() {
    return Glib::get_home_dir() + "/.config/pocket/pocketrc";
}

std::map<std::string, std::string> load_pocket_config() {
    std::map<std::string, std::string> config = {{"font", "Monospace"},
                                                 {"font-size", "12"},
                                                 {"icon-theme", ""},
                                                 {"width", "600"},
                                                 {"height", "400"},
                                                 {"background", "rgba(40, 40, 40, 0.95)"},
                                                 {"foreground", "#ffffff"},
                                                 {"accent", "#3465a4"},
                                                 {"max-results", "0"}};

    std::ifstream file(pocket_config_path());
    if (!file.is_open())
        return config;

    std::string line;
    while (std::getline(file, line)) {
        trim(line);
        if (line.empty() || line[0] == '#')
            continue;

        auto pos = line.find(':');
        if (pos == std::string::npos)
            continue;

        std::string key = line.substr(0, pos);
        std::string value = line.substr(pos + 1);
        trim(value);

        // Inline comments start with whitespace + '#', so "accent: #7C5CFF"
        // keeps its colour while "font-size: 16  # bigger" drops the note.
        for (size_t i = 1; i < value.size(); ++i) {
            if (value[i] == '#' && (value[i - 1] == ' ' || value[i - 1] == '\t')) {
                value.erase(i);
                break;
            }
        }

        trim(key);
        trim(value);
        if (!key.empty() && !value.empty())
            config[key] = value;
    }

    return config;
}
