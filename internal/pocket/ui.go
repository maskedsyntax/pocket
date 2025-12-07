package pocket

import (
	"os/exec"
	"strings"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/app"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/widget"
)

// searchEntry extends widget.Entry so we can intercept keys like
// Esc / Up / Down / Enter even when the entry has focus.
type searchEntry struct {
	widget.Entry

	onEscape func()
	onUp     func()
	onDown   func()
	onEnter  func()
}

func newSearchEntry() *searchEntry {
	e := &searchEntry{}
	e.ExtendBaseWidget(e)
	return e
}

// TypedKey is called for key events when this entry has focus.
func (e *searchEntry) TypedKey(ev *fyne.KeyEvent) {
	switch ev.Name {
	case fyne.KeyEscape:
		if e.onEscape != nil {
			e.onEscape()
			return
		}
	case fyne.KeyUp:
		if e.onUp != nil {
			e.onUp()
			return
		}
	case fyne.KeyDown:
		if e.onDown != nil {
			e.onDown()
			return
		}
	case fyne.KeyReturn, fyne.KeyEnter:
		if e.onEnter != nil {
			e.onEnter()
			return
		}
	}

	// default behavior (text, cursor, etc.)
	e.Entry.TypedKey(ev)
}

// Run is called from cmd/pocket/main.go
func Run() {
	_ = LoadConfig() // kept for future styling; unused for now

	apps, _ := LoadApplications()

	// filtered slice + selected index
	filtered := make([]AppInfo, len(apps))
	copy(filtered, apps)
	selectedIndex := -1

	a := app.NewWithID("pocket-launcher")
	w := a.NewWindow("Pocket Launcher")
	w.Resize(fyne.NewSize(600, 400))
	w.CenterOnScreen()

	entry := newSearchEntry()
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

	// helpers so we can reuse logic from both entry and window-level key handlers
	moveSelectionDown := func() {
		if len(filtered) == 0 {
			selectedIndex = -1
			return
		}
		if selectedIndex < 0 || selectedIndex >= len(filtered)-1 {
			selectedIndex = 0
		} else {
			selectedIndex++
		}
		list.Select(widget.ListItemID(selectedIndex))
	}

	moveSelectionUp := func() {
		if len(filtered) == 0 {
			selectedIndex = -1
			return
		}
		if selectedIndex <= 0 {
			selectedIndex = 0
		} else {
			selectedIndex--
		}
		list.Select(widget.ListItemID(selectedIndex))
	}

	launchSelected := func() {
		if len(filtered) == 0 {
			return
		}
		if selectedIndex < 0 || selectedIndex >= len(filtered) {
			selectedIndex = 0
		}
		launch(filtered[selectedIndex])
		w.Close()
	}

	quit := func() {
		w.Close()
	}

	// when user clicks or selects with keyboard in the list
	list.OnSelected = func(id widget.ListItemID) {
		if int(id) < 0 || int(id) >= len(filtered) {
			selectedIndex = -1
			return
		}
		selectedIndex = int(id)
	}

	// filter logic
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

	// Enter from entry: launch selection
	entry.OnSubmitted = func(_ string) {
		launchSelected()
	}

	// intercept keys while entry is focused
	entry.onEscape = quit
	entry.onUp = moveSelectionUp
	entry.onDown = moveSelectionDown
	entry.onEnter = launchSelected

	// also handle keys at the window level (when list or nothing has focus)
	w.Canvas().SetOnTypedKey(func(k *fyne.KeyEvent) {
		switch k.Name {
		case fyne.KeyEscape:
			quit()
		case fyne.KeyUp:
			moveSelectionUp()
		case fyne.KeyDown:
			moveSelectionDown()
		case fyne.KeyReturn, fyne.KeyEnter:
			launchSelected()
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
