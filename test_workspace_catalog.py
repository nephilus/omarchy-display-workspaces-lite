import unittest

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


if __name__ == "__main__":
    unittest.main()
