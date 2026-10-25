"""Repo guards for the promises this plugin makes in AGENTS.md and README.md.

These run anywhere, with no compositor, no network and no Omarchy install, so a
pull request can reject a regression in the read-only contract, in the privacy
of committed files, or in the manifest before a human has to notice it.
"""
import json
import os
import re
import subprocess
import unittest

ROOT = os.path.dirname(os.path.abspath(__file__))
PLUGIN_ID = "display.workspaces.lite"
# The only Hyprland subcommands this plugin may name. The first three are the
# read-only catalog reads, the fourth is the pointer poll, and `dispatch` is the
# single non-query call: focusing a workspace the user clicked.
ALLOWED_SUBCOMMANDS = ("-j", "dispatch")
ALLOWED_JOINTERS = ("monitors", "workspaces", "workspacerules", "cursorpos")
READ_ONLY_QUERIES = ("monitors", "workspaces", "workspacerules")

HYPRCTL_HEAD = re.compile(r"\"hyprctl\"\s*,\s*\"([^\"]+)\"")
HYPRCTL_JOINED = re.compile(r"\"hyprctl\"\s*,\s*\"-j\"\s*,\s*\"([^\"]+)\"")
LUA_DISPATCHER = re.compile(r"hl\.dsp\.([A-Za-z_][\w.]*)")

PRIVATE_PATTERNS = (
    ("/home/ absolute path", re.compile(r"/home/")),
    ("/run/user/ absolute path", re.compile(r"/run/user/")),
    ("compositor instance signature variable", re.compile(r"HYPRLAND_INSTANCE_SIGNATURE")),
    ("32-hex compositor instance signature", re.compile(r"\b[0-9a-f]{32}\b")),
)
IMAGE_SUFFIXES = (".png", ".gif", ".jpg", ".jpeg", ".webp", ".ico")
MARKDOWN_IMAGE = re.compile(r"!\[[^\]]*\]\(([^)]+)\)")
DANGEROUS_PATTERNS = (
    ("shell execution", re.compile(r"\b(?:bash|sh)\s+-c\b")),
    ("shell quoting helper", re.compile(r"shellQuote")),
    ("detached shell execution", re.compile(r"execDetached")),
    ("bar shell runner", re.compile(r"\bbar\.run\s*\(")),
    ("shell=True", re.compile(r"shell\s*=\s*True")),
    ("file writing", re.compile(r"\b(?:fs\.writeFile|File\.write|writeFile)\b")),
    ("Qt.open", re.compile(r"Qt\.open")),
)


def tracked_files():
    try:
        listing = subprocess.run(["git", "-C", ROOT, "ls-files", "-z"], check=True,
                                 capture_output=True, text=True).stdout
    except (OSError, subprocess.CalledProcessError):
        listing = "\0".join(sorted(os.listdir(ROOT)))
    return [name for name in listing.split("\0")
            if name and os.path.isfile(os.path.join(ROOT, name)) and not name.endswith(".pyc")]


def read(name):
    with open(os.path.join(ROOT, name), encoding="utf-8") as handle:
        return handle.read()


