# Backdrop

Desktop backgrounds per workspace or monitor, with timed rotation and animated
transitions — an [Omarchy](https://omarchy.org) plugin based on its original
`omarchy.background` plugin. It preserves the desktop background picker, theme
switcher, and theme-change transitions.

Choose a background for each workspace, pin one to each monitor, or rotate
through your theme's images. A bar button opens the settings panel.

![Backdrop demo: workspace backgrounds, rotation, and transitions](assets/backdrop-demo.gif)

## Requirements

- Omarchy's Quickshell shell and Lua Hyprland configuration
- Python 3 (standard library only), Bash, `jq`, and Omarchy's shell utilities

Validated locally against Omarchy `4.0.0.alpha`, Quickshell `0.3.1`, and Qt
`6.11.2`. Backdrop runs as your user.

## Install

```bash
omarchy plugin add https://github.com/mpriem/omarchy-backdrop-plugin
omarchy plugin disable omarchy.background
omarchy plugin enable backgrounds right
```

The plugin ID is `backgrounds`; `right` adds its button to the bar. Backdrop
replaces the built-in background service, so only one should be enabled.

## Configuration and local data

Use the bar button to choose a mode, assign images, and adjust transitions.

| Mode | Behavior |
| --- | --- |
| Classic | One background everywhere, using Omarchy's usual selection |
| Workspace | A background for each monitor's active workspace, assigned manually or distributed from the theme's images |
| Pinned | A chosen background for each monitor |
| Rotate | Change at an interval, in order or randomly, with the same or different images per monitor |

Images come from the current theme and your additions in
`~/.config/omarchy/backgrounds/<theme>/`. Workspace and monitor assignments are
saved per theme. Transitions include cut, fade, slide, zoom, wipe, and reveal,
with durations up to two seconds.

Settings are stored in `~/.config/omarchy/background.json`; manual edits reload
automatically. Invalid settings keep the last working configuration active.
The plugin expects the default installation location,
`~/.config/omarchy/plugins/backgrounds`.

For scripts, use `omarchy-shell background`, for example:

```bash
omarchy-shell background mode workspace
omarchy-shell background rotateEvery 30m
omarchy-shell background rotateNow
omarchy-shell background statusSafe
```

`statusSafe` reports counts and mode without personal paths or monitor names.
The full `status` command includes those details.

## Remove

```bash
omarchy plugin disable backgrounds
omarchy plugin remove backgrounds
omarchy plugin enable omarchy.background
```

Removal leaves your images and saved settings in place.

## Keys

| Action | Result |
| --- | --- |
| Double-click the desktop | Open the background picker |
| Right-double-click the desktop | Open the theme switcher |
| Click the bar button | Open settings |
| `Tab` / `Shift+Tab` in settings | Move between sections |
| Arrow keys or `h` / `j` / `k` / `l` | Navigate controls |
| `Enter` | Confirm a selection |

A desktop pick applies everywhere in Classic mode, to the active workspace in
Workspace mode, or to the monitor in Pinned mode. In Rotate mode it displays the
chosen image immediately and restarts the timer. Sliders and interval controls
apply changes as you adjust them.

## Development

Run `./tests/validate.sh` with Node.js, Python 3, Quickshell, Qt 6's `qmlformat`,
and `omarchy-plugin-validate` installed. Tests use temporary homes and do not
change the active desktop. Multi-monitor rendering, GPU effects, and theme
handoff still need live desktop testing.

## License

[MIT](LICENSE).
