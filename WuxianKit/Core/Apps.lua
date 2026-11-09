-- Apps (应用, 0.6): an AI app connects to the game without writing an extension. An app is a feed made from a
-- declaration: what it hears (chat channels, game events, bus topics, its addon's own pushes), whether and how its
-- items are gathered into wakes (a digest; with pace, the player's activity and quiet hours run it), which commands the
-- player can give it in the game, how long it may go unheard from before it counts as gone (lease), and options the
-- player sets for it. Package K2 fills this in; K3 draws it (UI/AppPanel.lua, the window's 应用 page, /wk <app> ...).
-- The contract is ARCHITECTURE.md section 10; in short:
--
--   WuxianKit:App(id, decl) -> app       an addon declares an app (functions allowed: check, urgent, enrich); with
--                                        no decl, the app declared before (or nil)
--   app:Get(name)                        one of its options (as ext:Get)
--   app:Running()                        its run while it runs ({ ends, started, ... }), else nil
--   app:Push(data) -> boolean            an item of its own ({ source = "addon", data }) while it runs
--   WuxianKit:AppControl(id, cmd) -> boolean   the player's command (one of the app's controls; "stop" stops it too)
--   WuxianKit:AppSay(id, text) -> boolean      the player's words to the app (decl.say)
--   WuxianKit:AppPanel(id, parent, width)      (UI/AppPanel.lua, K3) the app's card in another addon's window
--
-- Capabilities (the core's extension "kit"): kit.app.open { app, ...decl, minutes }, kit.app.status { app } (also the
-- heartbeat), kit.app.stop { app }, kit.app.recent { app, since, limit }, kit.apps. Events: app.<id> (the app's
-- wakes: { app, reason, items, skipped, pace?, quiet? }), kit.app ({ app, on, why?, ends? } when one starts or stops).
--
-- For the window (K3), from K2:
--   ns.AppList()                  the apps as kit.apps answers
--   ns.App(id)                    the app object, or nil
--   ns.AppStatus(id)              as kit.app.status answers (without marking it heard from)
--   ns.AppStop(id, why)           stops it ("player" from the window)
--   ns.AppOptionList(id)          its options as kit.options answers ({ [name] = { title, kind, value, ... } })
--   ns.SetAppOption(id, name, v)  the player set one: true and the value kept, or false
--   ns.AppControls(id)            { { cmd, label } } in its declared order
--   ns.ForgetApp(id)              the player removes an app an agent declared
--   ns.CONTROL_WORDS              word (English and Chinese) -> cmd, for /wk <app> <word>
local addonName, ns = ...
local Kit = ns.Kit

-- (contract stubs: K2 replaces them)
function Kit:App(id, decl) return nil end
function Kit:AppControl(id, cmd) return false end
function Kit:AppSay(id, text) return false end
function ns.AppList() return {} end
function ns.App(id) return nil end
function ns.AppStatus(id) return { app = id, on = false } end
function ns.AppStop(id, why) end
function ns.AppOptionList(id) return nil end
function ns.SetAppOption(id, name, value) return false end
function ns.AppControls(id) return {} end
function ns.ForgetApp(id) end
ns.CONTROL_WORDS = {
	mute = "mute", unmute = "unmute", less = "less", more = "more", test = "test", pause = "pause", resume = "resume",
	stop = "stop",
	["静音"] = "mute", ["开声"] = "unmute", ["少说"] = "less", ["多说"] = "more", ["试音"] = "test", ["暂停"] = "pause",
	["继续"] = "resume", ["离开"] = "stop", ["停止"] = "stop",
}
