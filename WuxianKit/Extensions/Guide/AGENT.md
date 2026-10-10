# Guide

Extension id `guide`. Shows the player where to look or what to click. Every tool acts at once; none is a proposal.
Use it for what no addon may do (casting, using items, placing action bar buttons) and to show the player around the UI.

- A frame is named by its global name (`CharacterMicroButton`, `PlayerFrame`, `Minimap`) or a path from one
  (`PlayerFrame.healthbar`). Do not guess names: an unknown one fails with "no frame ...".
- `wk_guide_highlight` with `{"frame": "CharacterMicroButton", "text": "Open your character window", "seconds": 30}`.
  `shown: false` means the frame exists but is hidden: ask the player to open its window first.
- `wk_guide_note` with `{"title": "...", "text": "...", "frame": "..."}`: a note under a frame, or mid-screen without one.
- `wk_guide_waypoint` with `{"x": 45.2, "y": 61.8}`: the map pin with its arrow (x, y 0–100 as `wk_sense_position`
  gives them; `map`: a map id, default the player's). It replaces a pin the player set.
- `wk_guide_tour` with `{"title": "...", "steps": [{"text": "...", "frame": "..."}]}`: 1–20 notes; the player clicks
  Next. Follow it with `events` (topic `guide.tour`: state shown, done or closed).
- `wk_guide_clear`: removes everything the guide shows, and its own map pin.
- Keep texts short and name the button or menu. Texts show as plain text (`|` codes do not work); line breaks are kept.
