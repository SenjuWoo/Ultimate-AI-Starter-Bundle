# Feel, world and player experience

## Gameplay feel

Feel is latency and feedback, not animation quality.

- **Input latency.** Measure press-to-visible-response. Avoid buffering that delays the
  first frame; input buffering is for combos, not for basic movement.
- **Acceleration and braking.** Movement curves matter more than top speed. Tune with the
  same camera and FOV the player will use.
- **Animation transitions.** Blend windows short enough to feel responsive, long enough to
  hide pops. Check turn-in-place, stop, and sprint-to-idle.
- **Hit feedback.** Hitstop, flash, knockback, sound and camera shake together, scaled by
  hit weight. A heavy hit that sounds light reads as a bug.
- **Recoil and camera.** Recoil must be recoverable and readable; camera shake must not
  destroy aim or cause motion sickness. Provide intensity settings.
- **Sound.** Attacks, impacts, footsteps and UI need distinct frequency space. Silence is
  a tool; audio spam hides the important cue.
- **Timing.** Cooldowns, wind-ups and recovery frames are gameplay. Change them only with a
  playtest, and log the change.
- **Responsiveness checklist.** Test on the lowest supported device at the lowest frame
  rate. Feel that only works at 120 fps is not shipped feel.

## Worldbuilding and immersion

- **Visual hierarchy.** One dominant landmark per sightline; secondary shapes guide the
  route; noise stays at the edges.
- **Landmarks and navigation.** The player should be able to describe where they are
  without the map. Repeat a shape language per faction or biome.
- **Sightlines.** Compose entrances and reveals. Block the destination until the reveal is
  earned, then open the view.
- **Environmental storytelling.** Props, damage, lighting and composition imply events.
  Keep one readable story per space; competing stories read as clutter.
- **Lighting and atmosphere.** Contrast directs attention. Fog and weather set distance
  and mood but must not hide gameplay affordances.
- **Acoustic spaces.** Reverb zones, occlusion and mix per area. Indoor/outdoor transitions
  should be audible before they are visible.
- **Diegetic interfaces.** Prefer in-world signage, HUD-as-device and audio cues where they
  do not reduce clarity.
- **Material coherence.** Consistent texel density, roughness language and colour grading
  per biome. One out-of-scale material breaks the whole space.

## Player experience

- **Onboarding.** Teach one mechanic per beat, in a safe space, with the real controls.
  No tutorial text wall before the first playable moment.
- **Progression.** Visible next goal, meaningful choice, and a reason to return. Check the
  first ten minutes and the first hour separately.
- **Navigation.** Waypoints, audio cues and landmarks that survive a resized HUD and a
  colour-blind filter.
- **Information clarity.** Critical state (health, ammo, objective, danger) readable at a
  glance, at distance, in motion, without colour alone.
- **Controls.** Remappable, with sensible defaults per device. Test keyboard/mouse, gamepad
  and touch where supported.
- **Accessibility.** Subtitles and captions, scalable UI, contrast, hold-vs-toggle options,
  motion reduction, difficulty independent of input speed.
- **Pacing.** Alternate tension and release. A constant peak exhausts; a long trough loses
  the player.
- **Feedback loops.** Every action gets a response within a frame or two: sound, visual,
  haptic or UI. Missing feedback reads as a dropped input.
