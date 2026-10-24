# Agent instructions

Omarchy Display Workspaces Lite is a read-only display/workspace menubar companion for HyprMonCfg. Its plugin ID is `display.workspaces.lite`.

Keep the product limited to display names, icons, display-group ordering, cursor-display highlighting, visible/focused workspace indicators, and read-only discovery of exact positive workspace declarations. It must never write monitor configuration, workspace rules, profiles, output state, or geometry. HyprMonCfg and Hyprland own those concerns.

`workspace_catalog.py` may only query `hyprctl -j monitors`, `workspaces`, and `workspacerules`. Resolve only exact connector selectors and unique exact `desc:` selectors. Ignore broad, named, special, ambiguous, disabled, and invalid rules. Existing live workspace placement always wins over a configured rule.

Use Omarchy host QML components and Python's standard library. Preserve MIT attribution and the GPT Astra caution. Validate with `omarchy plugin validate .` and `python3 -m unittest discover` (catalog behaviour plus the repo guards in `test_plugin_hygiene.py`). Exercise QML in the real linked Omarchy shell before release. Never commit private monitor identities, serials, paths, captures, or runtime state.

Quickshell already relays every Hyprland event as `Hyprland.rawEvent`; do not add a second event socket. Focusing a declared-but-uncreated workspace needs the host's dispatch syntax: `hl.dsp.focus({ workspace = "N" })` when `Hyprland.usingLua`, plain `workspace N` otherwise, with a fallback on a rejected attempt.
