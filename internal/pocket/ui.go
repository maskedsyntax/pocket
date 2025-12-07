package pocket

import (
	"os/exec"
	"strings"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/app"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/widget"
)

func Run() {
	// load config (for now not used in UI, but kept for future styling)
	_ = LoadConfig()

	apps, _ := LoadApplications() // if this fails, we just have an empty list

	filtered := make([]AppInfo, len(apps))
	copy(filtered, apps)
	selectedIndex := -1

	a := app.NewWithID("com.maskedsyntax.pocket")

	w := a.NewWindow("pocket")
	w.Resize(fyne.NewSize(600, 400))
	w.CenterOnScreen()

	entry := widget.NewEntry()
	entry.SetPlaceHolder("Type to search applications...")

	list := widget.NewList(
		func() int {
			return len(filtered)
		},
		func() fyne.CanvasObject {
			return widget.NewLabel("")
		},
		func(id widget.ListItemID, obj fyne.CanvasObject) {
			if id < 0 || int(id) >= len(filtered) {
				return
			}
			lbl := obj.(*widget.Label)
			lbl.SetText(filtered[id].Name)
		},
	)

	list.OnSelected = func(id widget.ListItemID) {
		if int(id) < 0 || int(id) >= len(filtered) {
			return
		}
		selectedIndex = int(id)
	}

	entry.OnChanged = func(text string) {
		q := strings.ToLower(strings.TrimSpace(text))

		filtered = filtered[:0]
		if q == "" {
			filtered = append(filtered, apps...)
		} else {
			for _, appInfo := range apps {
				if strings.Contains(strings.ToLower(appInfo.Name), q) {
					filtered = append(filtered, appInfo)
				}
			}
		}

		list.Refresh()

		if len(filtered) > 0 {
			selectedIndex = 0
			list.Select(0)
		} else {
			selectedIndex = -1
		}
	}

	entry.OnSubmitted = func(_ string) {
		if len(filtered) == 0 {
			return
		}
		if selectedIndex < 0 || selectedIndex >= len(filtered) {
			selectedIndex = 0
		}
		launch(filtered[selectedIndex])
		w.Close()
	}

	w.Canvas().SetOnTypedKey(func(k *fyne.KeyEvent) {
		switch k.Name {
		case fyne.KeyEscape:
			w.Close()
		case fyne.KeyDown:
			if len(filtered) == 0 {
				return
			}
			if selectedIndex < 0 || selectedIndex >= len(filtered)-1 {
				selectedIndex = 0
			} else {
				selectedIndex++
			}
			list.Select(widget.ListItemID(selectedIndex))
		case fyne.KeyUp:
			if len(filtered) == 0 {
				return
			}
			if selectedIndex <= 0 {
				selectedIndex = 0
			} else {
				selectedIndex--
			}
			list.Select(widget.ListItemID(selectedIndex))
		case fyne.KeyReturn, fyne.KeyEnter:
			if len(filtered) == 0 {
				return
			}
			if selectedIndex < 0 || selectedIndex >= len(filtered) {
				selectedIndex = 0
			}
			launch(filtered[selectedIndex])
			w.Close()
		}
	})

	content := container.NewBorder(entry, nil, nil, nil, list)
	w.SetContent(content)

	w.Show()
	a.Run()
}

func launch(appInfo AppInfo) {
	if appInfo.Exec == "" {
		return
	}
	cmd := exec.Command("sh", "-c", appInfo.Exec+" &")
	cmd.Stdout = nil
	cmd.Stderr = nil
	cmd.Stdin = nil
	_ = cmd.Start()
}
