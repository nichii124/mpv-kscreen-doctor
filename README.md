# mpv-kscreen-doctor

`mpv-kscreen-doctor.lua` is an [mpv](https://mpv.io/) Lua script that adjusts the display refresh rate using the `kscreen-doctor` utility. When playback starts it searches the active outputs for modes matching the current resolution and switches to the refresh rate that best matches the video's FPS. When mpv exits the previous modes are restored.

## Dependencies
- [mpv](https://mpv.io/)
- [`kscreen-doctor`](https://invent.kde.org/plasma/kscreen)

## Installation
1. Ensure the `kscreen-doctor` command from KDE is available on your system.
2. Copy `mpv-kscreen-doctor.lua` to mpv's scripts directory (typically `~/.config/mpv/scripts/`).
3. Restart mpv or reload scripts.

## How it works
- On the first run the script saves the current mode of each active output to `/tmp/mpv-kscreen-doctor.modes`.
- A process id file is stored at `/run/user/UID/mpv-kscreen-doctor.pid` (falling back to `/tmp` if the user id cannot be determined). Each running mpv process updates this file so the script knows when the last instance exits.
- When all mpv processes using the script have closed, the saved modes are restored and the PID and mode files are removed.

This allows multiple mpv instances to run without stepping on each other while ensuring the display returns to its previous configuration when playback finishes.
