"""Pick one workflow for a task, deterministically, so the user never chooses a framework.

The bundle now carries three methodologies: its own skills, Superpowers' long-run
pipeline, and optionally Pocock's requirement grilling or Addy's lifecycle commands.
Asking a user to pick one is the wrong interface. This maps an ordinary request to
exactly one primary workflow plus the specialists the task genuinely needs, and it is a
lookup over named signals, not a model call - a cheap model gets the same answer as an
expensive one, and the decision can be tested.

    python TOOLS/task_route.py "add OAuth login with tests before merge"
    python TOOLS/task_route.py --json "..."
"""

import argparse
import json
import re
import sys
from pathlib import Path

# Signals. Order matters only for reporting; rules below decide what wins.
RE_BUG = re.compile(r"\b(fix|bug|crash|traceback|regression|fails?|broken|hotfix|error)\b", re.I)
RE_FEATURE = re.compile(r"\b(add|build|implement|create|feature|support|new)\b", re.I)
RE_RESEARCH = re.compile(r"\b(research|compare|evaluate|investigate|survey|which .* better)\b", re.I)
RE_DOCS = re.compile(r"\b(readme|docs?|documentation|changelog|guide|release notes)\b", re.I)
RE_RELEASE = re.compile(r"\b(release|publish|ship|tag|deploy|version bump)\b", re.I)
RE_DESIGN = re.compile(r"\b(ui|frontend|design|layout|component|css|screenshot|mockup)\b", re.I)
RE_GAME = re.compile(r"\b(mod|skyrim|roblox|unity|unreal|godot|rimworld|game)\b", re.I)
RE_SECURITY = re.compile(r"\b(auth|oauth|login|password|payment|pii|gdpr|owasp|secrets?|privilege|security|vulnerab\w*)\b"
                         r"|\b(api[- ]?key|access[- ]token|bearer|credentials?|session token)\b", re.I)
# "token" alone is ambiguous: LLM token budgets are a cost topic, not a security one.
RE_TOKEN_COST = re.compile(r"\b(token (usage|budget|cost|count|limit|spend)|context (window|tokens)|"
                           r"tokens? per|prompt tokens|reduce tokens|cheaper tokens)\b", re.I)
RE_AUTONOMY = re.compile(r"\b(unattended|overnight|walk away|autonomous|while i'?m (away|out)|no questions)\b", re.I)
RE_VAGUE = re.compile(r"^\s*(make it better|improve (this|it)|clean (this|it) up|somehow|maybe)\b|"
                      r"\b(i think|not sure|something like|vague|idea)\b", re.I)
RE_MULTI = re.compile(r"\b(then|also|after that|plus|and then)\b", re.I)
RE_SMALL = re.compile(r"\b(typo|rename|bump|one[- ]line|small|quick|single file)\b", re.I)
RE_LARGE = re.compile(r"\b(whole|entire|end[- ]to[- ]end|from scratch|architecture|system|refactor)\b", re.I)

# Detail is the counterweight to a vague word: a request that names files, commands,
# acceptance criteria or a number is actionable even if it says "idea" somewhere.
RE_CONCRETE = re.compile(r"`[^`]+`|\b[\w./-]+\.(py|js|ts|tsx|jsx|ps1|md|json|ya?ml|cs|cpp|rs|go|lua|txt)\b"
                         r"|\b(line \d+|function \w+|class \w+|endpoint|command)\b", re.I)
RE_ACCEPT = re.compile(r"\b(must|should|acceptance|so that|tests?|verify|expected|reproduce|steps?)\b", re.I)


def detail_score(text):
    """0 = a wish, 3+ = a work order. Used to decide whether asking is material."""
    score = 0
    if len(text.split()) >= 25:
        score += 1
    if RE_CONCRETE.search(text):
        score += 1
    if RE_ACCEPT.search(text):
        score += 1
    if re.search(r"\d", text):
        score += 1
    return score


