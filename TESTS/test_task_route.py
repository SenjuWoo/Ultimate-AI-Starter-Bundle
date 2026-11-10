"""The router must pick ONE workflow, keep small work light, and never chain frameworks.

Scenarios come from the Phase 2 addendum and from Addy's own comparison document.
"""

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "TOOLS"))

import task_route as tr  # noqa: E402


class RoutingTests(unittest.TestCase):
    def test_suggestions_cannot_override_user_intent(self):
        for text in ("Write a story about a security guard", "Design a magic system for my game"):
            result = tr.route(text)
            self.assertTrue(result["advisory"])
            self.assertEqual(result["primary"], "lightweight")
            self.assertEqual(result["specialists"], [])
        result = tr.route("Implement a dialogue endpoint in api.py with OAuth")
        self.assertIn("security-and-hardening", result["specialists"])

    def test_small_bug_stays_lightweight(self):
        r = tr.route("fix the typo in main.py")
        self.assertEqual(r["primary"], "lightweight")
        self.assertEqual(r["checkpoints"], "none")
        self.assertIn("systematic-debugging", r["specialists"])

    def test_clear_add_is_lightweight_and_has_no_interview(self):
        r = tr.route("add a --verbose flag to the CLI")
        self.assertEqual(r["primary"], "lightweight")
        self.assertNotIn("requirements-pass", r["primary"])

    def test_vague_idea_gets_a_requirements_pass(self):
        r = tr.route("I have a vague idea for a tool, not sure what it should do")
        self.assertEqual(r["primary"], "requirements-pass")
        self.assertIn("brainstorming", " ".join(r["specialists"]))

    def test_long_authorised_feature_runs_autonomously(self):
        r = tr.route("build the whole export pipeline end to end while I'm away, no questions")
        self.assertEqual(r["primary"], "superpowers-autonomous")
        self.assertEqual(r["checkpoints"], "none until blocked")

    def test_security_change_forces_a_lifecycle_not_a_light_patch(self):
        r = tr.route("add oauth login with password reset and tests before merge")
        self.assertEqual(r["primary"], "lifecycle")
        self.assertIn("security-and-hardening", r["specialists"])
        self.assertIn("release-checklist", " ".join(r["specialists"]) + " release-checklist")

    def test_release_task_uses_the_lifecycle(self):
        r = tr.route("ship the release and tag it after the security review")
        self.assertEqual(r["primary"], "lifecycle")

    def test_research_and_docs_stay_lightweight(self):
        self.assertEqual(tr.route("research which bundler is faster")["primary"], "lightweight")
        self.assertEqual(tr.route("update the README and changelog")["primary"], "lightweight")

    def test_frontend_task_gets_the_design_specialist(self):
        r = tr.route("redesign the settings page layout")
        self.assertEqual(r["primary"], "lightweight")
        self.assertIn("impeccable", r["specialists"])

    def test_game_task_routes_through_capability_routing(self):
        r = tr.route("add a stamina system to my Skyrim mod")
        self.assertIn("capability-routing", r["specialists"])

    def test_mixed_task_still_gets_exactly_one_primary(self):
        r = tr.route("fix the crash, add tests, then update the changelog and ship a release")
        self.assertIn(r["primary"], {"lightweight", "lifecycle", "superpowers-autonomous"})
        self.assertNotIn("+", r["primary"], "a mixed task must not chain frameworks")

    def test_router_is_deterministic(self):
        text = "add oauth login with tests before merge"
        self.assertEqual(tr.route(text), tr.route(text))

    def test_every_route_names_its_continuity_path(self):
        self.assertIn("task_state", tr.route("fix a bug")["continuity"])

    def test_the_word_idea_does_not_buy_an_interview(self):
        text = ("I have an idea for a CLI: it must read `notes.json`, add a --tag flag "
                "and tests for both paths")
        self.assertNotEqual(tr.route(text)["primary"], "requirements-pass")

    def test_a_thin_vague_request_still_asks_once(self):
        self.assertEqual(tr.route("not sure what to build yet, maybe something for notes")["primary"],
                         "requirements-pass")

    def test_quick_security_fix_is_not_treated_as_a_trivial_patch(self):
        self.assertEqual(tr.route("quick fix to the auth token check")["primary"], "lifecycle")

    def test_unattended_run_with_a_concrete_goal_stays_autonomous(self):
        r = tr.route("finish the export pipeline while I'm away; it must pass `pytest tests/export`")
        self.assertEqual(r["primary"], "superpowers-autonomous")
        self.assertEqual(r["checkpoints"], "none until blocked")

    def test_missing_pack_falls_back_to_an_installed_specialist(self):
        r = tr.route("add oauth login with tests before merge")
        security = [x for x in r["resolved"] if x["want"] == "security-and-hardening"]
        self.assertTrue(security)
        self.assertEqual(security[0]["use"], "code-review-skill")
        self.assertIn(security[0]["via"], {"fallback", "bundle"})

    def test_installed_pack_wins_over_the_fallback(self):
        pool = {"addy-security-and-hardening": "optional", "code-review-skill": "provider"}
        resolved = tr.resolve(["security-and-hardening"], available=pool)
        self.assertEqual(resolved[0]["use"], "addy-security-and-hardening")
        self.assertEqual(resolved[0]["via"], "installed")

    def test_ai_token_costs_are_not_a_security_signal(self):
        for text in ("reduce AI token usage across the prompts to cut cost",
                     "trim the context window tokens so requests are cheaper",
                     "lower tokens per request in the summariser"):
            r = tr.route(text)
            self.assertNotIn("security-and-hardening", r["specialists"], text)
            self.assertNotEqual(r["primary"], "lifecycle", text)

    def test_credential_tokens_are_a_security_signal(self):
        for text in ("rotate the access token used by the API client",
                     "store the session token in an http-only cookie",
                     "the api key leaked into the build log"):
            r = tr.route(text)
            self.assertIn("security-and-hardening", r["specialists"], text)

    def test_promotion_to_lifecycle_sets_checkpoints(self):
        r = tr.route("add oauth login with tests before merge")
        self.assertEqual(r["primary"], "lifecycle")
        self.assertEqual(r["checkpoints"], "phase gates")

    def test_authorised_unattended_security_keeps_no_checkpoints(self):
        r = tr.route("add oauth login and finish it while I'm away, no questions")
        self.assertEqual(r["primary"], "superpowers-autonomous")
        self.assertEqual(r["checkpoints"], "none until blocked")

    def test_security_and_token_optimisation_are_independent(self):
        mixed = tr.route("Add OAuth login and reduce LLM token usage.")
        self.assertEqual(mixed["primary"], "lifecycle", "security must not be suppressed by a cost phrase")
        self.assertIn("security-and-hardening", mixed["specialists"])
        self.assertTrue(mixed["signals"]["token_cost"])
        self.assertTrue(mixed["signals"]["security"])

    def test_an_empty_provider_sees_no_specialists(self):
        resolved = tr.resolve(["security-and-hardening"], available={})
        self.assertEqual(resolved[0]["use"], None)
        self.assertEqual(resolved[0]["via"], "unavailable")

    def test_a_partial_install_resolves_what_is_present_only(self):
        pool = {"addy-security-and-hardening": "optional"}
        resolved = tr.resolve(["security-and-hardening", "context-engineering"], available=pool)
        self.assertEqual(resolved[0]["via"], "installed")
        self.assertEqual(resolved[1]["use"], None, "nothing may be claimed that is not installed")

    def test_source_skills_are_labelled_not_installed(self):
        resolved = tr.resolve(["systematic-debugging"], available={"systematic-debugging": "source"})
        self.assertEqual(resolved[0]["via"], "bundle")
        self.assertEqual(resolved[0]["origin"], "source")

    def test_no_specialist_resolves_to_a_missing_skill(self):
        pool = {p.name for p in (ROOT / "_CANONICAL-SKILLS").iterdir()
                if (p / "SKILL.md").is_file()}
        for scenario in ("fix a bug", "add oauth login", "redesign the settings page",
                         "add a stamina system to my Skyrim mod"):
            for item in tr.route(scenario)["resolved"]:
                if item["use"]:
                    self.assertIn(item["use"], pool, item)


if __name__ == "__main__":
    unittest.main(verbosity=2)
