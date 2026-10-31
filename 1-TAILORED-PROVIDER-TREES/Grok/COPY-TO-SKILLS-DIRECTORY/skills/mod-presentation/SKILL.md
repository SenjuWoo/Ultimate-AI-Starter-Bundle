---
name: mod-presentation
description: Use when preparing a public mod page, GitHub repository or Nexus/ModDB release so it shows real images, a clear gallery and honest visual proof.
metadata:
  version: 1.0.0
---

# Mod presentation

A public mod page is judged before it is read. Text alone is not a presentation,
and a wall of feature bullets with no image is a release defect. Show the thing
the mod changes: the character, the armor, the environment, the animation, the
menu, the fight.

This skill owns the page and the images. `public-copy-durability` owns claims
that must survive a release; `visual-verification` owns checking rendered pixels;
`impeccable` owns frontend craft. Use `mod-workspace-organization` to keep the
captures and release files out of the package root.

## The visual contract

Every public release needs:

| Asset | Spec | Why |
|---|---|---|
| Cover / hero | 16:9, 1920x1080 or 1280x720, <= 6 MB | the card and the first impression |
| Gallery | at least 3 stills, 1920x1080, <= 10 MB each | proof from more than one angle |
| README images | at least 3 local images with alt text | GitHub readers never see the Nexus gallery |
| Kind-specific shot | see below | proves the actual feature |
| Motion clip | GIF/WebM/MP4, 10-30 s, <= 30 MB | required for animation and combat; recommended for tools |

Kind-specific proof:

- **Character / follower / race** — a face or portrait close-up, plus a
  full-body or outfit shot. A landscape with a tiny figure does not show a face.
- **Armor / weapon / clothing** — front, back and a detail shot; state whether
  the character is vanilla or modded.
- **Environment / weather / lighting** — a wide establishing shot and a detail
  shot; same location before/after when the mod changes an existing place.
- **Animation / combat** — a short motion clip; a still frame is not proof of
  animation.
- **Tool / framework / UI** — installer detection page and the in-game menu or
  configuration screen; show what the user actually sees.

## Capture real pixels

- Use the final archive, the final load order and the final settings. An image
  from an older version is a false claim.
- Hide the HUD, console, debug overlays, notifications, desktop and personal
  paths. No cursor, no second monitor, no chat window.
- Shoot at 1920x1080 or higher. Keep the subject out of the crop-safe edges;
  Nexus cards and GitHub social previews crop differently.
- Use consistent weather, time of day and lighting across a comparison. For
  before/after, stand in the same spot and use the same camera.
- Credit visible third-party assets (armor, follower, weather, ENB, ReShade) in
  the caption when their licence asks. Disclose ENB/ReShade and any composite
  title overlay.
- Never present generated art as an in-game result. If you add an AI-made
  promotional image, label it and keep the platform's AI-media tag.
- A screenshot is evidence, not decoration: if the feature is a rout, show the
  rout; if it is a face, show the face.

## Page order

Use this order on GitHub and adapt it to Nexus BBCode:

1. **Title and one-line hook** — what changes, for whom, in one sentence.
2. **Hero image** — the best real shot, 16:9.
3. **Badges** — version, game, requirements, licence (only true ones).
4. **What it does** — three to six concrete player-visible changes.
5. **Gallery** — 3-6 images in a deliberate order; caption what each proves.
6. **Features** — the details that did not fit the hook.
7. **Requirements** — game build, frameworks, dependencies, load order.
8. **Installation** — installer steps, FOMOD choices, upgrade/uninstall.
9. **Compatibility** — known conflicts, patches, what is untouched.
10. **Credits and permissions** — authors, assets, tools, reuse terms.
11. **Changelog and support** — version, date, known issues, log location.

Keep the first screen readable at card size. A title baked into the hero image
goes stale; put the title in text and keep the image clean unless the overlay is
part of the design and disclosed.

## GitHub and Nexus specifics

**GitHub**

- Put images under `docs/presentation/` and reference them with relative paths
  so the README works in a clone and on the web.
- Set a social preview image (1280x640) in the repository settings; the README
  hero is not the social card.
- Use a release body with the same hero and gallery links, not a bare asset
  list.
- Alt text is mandatory: `![Bandits routing after their chief falls](...)`.

**Nexus Mods**

- Upload the cover as the main image, then gallery images in page order.
- Use BBCode for the description: `[img]`, `[b]`, `[list]`, `[size]`,
  `[center]`, `[url]`, `[spoiler]`. Keep image URLs absolute.
- Put the version and date in text, not baked into the image.
- Set the media permissions and credits before publishing, not after.

Templates live in this skill's `templates/`: `MOD-README.md`,
`NEXUS-BBCODE.txt` and `PRESENTATION-PLAN.md`.

## Check before publishing

```text
python TOOLS/presentation_check.py <project> --kind character
python TOOLS/presentation_check.py <project> --kind armor
python TOOLS/presentation_check.py <project> --kind animation
```

It fails when the cover is missing, the gallery has fewer than three stills,
the README has fewer than three local images, alt text is empty, a path does not
resolve, an image is oversized, or the kind-specific shot is missing. A passing
check is necessary, not sufficient: look at the images yourself with
`visual-verification`.

## Done means

- the hero and at least three gallery images are real, current and captioned;
- the README renders with images and alt text on GitHub;
- the kind-specific proof exists (face, angles, wide/detail, motion, menu);
- third-party assets and overlays are credited or disclosed;
- `presentation_check.py` passes and the mod ship gate records
  `PRESENTATION: PASS`;
- no image claims a feature that was not seen in the final build.
