#pragma once
#include <map>
#include <string>

std::string pocket_config_path();
std::map<std::string, std::string> load_pocket_config();
