# Exporting a Windows build

Testers do not need the Godot editor, only the zip.

1. **Once:** open the project in Godot 4.7, then Editor > Manage Export Templates > Download and Install (for 4.7).
2. Project > Export > **Windows Desktop** > Export Project. It writes `builds/windows/Bathala.exe` (the PCK is embedded, so it is one file; `builds/` is git-ignored).
3. Zip `builds/windows/` and share it.

## What testers will see
- **Windows SmartScreen** ("Windows protected your PC"): the build is not code-signed. Click **More info > Run anyway**.
- **Windows Firewall** prompt the first time someone hosts: **allow Private and Public** networks, or friends on a VPN cannot connect.

## Joining over a VPN (ZeroTier, Tailscale, Radmin, Hamachi)
The ON YOUR NETWORK list uses UDP broadcast, which these VPNs often do not carry. The host reads the IPs from the lobby ("Your IPs: ..."), and friends type one into **HOST IP** on the Join screen and press JOIN BY IP (`ip` or `ip:port`; a Tailscale name like `lamp-pc` works too).

## The `godot_ai` addon error
`project.godot` registers the autoload `_mcp_game_helper` from `addons/godot_ai/`, which is git-ignored (a local editor tool). Without that folder the console prints `Failed to instantiate an autoload, can't load from path: res://addons/godot_ai/runtime/game_helper.gd`. It is harmless: the game runs and exports without it.
