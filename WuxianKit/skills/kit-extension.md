---
name: kit-extension
title: Write an extension
title-zh: 写一个扩展
description: Make an addon a WuxianKit extension, write a new extension, or write an adapter that plugs another addon into one of WuxianKit's interfaces (such as the quest guide), by WuxianKit's architecture
description-zh: 按扩展框架的架构，把插件接入扩展框架、新写一个扩展，或写一个适配器把别的插件接到框架的接口上（如任务指引）
arguments: addon, goal?
---
Make the addon {{addon}} a WuxianKit extension. What it should offer: {{goal}}

1. Read the architecture first: `ARCHITECTURE.md` in the WuxianKit folder (`Interface\AddOns\WuxianKit`; the workshop's
   `status` tool gives the AddOns folder). Follow it; do not invent fields.
2. Plan with the player before writing code:
   - the extension id (lowercase letters, digits, `_`);
   - each capability and its kind: Read (`See`) for questions about the game, Store (`Keep`) for data kept on this
     computer, Guide (`Point`) for pointing at things, Send (`Say`) for messages, Change (`Do`) for changes. A value the
     game keeps is a `Setting`;
   - sources (`ext:Source`, section 5): a stream of items apps can hear, such as what the addon sees happen. A source
     only hands items to its subscribers (`on` / `off`); it has no tools, and apps gather, keep and wake for it;
   - facets (`ext:Facet`, section 5): how things stand now, a small snapshot apps see (`see`) in each wake's
     `state`, such as the addon's current mode or a count for the day. Facts belong in the extension, what to say in
     the app: when an app would have to work a state out from items or parse text, give it a facet instead;
   - the categories the player may pre-approve (`ext:Scope`), the events it emits (`ext:Event`), options and commands.
   An extension is a part: it never declares or names an app. An app that uses it is made with the skill `kit-app`.
   To plug another addon into an interface WuxianKit already has (the quest guide: step 8), write an adapter in an
   extension of your own; neither WuxianKit's core nor its extensions name other addons.
3. The `.toc`:
   - a new addon that only makes sense with WuxianKit: `## Dependencies: WuxianKit`, `## X-WuxianKit-Extension: <id>`,
     `## LoadOnDemand: 1` (WuxianKit loads it at login);
   - an existing addon that must keep working without WuxianKit: `## OptionalDeps: WuxianKit`,
     `## X-WuxianKit-Extension: <id>`, and register only `if WuxianKit then ... end`.
4. The code: `Kit:Words` with Chinese and English, `Kit:Extension(id, { title = L"TITLE", version = ... })`, then the
   declarations. Use `L"KEY"` in declarations and `L.KEY` at run time.
   - `snapshot(self, args)`: every Change capability returns what an undo needs (without it the change cannot be
     undone);
   - `settled(self, args, result)`: only for a change the client makes a moment later; it returns true once the game
     shows the change (the step fails after 5 s);
   - `alone = true`: a message to a public channel; it must be a proposal of its own;
   - whatever a preview, label or format shows of the args goes through `WuxianKit:Escape`;
   - `doc`: one English sentence starting with a verb (Returns... / Proposes to...), naming other capabilities by
     their id; errors in English; player-facing words short and plain;
   - a source: a name no other extension uses (lowercase letters, digits, `_`, at most 24 bytes); `check(what)`
     answers why a `what` is wrong; `on(self, what, fn)` hands `fn` a new table for each item (apps write fields on
     it), plain data only, and returns a token; `off(self, token)` ends it; the source's `doc` says what
     `<name>:<what>` hears. An item's `id` is the kit's: the core numbers every item as it reaches an app. An `id`
     the source gives is handed on as the item's `ref` (unless the source gave a `ref` of its own): give there the
     number an agent should name the thing by, as the source `chat` does with a message's number;
   - a facet: a name no other extension uses (lowercase letters, digits, `_`, at most 24 bytes); `read(self)` returns
     a small table of plain data, or nil when there is nothing now (a snapshot over 600 bytes is cut); `fields` lists
     its fields for the docs; `on(self)` and `off(self)` turn on and off what it needs while an app sees it (a count
     counts only between them); its `doc` says what each field means;
   - registering a source or a facet again from the same extension replaces it (the apps that hear the source
     subscribe to the new one). `ext:Source(name, nil)` and `ext:Facet(name, nil)` take it back: an app that runs
     and needs it waits half a minute for it to come again, then stops (`why` `extension`), and no app that needs
     it can start meanwhile.
