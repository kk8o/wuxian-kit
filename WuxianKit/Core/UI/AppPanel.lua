-- The app card (0.6, package K3): WuxianKit:AppPanel(id, parent, width) draws app `id` in another addon's window, the
-- same card the window's 应用 page shows: its state (no 无限工坊 link, its extension off, its check(), running until,
-- the agent present or gone, last heard from, what it said today), the connect button (the copy box with
-- /mcp__wuxian__<prompt>), stop, its controls, and its options (the core's 活跃度 / 免打扰时段 when it has pace). Returns
-- a frame (its height set by its content) with :Refresh(), or nil when there is no such app. See ARCHITECTURE.md
-- section 10.
local addonName, ns = ...
local Kit = ns.Kit

-- (contract stub: K3 replaces it)
function Kit:AppPanel(id, parent, width) return nil end