class SourceContractTests(unittest.TestCase):
    def setUp(self):
        self.sources = {}
        self.images = []
        for name in tracked_files():
            if name.lower().endswith(IMAGE_SUFFIXES):
                self.images.append(name)
                continue
            self.sources[name] = read(name)
        self.code = {name: text for name, text in self.sources.items()
                     if name.endswith((".qml", ".py")) and not name.startswith("test_")}

    def test_python_catalog_reads_only_the_three_queries(self):
        import workspace_catalog
        self.assertEqual(workspace_catalog.READ_ONLY_QUERIES, READ_ONLY_QUERIES)
        self.assertEqual(workspace_catalog.QUERY_TIMEOUT_SECONDS, 5)
        self.assertNotIn("shell=True", self.sources["workspace_catalog.py"])

    def test_every_hyprctl_mention_uses_an_allowed_subcommand(self):
        for name, text in self.code.items():
            occurrences = text.count("\"hyprctl\"")
            heads = HYPRCTL_HEAD.findall(text)
            self.assertEqual(len(heads), occurrences, f"{name} builds an unparsed hyprctl call")
            for subcommand in heads:
                self.assertIn(subcommand, ALLOWED_SUBCOMMANDS, f"{name} runs hyprctl {subcommand!r}")
            for jointed in HYPRCTL_JOINED.findall(text):
                self.assertIn(jointed, ALLOWED_JOINTERS, f"{name} reads hyprctl -j {jointed!r}")

    def test_dispatch_only_ever_focuses_a_workspace(self):
        text = self.sources["Workspaces.qml"]
        self.assertEqual(set(LUA_DISPATCHER.findall(text)), {"focus"})
        self.assertIn("\"workspace \" + id", text)

    def test_no_shell_or_file_writing_reaches_the_shell(self):
        for name, text in self.code.items():
            for label, pattern in DANGEROUS_PATTERNS:
                self.assertIsNone(pattern.search(text), f"{name} uses {label}")

    def test_committed_files_hold_no_private_display_identity(self):
        # This module names the patterns it forbids, so it cannot be scanned.
        for name, text in self.sources.items():
            if name == os.path.basename(__file__):
                continue
            for label, pattern in PRIVATE_PATTERNS:
                match = pattern.search(text)
                self.assertIsNone(match, f"{name} contains {label}: {match and match.group(0)!r}")

    def test_documentation_images_live_in_docs_and_resolve(self):
        for name in self.images:
            self.assertTrue(name.startswith("docs/"), f"{name} should live under docs/")
            self.assertGreater(os.path.getsize(os.path.join(ROOT, name)), 1024,
                               f"{name} looks truncated")
        referenced = MARKDOWN_IMAGE.findall(self.sources["README.md"])
        self.assertTrue(referenced, "README lost its preview image")
        for target in referenced:
            self.assertFalse(target.startswith(("http://", "https://", "/")),
                             f"README should embed docs images locally, not {target!r}")
            self.assertTrue(os.path.exists(os.path.join(ROOT, target)), f"missing {target}")

    def test_manifest_matches_readme_and_points_at_existing_files(self):
        manifest = json.loads(read("manifest.json"))
        self.assertEqual(manifest["id"], PLUGIN_ID)
        self.assertEqual(manifest["schemaVersion"], 1)
        self.assertFalse(manifest["barWidget"]["allowMultiple"])
        self.assertRegex(manifest["version"], r"^\d+\.\d+\.\d+$")
        self.assertIn(f"**Version:** {manifest['version']}", self.sources["README.md"])
        for entry in manifest["entryPoints"].values():
            self.assertTrue(os.path.exists(os.path.join(ROOT, entry)), f"missing entry {entry}")
        for script in re.findall(r"Qt\.resolvedUrl\(\"([^\"]+)\"\)", self.sources["Workspaces.qml"]):
            self.assertTrue(os.path.exists(os.path.join(ROOT, script)), f"missing script {script}")

    def test_plugin_id_is_used_consistently(self):
        manifest = json.loads(read("manifest.json"))
        self.assertIn(PLUGIN_ID, self.sources[manifest["entryPoints"]["barWidget"]])
        panels = [name for name in self.sources if name.endswith("SettingsPanel.qml")]
        self.assertTrue(panels, "settings panel is missing")
        self.assertIn(PLUGIN_ID, self.sources[panels[0]])

    def test_attribution_and_caution_are_retained(self):
        license_text = read("LICENSE")
        self.assertIn("MIT License", license_text)
        self.assertIn("Permission is hereby granted", license_text)
        self.assertIn("basecamp/omarchy", read("README.md"))
        self.assertIn("GPT Astra", read("README.md"))


if __name__ == "__main__":
    unittest.main()
