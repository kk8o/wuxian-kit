# Tune

Changes the player's game setup: settings (CVars), key bindings, macros, Edit Mode layouts, talent loadouts, equipment
sets, bag sorting, addons on or off, and profiles.

- Look before you change: `wk_tune_cvar_find`, `wk_tune_binding_find`, `wk_tune_macro_list`, `wk_tune_layout_list`,
  `wk_tune_talent_list`, `wk_tune_gear_list`, `wk_tune_addon_list`. Each `*_get` reads one value.
- Every `*_set`, `wk_tune_gear_use`, `wk_tune_gear_save`, `wk_tune_layout_import` and `wk_tune_bags_sort` is a
  proposal the player confirms. A setting's preview shows old → new. All of them can be undone except
  `wk_tune_bags_sort`; a deleted macro comes back to the macro list, but not to the action bars.
- For several changes at once use `wk_propose`, one step per change: one click runs them all, one undo takes them all
  back.
- Turning an addon on or off takes effect after a reload; the proposal says so.
- Macros, layouts, talent loadouts and new equipment sets take a moment to apply. The proposal waits for the game
  (talent loadouts up to 10 s, the others 5 s) and fails if the change does not stay. A loadout name two loadouts
  share is refused: ask the player to rename one.
- Profiles: `wk_tune_profile_capture` keeps the current values of the settings, keys, macros and layout you name;
  `wk_tune_profile_apply` turns a profile into one proposal; `wk_tune_profile_export` and `wk_tune_profile_import`
  share it as a `WK1:` string. An imported profile always waits for the player's click.
- Only what an addon may change can be changed. Protected settings and actions are out of reach.
