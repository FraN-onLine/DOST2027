# Exporting a Windows build

Testers do not need the Godot editor, only the zip.

## One-time setup

1. Open the project in Godot 4.7.
2. Editor > Manage Export Templates > Download and Install (for 4.7).
3. The **Windows Desktop** preset is already saved in `export_presets.cfg`.

## Build

1. Project > Export > **Windows Desktop** > **Export Project**. It writes
   `builds/windows/Bathala.exe` (the PCK is embedded, so it is one file;
   `builds/` is git-ignored).
2. Zip `builds/windows/` and share it.

From a terminal (run the import first when assets were just added):

```sh
godot --headless --path . --import
godot --headless --path . --export-release "Windows Desktop" builds/windows/Bathala.exe
```

## Preset settings that matter

- **Export Mode: Export all resources in the project** (`export_filter="all_resources"`).
  Do **not** switch to "Export selected scenes (and dependencies)". The gods and
  the Pamana are found by scanning `res://resources/gods/` and
  `res://resources/pamana/`, and several pieces of art are loaded from paths built
  at runtime. A "selected scenes" export ships an empty god list, an empty
  Tindahan, or missing art.
- **Filters to export non-resource files:** blank. The game only loads Godot
  resources. If you ever add a file type Godot does not import (e.g. `.json`,
  `.csv`), add it here (`*.json,*.csv`) or it will not be in the PCK.
- **Filters to exclude files:**
  `tools/*,addons/*,builds/*,*.md,*.ps1,*.txt,_fix_gd*.py`.
  Test tools, the local MCP addon, old builds and docs stay out of the game.
- **Embed PCK:** on - the `.exe` is self-contained.
- **Binary format / architecture:** x86_64.
- **Application icon:** `res://Assets/Placeholders/app-icon.ico`.

The Linux preset is configured next to it, but the Windows build is the one
that has been verified.

## Why assets used to disappear after export

Exported builds store a text resource as `foo.tres.remap` (the data itself is
packed as `foo.res`). `load(".../foo.tres")` still works, but
`DirAccess.get_files()` returns the **`.remap`** name, not the `.tres` name.
`Gods` and `Pamanas` now strip `.remap` before filtering, so they find every
god and heirloom in a packaged build. Any new folder scanner must do the same.

## Verify a build

Boot the exported game without a window and check the log:

```sh
builds/windows/Bathala.exe --headless --quit-after 240 --log-file build.log
```

No `SCRIPT ERROR`, `Failed to load`, or `Cannot open` lines means every resource
resolved. `--quit-after` counts frames, so 240 is about four seconds at 60 FPS.

## What testers will see

- **Windows SmartScreen** ("Windows protected your PC"): the build is not
  code-signed. Click **More info > Run anyway**.
- **Windows Firewall** prompt the first time someone hosts: **allow Private and
  Public** networks, or friends on a VPN cannot connect.

## Joining over a VPN (ZeroTier, Tailscale, Radmin, Hamachi)

The ON YOUR NETWORK list uses UDP broadcast, which these VPNs often do not
carry. The host reads the IPs from the lobby ("Your IPs: ..."), and friends type
one into **HOST IP** on the Join screen and press JOIN BY IP (`ip` or `ip:port`;
a Tailscale name like `lamp-pc` works too).

## Notes

- The build is about 125 MB because "all resources" also packs art and audio
  from the older game that the current modes no longer use (`Sounds/`,
  `Assets/cards/`, `Assets/buildings/`, `Assets/landscape/`). Add those folders
  to the exclude filter only after confirming nothing loads them.
- `UI/card_slot.tscn` is an unused leftover that references a removed `Card`
  class. It is not loaded, so it does not affect the build; exclude or delete it
  to silence the editor parse error.
