---
name: kit-extension
title: Write an extension
title-zh: 写一个扩展
description: Make an addon a WuxianKit extension, or write a new extension, by WuxianKit's architecture
description-zh: 按扩展框架的架构，把插件接入扩展框架，或新写一个扩展
arguments: addon, goal?
---
Make the addon {{addon}} a WuxianKit extension. What it should offer: {{goal}}

1. Read the architecture first: `ARCHITECTURE.md` in the WuxianKit folder (`Interface\AddOns\WuxianKit`; the workshop's
   `status` tool gives the AddOns folder). Follow it; do not invent fields.
2. Plan with the player before writing code:
   - the extension id (lowercase letters, digits, `_`);
   - each capability and its kind: Read (`See`) for questions about the game, Store (`Keep`) for data kept on this
     computer, Guide (`Point`) for pointing at things, Send (`Say`) for messages, Change (`Do`) for changes. A value the
     game keeps is a `Setting`; events heard for a while are a `Feed`;
   - the categories the player may pre-approve (`ext:Scope`), the events it emits (`ext:Event`), options and commands.
3. The `.toc`:
   - a new addon that only makes sense with WuxianKit: `## Dependencies: WuxianKit`, `## X-WuxianKit-Extension: <id>`,
     `## LoadOnDemand: 1` (WuxianKit loads it at login);
   - an existing addon that must keep working without WuxianKit: `## OptionalDeps: WuxianKit`,
     `## X-WuxianKit-Extension: <id>`, and register only `if WuxianKit then ... end`.
4. The code: `Kit:Words` with Chinese and English, `Kit:Extension(id, { title = L"TITLE", version = ... })`, then the
   declarations. Use `L"KEY"` in declarations and `L.KEY` at run time. Every Change capability takes a `snapshot` so it
   can be undone; a change the client makes a moment later declares `settled`. Whatever a preview, label or format
   shows of the args goes through `WuxianKit:Escape`; a message to a public channel declares `alone`. Player-facing words short and plain;
   `doc` texts and errors in English.
5. Docs: an `AGENT.md` in the addon folder (what the tools are for, how to use them together, cautions), and
   `skills/<name>.md` only for a workflow that needs several tools in order.
6. Check: the workshop's `check` on the addon until it reports no errors.
7. Try it in the game. A new addon appears only after a full restart of the game; later changes to its Lua need a UI
   reload (the workshop's `reload` asks the player). Then:
   - `wk_docs` with the extension's id lists its tools and events (after the restart or reload);
   - call a Read tool and check the answer;
   - for a Change tool, tell the player first, make the proposal, `wk_wait` for the outcome, and offer `wk_kit_undo`
     afterwards.
8. Report what the extension offers and what you checked in the game.

Never change the game behind the player's back: Send and Change go through proposals, and only the player can
pre-approve a category.
