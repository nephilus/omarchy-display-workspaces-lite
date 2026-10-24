import unittest
from unittest import mock

import workspace_catalog


class WorkspaceCatalogTests(unittest.TestCase):
    def setUp(self):
        self.monitors = [
            {"name": "eDP-1", "description": "Laptop Panel", "disabled": False},
            {"name": "DP-2", "description": "Desk Panel", "disabled": False},
            {"name": "DP-9", "description": "Sleeping Panel", "disabled": True},
        ]

    def test_merges_live_and_uncreated_exact_rules_by_connector_and_description(self):
        result = workspace_catalog.catalog(
            self.monitors,
            [{"id": 1, "monitor": "eDP-1"}, {"id": 4, "monitor": "DP-2"}],
            [
                {"workspaceString": "1", "enabled": True, "monitor": "desc:Laptop Panel"},
                {"workspaceString": "2", "enabled": True, "monitor": "desc:Laptop Panel"},
                {"workspaceString": "5", "enabled": True, "monitor": "DP-2"},
                {"workspaceString": "6", "enabled": True, "monitor": "DP-2"},
            ],
        )
        self.assertEqual(result["workspaces"], {"eDP-1": [1, 2], "DP-2": [4, 5, 6]})

    def test_live_workspace_placement_wins_over_rule(self):
        result = workspace_catalog.catalog(
            self.monitors,
            [{"id": 7, "monitor": "DP-2"}],
            [{"workspaceString": "7", "enabled": True, "monitor": "eDP-1"}],
        )
        self.assertEqual(result["workspaces"], {"eDP-1": [], "DP-2": [7]})

    def test_ignores_unsafe_or_inapplicable_rules(self):
        duplicate = self.monitors + [{"name": "DP-3", "description": "Desk Panel", "disabled": False}]
        result = workspace_catalog.catalog(
            duplicate,
            [],
            [
                {"workspaceString": "name:web", "enabled": True, "monitor": "eDP-1"},
                {"workspaceString": "special:scratch", "enabled": True, "monitor": "eDP-1"},
                {"workspaceString": "8", "enabled": False, "monitor": "eDP-1"},
                {"workspaceString": "9", "enabled": True, "monitor": "desc:Desk Panel"},
                {"workspaceString": "10", "enabled": True, "monitor": "DP-9"},
                {"workspaceString": "0", "enabled": True, "monitor": "eDP-1"},
            ],
        )
        self.assertEqual(result["workspaces"], {"eDP-1": [], "DP-2": [], "DP-3": []})

    def test_ignores_mirrored_monitors(self):
        result = workspace_catalog.catalog(
            self.monitors + [{"name": "DP-4", "description": "Copy", "mirrorOf": "DP-2"}],
            [{"id": 3, "monitor": "DP-4"}],
            [{"workspaceString": "4", "enabled": True, "monitor": "DP-4"}],
        )
        self.assertEqual(result["workspaces"], {"eDP-1": [], "DP-2": []})

    def test_survives_malformed_compositor_payloads(self):
        # A dict monitor is unhashable, and none of these shapes may raise: the
        # bar keeps working when Hyprland reports something unexpected.
        result = workspace_catalog.catalog(
            self.monitors + ["not a monitor", {"description": "Nameless"}],
            [
                {"id": 8, "monitor": {"name": "eDP-1"}},
                {"id": "9", "monitor": "eDP-1"},
                {"id": 10},
                "not a workspace",
                {"id": -3, "monitor": "eDP-1"},
            ],
            [
                "not a rule",
                {"workspaceString": "11", "enabled": True, "monitor": None},
                {"workspaceString": "12" * 40, "enabled": True, "monitor": "eDP-1"},
                {"workspaceString": "2147483648", "enabled": True, "monitor": "eDP-1"},
                {"workspaceString": "3000000000", "enabled": True, "monitor": "eDP-1"},
            ],
        )
        self.assertEqual(result["workspaces"], {"eDP-1": [], "DP-2": []})

    def test_exact_workspace_id_bounds(self):
        self.assertEqual(workspace_catalog.exact_workspace_id("2147483647"), 2147483647)
        for value in ("2147483648", "01", "-4", "7 ", "", None, "1e3", "9" * 11):
            self.assertIsNone(workspace_catalog.exact_workspace_id(value), msg=repr(value))

    def test_query_refuses_anything_but_the_read_only_surface(self):
        for name in ("keyword", "setprop", "j/monitors", "dispatch", ""):
            with mock.patch("workspace_catalog.subprocess.run") as run:
                with self.assertRaises(ValueError):
                    workspace_catalog.query(name)
            run.assert_not_called()

    def test_query_decodes_and_validates_json(self):
        with mock.patch("workspace_catalog.subprocess.run") as run:
            run.return_value.stdout = '[{"name": "eDP-1"}]'
            self.assertEqual(workspace_catalog.query("monitors"), [{"name": "eDP-1"}])
            called = run.call_args
            self.assertEqual(called.args[0], ["hyprctl", "-j", "monitors"])
            self.assertFalse(called.kwargs.get("shell", False))
            self.assertEqual(called.kwargs["timeout"], workspace_catalog.QUERY_TIMEOUT_SECONDS)
            run.return_value.stdout = '{"not": "a list"}'
            with self.assertRaises(ValueError):
                workspace_catalog.query("workspaces")

    def test_missing_rules_query_still_reports_live_workspaces(self):
        with mock.patch("workspace_catalog.query") as query:
            query.side_effect = lambda name: [] if name == "workspacerules" else [{"name": "eDP-1"}]
            self.assertEqual(workspace_catalog.optional_query("workspacerules"), [])
            query.side_effect = FileNotFoundError("hyprctl")
            self.assertEqual(workspace_catalog.optional_query("workspacerules"), [])

    def test_rules_are_fetched_optionally_while_core_queries_are_not(self):
        with mock.patch.object(workspace_catalog, "query") as query, \
                mock.patch.object(workspace_catalog, "optional_query") as optional:
            query.side_effect = lambda name: [{"name": "eDP-1"}] if name == "monitors" else []
            optional.return_value = [{"workspaceString": "3", "enabled": True, "monitor": "eDP-1"}]
            result = workspace_catalog.main()
            self.assertEqual([call.args[0] for call in query.call_args_list], ["monitors", "workspaces"])
            self.assertEqual(optional.call_args.args[0], "workspacerules")
            self.assertEqual(result["workspaces"], {"eDP-1": [3]})


if __name__ == "__main__":
    unittest.main()
