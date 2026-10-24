#!/usr/bin/env python3
"""Read-only Hyprland workspace catalog, including configured but uncreated workspaces."""
import json
import re
import subprocess
import sys

# The only compositor state this plugin ever reads. Nothing is written: monitor
# configuration, workspace rules and profiles belong to Hyprland and HyprMonCfg.
READ_ONLY_QUERIES = ("monitors", "workspaces", "workspacerules")
MAX_WORKSPACE_ID = 2_147_483_647
QUERY_TIMEOUT_SECONDS = 5


def query(name):
    """Run one read-only ``hyprctl -j <name>`` and return the decoded list."""
    if name not in READ_ONLY_QUERIES:
        raise ValueError(f"{name} is not a read-only query")
    result = subprocess.run(
        ["hyprctl", "-j", name],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        stdin=subprocess.DEVNULL,
        timeout=QUERY_TIMEOUT_SECONDS,
    )
    value = json.loads(result.stdout)
    if not isinstance(value, list):
        raise ValueError(f"hyprctl {name} did not return a list")
    return value


def optional_query(name):
    """Query that may be unsupported: an older compositor still gets live workspaces."""
    try:
        return query(name)
    except (OSError, ValueError, subprocess.SubprocessError):
        return []


def exact_workspace_id(value):
    if not isinstance(value, str) or len(value) > 10:
        return None
    if not re.fullmatch(r"[1-9][0-9]*", value):
        return None
    result = int(value)
    return result if result <= MAX_WORKSPACE_ID else None


def resolve_monitor(selector, monitors):
    if not isinstance(selector, str) or not selector:
        return None
    exact = [monitor for monitor in monitors
             if isinstance(monitor, dict) and monitor.get("name") == selector]
    if len(exact) == 1:
        return exact[0]["name"]
    if selector.startswith("desc:"):
        description = selector[5:]
        matches = [monitor for monitor in monitors
                   if isinstance(monitor, dict) and monitor.get("description") == description]
        if len(matches) == 1:
            return matches[0]["name"]
    return None


def catalog(monitors, workspaces, rules):
    live = [monitor for monitor in monitors
            if isinstance(monitor, dict) and isinstance(monitor.get("name"), str)
            and monitor["name"] and not monitor.get("disabled")
            and monitor.get("mirrorOf", "none") in ("", "none", None)]
    result = {monitor["name"]: set() for monitor in live}
    assigned = set()
    for workspace in workspaces:
        if not isinstance(workspace, dict):
            continue
        wid, monitor = workspace.get("id"), workspace.get("monitor")
        if type(wid) is int and wid > 0 and isinstance(monitor, str) and monitor in result:
            result[monitor].add(wid)
            assigned.add(wid)
    for rule in rules:
        if not isinstance(rule, dict) or rule.get("enabled") is not True:
            continue
        wid = exact_workspace_id(rule.get("workspaceString"))
        monitor = resolve_monitor(rule.get("monitor"), live)
        if wid is not None and wid not in assigned and monitor is not None:
            result[monitor].add(wid)
    return {"ok": True, "workspaces": {name: sorted(ids) for name, ids in result.items()}}


def main():
    monitors = query("monitors")
    workspaces = query("workspaces")
    return catalog(monitors, workspaces, optional_query("workspacerules"))


if __name__ == "__main__":
    try:
        print(json.dumps(main(), separators=(",", ":")))
    except Exception as error:
        # Bounded so a compositor error string never grows into a log of paths.
        message = str(error).replace("\n", " ")[:200]
        print(json.dumps({"ok": False, "message": message}, separators=(",", ":")))
        sys.exit(1)
