# Capturing a lesson without polluting the catalog

Referenced from SKILL.md. A skill is a durable procedure, not a diary entry.

A skill is a durable procedure, not a diary entry. Before creating one:

1. Search what already exists: `skill-discovery`, the project's `MEMORY/`
   (`KNOWN-GOOD.md`, `DECISIONS.md`, `FAILED-APPROACHES.md`, `CANDIDATES.md`) and
   the installed skills. If the lesson fits an existing skill, edit that one.
2. Write the lesson where it will be read: a project-specific fact goes to the
   project's `MEMORY/`; a general reusable procedure may become a skill.
3. A new skill needs a repeatable trigger, a procedure that survives the next
   model, and a deterministic check. One success is not a pattern.
4. Run `python scripts/quick_validate.py <skill-dir>` before shipping it, and
   trigger-evaluate only when a Claude-compatible CLI is available (the scripts
   say so and exit 2 rather than inventing results).
5. Record provenance: date, source, affected version, evidence, paths.

Do not create a skill per task. Do not enable a periodic creation nudge. Capture
after a real correction, a novel verified workflow, or an explicit request.