def signals(text):
    return {
        "bug": bool(RE_BUG.search(text)),
        "feature": bool(RE_FEATURE.search(text)),
        "research": bool(RE_RESEARCH.search(text)),
        "docs": bool(RE_DOCS.search(text)),
        "release": bool(RE_RELEASE.search(text)),
        "design": bool(RE_DESIGN.search(text)),
        "game": bool(RE_GAME.search(text)),
        "security": bool(RE_SECURITY.search(text)),
        "token_cost": bool(RE_TOKEN_COST.search(text)),
        "autonomy": bool(RE_AUTONOMY.search(text)),
        "vague": bool(RE_VAGUE.search(text)),
        "multi": bool(RE_MULTI.search(text)),
        "small": bool(RE_SMALL.search(text)),
        "large": bool(RE_LARGE.search(text)),
        "detail": detail_score(text),
    }


def route(text, provider=None, home=None):
    """One primary workflow plus the specialists worth invoking, with a reason."""
    text = text or ""
    s = signals(text)
    specialists = []

    # Asking is only justified when the request is vague AND thin. "I have an idea for
    # X, it must do Y, here is the file" is a work order with the word "idea" in it.
    ambiguous = s["vague"] and s["detail"] <= 1

    if ambiguous:
        primary, why = "requirements-pass", "the request does not yet name a concrete outcome"
        specialists += ["brainstorming", "to-spec"]
        checkpoints = "ask once, then proceed"
    elif s["release"] and (s["security"] or s["large"] or s["multi"]):
        primary, why = "lifecycle", "change reaches release, security or several phases"
        specialists += ["release-checklist", "ci-convergence"]
        checkpoints = "phase gates"
    elif s["autonomy"] and (s["feature"] or s["large"] or s["multi"] or s["detail"] >= 2):
        primary, why = "superpowers-autonomous", "long, authorised run with a clear goal"
        specialists += ["writing-plans", "executing-plans", "one-shot-completion"]
        checkpoints = "none until blocked"
    elif s["bug"] and s["small"] and not s["security"]:
        primary, why = "lightweight", "one concrete failure with a known target"
        specialists += ["systematic-debugging"]
        checkpoints = "none"
    elif s["bug"] and not s["large"] and not s["multi"]:
        primary, why = "lightweight", "one concrete failure with a known target"
        specialists += ["systematic-debugging"]
        checkpoints = "none"
    elif s["research"]:
        primary, why = "lightweight", "an answer is the deliverable, not code"
        specialists += ["research-verification", "grounded-citations"]
        checkpoints = "none"
    elif s["docs"] and not s["feature"]:
        primary, why = "lightweight", "files only, no behaviour change"
        specialists += ["public-copy-durability"] if s["release"] else []
        checkpoints = "none"
    elif s["feature"] and (s["large"] or s["multi"]):
        primary = "superpowers-autonomous" if s["autonomy"] else "lifecycle"
        why = ("long, authorised run with a clear goal" if primary == "superpowers-autonomous"
               else "several phases or a large surface")
        specialists += ["writing-plans", "executing-plans", "requesting-code-review"]
        checkpoints = "plan review only"
    elif s["design"] and not s["feature"]:
        primary, why = "lightweight", "visual change with a concrete target"
        specialists += ["impeccable", "visual-verification"]
        checkpoints = "none"
    elif s["feature"]:
        primary, why = "lightweight", "single, well-scoped addition"
        specialists += ["test-driven-development", "check-work"]
        checkpoints = "none"
    else:
        primary, why = "lightweight", "no signal that any heavier workflow would pay for itself"
        checkpoints = "none"

    if s["security"]:
        specialists.append("security-and-hardening")
        if primary == "lightweight":
            primary, why = "lifecycle", "touches authentication, money or personal data"
    if s["game"]:
        specialists.append("capability-routing")
    if s["design"] and "impeccable" not in specialists:
        specialists.append("impeccable")

    # One primary workflow only: a mixed task still runs one pipeline and borrows
    # specialists, rather than chaining three methodologies.
    return {"primary": primary, "specialists": specialists, "checkpoints": checkpoints,
            "reason": why, "signals": {k: v for k, v in s.items() if v},
            "resolved": resolve(specialists, available_skills(provider, home)),
            "continuity": "TOOLS/task_state.py next|resume keeps progress across sessions"}


