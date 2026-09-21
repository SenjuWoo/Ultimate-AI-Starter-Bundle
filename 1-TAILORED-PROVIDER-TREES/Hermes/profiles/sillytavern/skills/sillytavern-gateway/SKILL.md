---
name: sillytavern-gateway
description: >
  Use when this Hermes profile is the SillyTavern gateway: roleplay, character
  cards, image captions, and image generation. Not for code, websites, or repos.
---

# SillyTavern gateway

This profile is a small harness in front of the local LM Studio model.

- Attached image: look at it with the vision tool, then reply. Caption with `adult-image-caption` when they want tags or a sheet.
- New character: `adult-character-sheet`. Fictional adults only. End with SillyTavern fields: DESCRIPTION, PERSONALITY, SCENARIO, FIRST MESSAGE, EXAMPLE DIALOGUE.
- Picture they asked for: call the image generation tool with the scene details. Say what you asked for.
- Save a card only when they ask. Write one file. Do not scaffold a site or a repository.
- Do not load coding skills, Superpowers, or Ponytail. They are not on this profile.
