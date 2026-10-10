---
name: tune-setup
title: Tune a setup
title-zh: 调一套设置
description: Change a set of settings, key bindings, macros, the layout or the talent loadout as the player asks, in one proposal they can undo as one
description-zh: 按玩家的要求调整一组设置、按键、宏、界面布局或天赋配置，合成一个可以整体撤销的提案
arguments: goal
---
What the player wants: {{goal}}

1. Make sure you know exactly what to change. Ask when it is unclear (which keys, which settings, for which character).
2. Look before you change, and use only names the game gives you:
   - settings: `wk_tune_cvar_find` (by words in the name or help), `wk_tune_cvar_get`;
   - keys: `wk_tune_binding_find`, `wk_tune_binding_get`;
   - macros: `wk_tune_macro_list`; layouts: `wk_tune_layout_list`, `wk_tune_layout_get`;
   - talent loadouts: `wk_tune_talent_list`; equipment sets: `wk_tune_gear_list`; addons: `wk_tune_addon_list`.
3. For a large change, offer to keep the current state first: `wk_tune_profile_capture` with a name such as
   `before-<goal>` and the settings, keys, macros, layout or talent loadout you will change. The player can apply it
   later to go back, even after other changes.
4. Put every change in one proposal: `wk_propose`, one step per change:
   - `tune.cvar.set` {name, value}, `tune.binding.set` {key, value} (no value clears the key),
     `tune.macro.set` {name, value}, `tune.layout.set` {value}, `tune.talent.set` {value},
     `tune.gear.use` {name}, `tune.addon.set` {name, value};
   - a short `title` that says what it is for. Example: `{"title": "Auto loot and a map key", "steps": [{"cap":
     "tune.cvar.set", "args": {"name": "autoLootDefault", "value": "1"}}, {"cap": "tune.binding.set", "args": {"key":
     "CTRL-M", "value": "TOGGLEWORLDMAP"}}]}`;
   - `cap` is a capability id with dots; the options here are `title`, `ttl` and `after`, without the underscore.
5. Tell the player what will change and that they confirm it in the game. If the answer's `state` is already `done`,
   the categories were pre-approved and it ran. Otherwise call `wk_wait` with `{"proposal": <id>}`.
6. After it:
   - `timeout: true`: the player has not decided yet; call `wk_wait` again or ask them;
   - done: say what changed. It can be undone as one from the /wk window (执行记录), or with `wk_kit_undo` when the
     player asks;
   - failed: say why; the steps before the failing one were rolled back;
   - declined or expired: stop, and ask what to change instead.
7. Turning addons on or off takes effect after a UI reload: ask the player, then use the workshop's `reload`.
8. To share the setup: `wk_tune_profile_save` with the same steps (or `wk_tune_profile_capture` after it ran), then
   `wk_tune_profile_export` gives a `WK1:` string; `wk_tune_profile_import` takes one.

Only change what the goal needs. In combat, the changes wait until combat ends. Placing spells on action bars and other
protected actions are out of reach: show the player where to click with the Guide extension (skill `guide-tour`).
