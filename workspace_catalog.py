#!/usr/bin/env python3
"""Read-only Hyprland workspace catalog, including configured but uncreated workspaces."""
import json
import re
import subprocess
import sys


def query(name):
    result = subprocess.run(["hyprctl", "-j", name], check=True, capture_output=True, text=True, timeout=5)
    value = json.loads(result.stdout)
    if not isinstance(value, list):
        raise ValueError(f"hyprctl {name} did not return a list")
    return value


def exact_workspace_id(value):
    if not isinstance(value, str) or not re.fullmatch(r"[1-9][0-9]*", value):
        return None
    result = int(value)
    return result if result <= 2_147_483_647 else None


def resolve_monitor(selector, monitors):
    if not isinstance(selector, str) or not selector:
        return None
    exact = [monitor for monitor in monitors if monitor.get("name") == selector]
    if len(exact) == 1:
        return exact[0]["name"]
    if selector.startswith("desc:"):
        description = selector[5:]
        matches = [monitor for monitor in monitors if monitor.get("description") == description]
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
        if type(wid) is int and wid > 0 and monitor in result:
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
    return catalog(query("monitors"), query("workspaces"), query("workspacerules"))


if __name__ == "__main__":
    try:
        print(json.dumps(main(), separators=(",", ":")))
    except Exception as error:
        print(json.dumps({"ok": False, "message": str(error)}, separators=(",", ":")))
        sys.exit(1)
