# Guide

Points things out to the player and changes nothing. Use it for what no addon may do (casting, using items, placing
action bar buttons) and to show the player around the UI.

- `wk_guide_highlight`: a glowing frame round a part of the UI (a global frame name, or a path from one), with an
  optional text.
- `wk_guide_note`: a note with a title, under a frame or mid-screen.
- `wk_guide_waypoint`: the map pin at x, y (0–100) on a map, with its arrow.
- `wk_guide_tour`: notes one after another (up to 20 steps); the player clicks Next. Its progress is the event
  `guide.tour`.
- `wk_guide_clear`: puts everything away.
- Keep notes short and name the button or menu the player should use. Your text shows with `|` escaped (no color or
  link codes); line breaks are kept.
