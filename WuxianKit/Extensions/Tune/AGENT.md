# Tune

Extension id `tune`. Changes the player's game setup: the game's settings (the Settings panel's options and CVars), key
bindings, macros, Edit Mode layouts, talent loadouts, equipment sets, bag sorting, addons on or off, and profiles.

- When the player names an option of the game's Settings panel ("自动拾取", "动作条 2", "状态文字"), find it with
  `wk_tune_setting_find` (the words the player reads, in the client's language, or its category): each result says
  how to change it. `set: "tune.cvar.set"` with `name`: a CVar (`inverted: true`: its box is ticked when the CVar is 0).
  `set: "tune.option.set"` with `name`: an option that is no single CVar (action bars shown, modifier keys, status
  text, self cast, motion sickness, window size, character models ...); its value is one of `choices`, a number in
  `min`..`max`, or one of `sizes`. No `set`: `why` says why it is the player's to change in the panel. The action bars
  shown are the game's own: an addon that replaces them (EllesmereUI, ElvUI, Bartender) shows its bars by its settings.
- Look before you change: `wk_tune_setting_find`, `wk_tune_cvar_find` (CVars by name or English help text),
  `wk_tune_binding_find`, `wk_tune_macro_list`, `wk_tune_layout_list`, `wk_tune_talent_list`, `wk_tune_gear_list`,
  `wk_tune_addon_list`. Each `*_get` reads one value. A few settings are bit fields (`bits: true`): they read as the bits
  that are on, `bits:1,4`, and are set the same way.
- Settings change as the Settings panel changes them: a graphics quality (`graphicsQuality`, `raidGraphicsQuality`)
  also sets shadows, view distance and the rest to that quality; a display setting (`gxMaximize`, `vsync` ...) updates
  the window at once; `gxapi` and `physicsLevel` take effect after the game restarts.
- Every `*_set`, `wk_tune_gear_use`, `wk_tune_gear_save`, `wk_tune_layout_import` and `wk_tune_bags_sort` is a
  proposal: the player clicks 执行 (Run), unless they pre-approved that category (settings, key bindings, macros,
  layouts, talents, gear, bags, addons); then it runs at once. Propose only what the player asked for. A setting's
  preview shows old → new. All of them can be undone except `wk_tune_bags_sort`; a deleted macro comes back to the
  macro list, but not to the action bars.
- For several changes at once use `wk_propose`, one step per change: one click runs them all, one undo takes them all
  back. Example: `{"title": "Auto loot and a map key", "steps": [{"cap": "tune.cvar.set", "args": {"name":
  "autoLootDefault", "value": "1"}}, {"cap": "tune.binding.set", "args": {"key": "CTRL-M", "value": "TOGGLEWORLDMAP"}}]}`.
  `cap` is a capability id with dots; profile steps take only ids.
- Turning an addon on or off, and the character models, take effect after a UI reload: when the proposal is done, ask
  the player, then call the workshop's `reload`.
- Macros, layouts, talent loadouts, new equipment sets, the action bars shown and the window's size take a moment to
  apply. The proposal waits for the game (talent loadouts up to 10 s, the others 5 s) and fails if the change does not
  stay. A loadout name two loadouts share is refused: ask the player to rename one. Setting the loadout in use loads it
  again (its unsaved edits go).
- Profiles: `wk_tune_profile_capture` keeps the current values of the settings, options, keys, macros and layout you
  name; `wk_tune_profile_apply` turns a profile into one proposal; `wk_tune_profile_export` and
  `wk_tune_profile_import` share it as a `WK1:` string. An imported profile always waits for the player's click.
- Only what an addon may change can be changed. Protected settings and actions are out of reach.
