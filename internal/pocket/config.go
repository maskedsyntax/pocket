package pocket

import (
	"bufio"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

type Config struct {
	Font     string
	FontSize int
	Icon     string
}

func defaultConfig() Config {
	return Config{
		Font:     "JetBrains Mono",
		FontSize: 12,
		Icon:     "",
	}
}

func configPath() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return filepath.Join(home, ".config", "pocket", "pocketrc")
}

func LoadConfig() Config {
	cfg := defaultConfig()
	path := configPath()
	if path == "" {
		return cfg
	}

	f, err := os.Open(path)
	if err != nil {
		return cfg
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		parts := strings.SplitN(line, ":", 2)
		if len(parts) != 2 {
			continue
		}
		key := strings.TrimSpace(parts[0])
		value := strings.TrimSpace(parts[1])
		switch key {
		case "font":
			if value != "" {
				cfg.Font = value
			}
		case "font-size":
			if v, err := strconv.Atoi(value); err == nil && v > 0 {
				cfg.FontSize = v
			}
		case "icon":
			cfg.Icon = value
		}
	}

	return cfg
}
