package pocket

import (
	"bufio"
	"os"
	"os/user"
	"path/filepath"
	"sort"
	"strings"
)

type AppInfo struct {
	Name     string
	Exec     string
	IconName string // as in the .desktop file (may be a path or icon theme name)
}

func appDirs() []string {
	dirs := []string{
		"/usr/share/applications",
		"/usr/local/share/applications",
		"/var/lib/snapd/desktop/applications",
		"/var/lib/flatpak/exports/share/applications",
	}

	usr, err := user.Current()
	if err == nil {
		home := usr.HomeDir
		dirs = append(dirs,
			filepath.Join(home, ".local", "share", "applications"),
			filepath.Join(home, ".local", "share", "flatpak", "exports", "share", "applications"),
		)
	}

	return dirs
}

func LoadApplications() ([]AppInfo, error) {
	var apps []AppInfo

	for _, dir := range appDirs() {
		entries, err := os.ReadDir(dir)
		if err != nil {
			continue
		}

		for _, e := range entries {
			if e.IsDir() {
				continue
			}
			if filepath.Ext(e.Name()) != ".desktop" {
				continue
			}
			path := filepath.Join(dir, e.Name())
			if app, ok := parseDesktopFile(path); ok {
				apps = append(apps, app)
			}
		}
	}

	sort.Slice(apps, func(i, j int) bool {
		return apps[i].Name < apps[j].Name
	})

	return apps, nil
}

func parseDesktopFile(path string) (AppInfo, bool) {
	f, err := os.Open(path)
	if err != nil {
		return AppInfo{}, false
	}
	defer f.Close()

	var app AppInfo
	scanner := bufio.NewScanner(f)
	inDesktopEntry := false

	for scanner.Scan() {
		line := scanner.Text()
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		if strings.HasPrefix(line, "[") {
			inDesktopEntry = (line == "[Desktop Entry]")
			continue
		}

		if !inDesktopEntry {
			continue
		}

		kv := strings.SplitN(line, "=", 2)
		if len(kv) != 2 {
			continue
		}

		key := strings.TrimSpace(kv[0])
		value := strings.TrimSpace(kv[1])

		switch key {
		case "Name":
			app.Name = value
		case "Exec":
			app.Exec = stripExecArgs(value)
		case "Icon":
			app.IconName = value
		case "NoDisplay":
			if strings.EqualFold(value, "true") {
				return AppInfo{}, false
			}
		case "Hidden":
			if strings.EqualFold(value, "true") {
				return AppInfo{}, false
			}
		}
	}

	if app.Name == "" || app.Exec == "" {
		return AppInfo{}, false
	}

	return app, true
}

func stripExecArgs(exec string) string {
	if idx := strings.Index(exec, "%"); idx >= 0 {
		exec = exec[:idx]
	}
	return strings.TrimSpace(exec)
}