5. Docs: an `AGENT.md` in the addon folder (what the tools are for, how to use them together, its sources and their
   items' fields, its facets and their fields, cautions), and
   `skills/<name>.md` only for a workflow that needs several tools in order (its front matter: `name`, `title`,
   `description`, `arguments`; `needs: shell` when the client must run commands in the background, `mcp: <name>
   <URL>` for another MCP server it uses).
6. Check: the workshop's `check` on the addon until it reports no errors. Keep each capability's full id
   (`<extension>.<name>`) and each event's full topic within 64 bytes.
7. Try it in the game. A new addon appears only after a full restart of the game; later changes to its Lua need a UI
   reload (the workshop's `reload` asks the player). Then:
   - `wk_docs` with the extension's id lists its tools, sources, facets and events (after the restart or reload);
   - call a Read tool and check the answer;
   - for a source, hear it with a temporary app: `wk_kit_app_open` with `{"app": "peek", "temp": {"title": "Peek",
     "hear": ["<source>:<what>"]}, "minutes": 15}` (`temp` is the temporary app's whole declaration), make the thing
     happen in the game, read `wk_kit_app_recent` with `{"app": "peek", "since": 0}`, then `wk_kit_app_stop`;
   - for a facet, see it with a temporary app (`"see": ["<facet>"]` in its `temp`) and read its snapshot with
     `wk_kit_app_state` and `{"app": "peek"}` (each wake's `state` holds the same);
   - for a Change tool, tell the player first, make the proposal, `wk_wait` for the outcome, and offer `wk_kit_undo`
     afterwards.
8. An adapter for an interface: the quest guide (section 13). The extension `route` (任务指引) takes the step the
   player is on from a provider; another guide addon becomes one through an adapter in a custom extension, never in
   WuxianKit or in the guide addon. WuxianKit's own `WuxianKit_Guides` (任务指引适配, the RestedXP adapter) is a full
   example:
   - the `.toc`: `## Dependencies: WuxianKit`, `## OptionalDeps: <the guide addon>`;
   - provide it while the extension is on and the guide addon is loaded:
     1. in the extension's `setup` (it is turned on), if the guide addon is loaded:
        `WuxianKit.Route:Provide("<id>", { title, addon, extension, Active, Current, Start, Stop })`;
     2. on `ADDON_LOADED`, while the extension is on: the same call once the guide addon has loaded later. A provider
        is taken up whenever it comes;
     3. turned off: give the adapter `extension = "<your extension's id>"` and do nothing more. While that extension
        is off the quest guide does not read the provider (it stops reading at once), and takes it up again when the
        extension is back on. Without `extension`, take it back yourself in `teardown`:
        `WuxianKit.Route:Provide("<id>", nil)`;
   - the adapter: `Active()` is true while the addon runs a guide; `Current()` returns the step in the standard shape
     (`key`, `goals` of `op` go, kill, collect, accept, turnin, talk, use or other, with `target`, `quest = {id,
     name}`, `objective`, `place = {map, x, y, zone}`; the raw lines in `text`); `Start(changed)` calls `changed()`
     when the step may have changed and `changed("arrive", place)` at its waypoint; `Stop()` lets go. The second
     argument of `changed("arrive", ...)` is the place reached, `{map, x, y, zone}`; leave it out and the quest guide
     takes the place of the step's first `go` goal. An arrival is told once in 5 seconds for a step;
   - give structured goals from the addon's own step data, never by parsing its text; give a quest id and objective
     where the step names a quest (WuxianKit then fills in the progress from the client);
   - try it: `WuxianKit.Route:Providers()` lists it; choose it in the quest guide's option `provider` in /wk,
     see the facet `route` and hear `route:*` with a temporary app, and follow the guide in the game.
9. Report what the extension offers and what you checked in the game.

Never change the game behind the player's back: Send and Change go through proposals, and only the player can
pre-approve a category.