# When an optional specialist is not installed, the task still has to run: every intent
# names an installed fallback so nobody has to shop for a pack mid-task.
FALLBACKS = {
    "security-and-hardening": ["code-review-skill", "requesting-code-review"],
    "performance-optimization": ["code-review-skill"],
    "observability-and-instrumentation": ["observability-first"],
    "api-and-interface-design": ["codebase-design", "writing-plans"],
    "context-engineering": ["token-efficiency"],
    "deprecation-and-migration": ["release-checklist"],
    "domain-modeling": ["brainstorming"],
    "codebase-design": ["writing-plans"],
    "to-spec": ["writing-plans"],
    "triage": ["systematic-debugging"],
    "writing-for-agents": ["skill-creator"],
    "impeccable": ["popular-web-designs"],
    "visual-verification": ["dogfood"],
    "one-shot-completion": ["executing-plans"],
    "check-work": ["check-work"],
}

BUNDLE_SKILLS = Path(__file__).resolve().parents[1] / "_CANONICAL-SKILLS"


def available_skills(provider=None, home=None):
    """What this provider can actually see: a dict of name -> origin.

    A skill sitting in the bundle's source tree is not installed anywhere. Only when no
    provider is given (CLI use inside the repo) do we report source skills, and they are
    labelled `source` so nothing claims they are discoverable.
    """
    found = {}
    if provider:
        try:
            import recommended_skills as rs
            root = rs.provider_dirs(home)[provider]
            if root.is_dir():
                found.update({p.name: "provider" for p in root.iterdir() if (p / "SKILL.md").is_file()})
            for pack in ("addy", "pocock"):
                receipt = rs.receipt_path(pack, provider, home)
                if receipt.exists():
                    data = rs._load(receipt)
                    for path in data.get("owned", []):
                        item = Path(path)
                        if item.is_dir() and (item / "SKILL.md").is_file() and item.parent == root:
                            found[item.name] = "optional"
        except Exception:
            pass  # an unreadable receipt must not break routing
        return found
    if BUNDLE_SKILLS.is_dir():
        found = {p.name: "source" for p in BUNDLE_SKILLS.iterdir() if (p / "SKILL.md").is_file()}
    return found


def resolve(specialists, available=None):
    """Map each specialist intent to a skill that exists in the place we looked."""
    pool = available if isinstance(available, dict) else {n: "source" for n in (available or ())}
    resolved = []
    for want in specialists:
        candidates = ["addy-" + want, "pocock-" + want, want] + FALLBACKS.get(want, [])
        for candidate in candidates:
            if candidate in pool:
                origin = pool[candidate]
                if candidate == want:
                    via = "bundle" if origin == "source" else "installed"
                elif origin == "source":
                    via = "bundle"
                elif candidate.endswith("-" + want) and not candidate.startswith(tuple(FALLBACKS.get(want, ["\0"]))):
                    via = "installed"
                else:
                    via = "fallback"
                resolved.append({"want": want, "use": candidate, "via": via, "origin": origin})
                break
        else:
            resolved.append({"want": want, "use": None, "via": "unavailable", "origin": None})
    return resolved


def main(argv=None):
    ap = argparse.ArgumentParser(description="One workflow for a task, chosen deterministically")
    ap.add_argument("text", nargs="+", help="what the user asked for")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--provider")
    ap.add_argument("--home")
    args = ap.parse_args(argv)
    result = route(" ".join(args.text), args.provider, args.home)
    if args.json:
        print(json.dumps(result, indent=1))
    else:
        print("primary: %s (%s)" % (result["primary"], result["reason"]))
        print("specialists: %s" % (", ".join(result["specialists"]) or "-"))
        for item in result["resolved"]:
            if item["use"]:
                print("  %-32s -> %s (%s)" % (item["want"], item["use"], item["via"]))
        print("checkpoints: %s" % result["checkpoints"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
