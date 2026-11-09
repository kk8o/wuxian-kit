# 无限工坊 · 扩展框架（WuxianKit）架构说明

WuxianKit 是插件的 Agent 接入框架。扩展只写声明：能做什么、发出哪些事件、给 Agent 的说明。其余由框架负责：校验参数；把更改游戏的操作变成提案，在游戏里预览，玩家执行后生效，可以撤销；管理存储、游戏事件、定时器和 `/wk` 窗口里的一页；生成能力清单交给 Agent。

本文写给扩展作者。给 Agent 的用法说明见同目录的 `AGENT.md`。

## 1. 分层

| 层 | 负责 | 不负责 |
|---|---|---|
| 扩展（内置或别的插件） | 声明能力、事件、选项、命令；附带 `AGENT.md` 与 `skills/` | 确认、撤销、权限、传输 |
| 核心 | 校验、提案、免确认、撤销、存储、事件、定时器、窗口；生成清单 | 具体玩法 |
| 开发组件 WoWBridge（可选） | 把能力和事件交给无限工坊：不带代码的调用与事件 | 业务逻辑 |
| 无限工坊 App | 按固定规则把清单翻译成 MCP；从插件文件夹读说明与技能 | 针对某个扩展的代码 |
| Agent | 使用标准 MCP 工具 | 直接改游戏 |

扩展框架是可选插件：无限工坊不会自动安装它，它也不依赖无限工坊。没有无限工坊时照常运行，只是没有 Agent；别的插件也可以直接调用它，不经过 Agent。

## 2. 目录

```
WuxianKit/
  WuxianKit.toc  Bindings.xml  Media/
  AGENT.md                 给 Agent：能力的类别、提案、规则、事件
  ARCHITECTURE.md          本文
  Core/
    Locale.lua             核心的中英文字
    Kit.lua                公共表 WuxianKit：文字与语言、总线、载入 / 登录 / 退出钩子
    Schema.lua             参数声明与校验
    Extension.lua          扩展对象与生命周期、存储、游戏事件、定时器、选项、命令
    Kinds.lua              五类能力、Setting 与 Feed 两种模式；Call / Propose；清单与修订号
    Proposals.lua          提案管线：预览、执行、战斗排队、等待生效、快照撤销、执行前取消、免确认
    Comm.lua               玩家客户端之间的插件消息（WuxianKit.Comm）
    Bridge.lua             经 WoWBridge 交给 Agent
    UI/                    提案窗口、扩展框架窗口（/wk）、应用卡片（AppPanel）、样式（WuxianKit.Skin）
    Builtins.lua           核心自己的扩展 kit：扩展开关、提案查询、撤销、清单、称呼
    Apps.lua               应用（第 10 节）：kit.app.*、WuxianKit:App
  Extensions/<名称>/        内置扩展：<名称>.lua 等代码，AGENT.md，skills/
  Extensions/Chat/GuildApp.lua         框架自己的应用 guild（公会聊天，第 10 节）
  Extensions/Chat/skills/guild-chat.md 它的技能
```

## 3. 扩展

### 定义

```lua
local Kit = WuxianKit
local L = Kit:Words {
  zhCN = { TITLE = "示例", VOLUME = "音量", SCOPE = "示例设置" },
  enUS = { TITLE = "Demo", VOLUME = "Volume", SCOPE = "Demo settings" },
}
local demo = Kit:Extension("demo", { title = L"TITLE", version = "1.0.0", defaults = { volume = 3 } })
demo:Scope("settings", L"SCOPE")
```

- `id`：小写字母、数字和下划线。能力的 id 是 `<扩展>.<名称>`，事件主题是 `<扩展>.<主题>`。
- `info` 的字段：`title`、`version`、`notes`、`addon`（所属插件的文件夹名，别的插件的扩展写它）、`defaults`（存储的默认值）、`setup(self)`（启用时）、`teardown(self)`（停用时）、`docs`（`AGENT.md` 与 `skills/` 所在的子文件夹，相对于插件文件夹；不写就是插件文件夹本身）、`prompt`（`skills/` 里一个技能的 `name`，见下）。
- 多个文件组成的扩展，其他文件用 `Kit:Extension("demo")`（不带 `info`）取回同一个对象。

### 生命周期

- 内置扩展在扩展框架的存档载入后启用；别的插件的扩展在它的文件执行完后启用。
- 玩家在 `/wk` 里停用后立即生效：游戏事件不再交给它，定时器和 Feed 停止，能力拒绝调用，它还没执行的提案作废（执行到一半的撤回已执行的步骤）。它经提案做过的更改保留，可以在执行记录里撤销；它在界面上创建的东西要重载界面后才清除。
- 停用记在 `WuxianKitDB.off`，重载和重新登录后仍然停用。

### 扩展对象的方法

| 方法 | 作用 |
|---|---|
| `ext.db` | 自己的存储（`WuxianKitDB.ext[id]`），已填入 `defaults` |
| `ext:On(event, fn)` | 游戏事件，启用期间才交给它 |
| `ext:Every(seconds, fn)` | 定时器，启用期间运行 |
| `ext:Emit(topic, data)` | 总线事件 `<id>.<topic>`，同时交给 Agent |
| `ext:Event(topic, { doc, data })` | 声明会发出的事件，写进清单（`data`：字段 → 类型） |
| `ext:Scope(name, title)` 或 `ext:Scope(name, { title, budget })` | 免确认的类别，玩家在窗口里勾选。名称可以带点分层（`guild.reply`），授权上一层也覆盖下一层；`budget = { per = 秒, most = 次数 }` 是建议的限额，玩家勾选时预先选上（第 6 节） |
| `ext:Option(name, { title, kind, default, hint, changed, ... })` | 玩家在窗口里设置的选项，见下；只能由玩家修改，Agent 经 `kit.options` 只读 |
| `ext:Get(name)` | 读选项的值（列表返回副本） |
| `ext:Command(word, fn, help)` | 斜杠命令 `/wk <word>` |
| `ext:Status(fn)`、`ext:Button(label, fn)` | 窗口里这一页的一行状态和几个按钮 |
| `ext:Tell(text)` | 以扩展名义在聊天框给玩家一行提示 |
| `ext:Char()` | 本角色的存储（`ext.db.chars[角色 GUID]`），第一次用时建好 |

选项的 `kind`：

| kind | 控件 | 值 | 另外的字段 |
|---|---|---|---|
| `boolean`（默认） | 勾选框 | `true` / `false` | |
| `text` | 文本框 | 字符串 | |
| `number` | 数字框 | 数字，夹在 `min`–`max` 之间、按 `step` 取整 | `min`、`max`、`step`（默认 1）、`unit`（单位文字，`L"KEY"` 或字符串） |
| `choice` | 一排按钮，选一个 | 某个 `value` | `choices = { { value, label }, ... }`，`label` 可以是 `L"KEY"`；存的值不在其中时按 `default` |
| `list` | 文本框，用逗号（`,`、`，`、`、`）分开 | 字符串的表：去掉首尾空白、去空、去重，最多 20 项，每项最多 32 字节 | |

- 玩家改了选项，核心调 `changed(self, value)`，并发出总线事件 `kit.option`（`{ extension, name, value }`）。
- `WuxianKit:OptionsPanel(id, parent, width)`：在插件自己的窗口里画扩展 `id` 的全部选项，样式与 `/wk` 一致，两处改的是同一份；返回一个框体（高度已按内容设好），`:Refresh()` 重画。扩展不存在或没有选项时返回 nil。
- `kit.options { extension }`（读取）：`{ [name] = { title, kind, value, default, choices?, min?, max?, unit? } }`，标题按当前语言。Agent 用它了解玩家的设置，不能修改。

复制框与接入：

- `WuxianKit:Copy(text, { title, hint, how, done })`：一个只读的复制框，文字已选中、输入焦点在框里，改了内容就恢复原文并重新选中；最下一行是 `how`（不写就是「Ctrl+C 复制」），玩家按 Ctrl+C 后显示「已复制」并在片刻后收起，调 `done()`；Esc、Enter、关闭按钮关闭。无限的客户端不允许插件写剪贴板（`CopyToClipboard` 受限），要复制给玩家的文字都用它。同一时间只有一个复制框，新的替换旧的。
- `info.prompt`：只记下扩展的主技能，扩展页不再有按钮。要让玩家交给 AI 的，声明成应用（第 10 节）：应用卡片上的「交给 AI」复制启动语，Claude Code 里一样能用；斜杠命令 `/mcp__wuxian__<prompt>` 由无限工坊 App 提示。
- `WuxianKit:Requires(version)`：扩展框架的版本不低于 `version`（`"0.5.0"`）时为真。可选依赖扩展框架的插件用它判断新接口在不在。

声明会发出的事件：

```lua
demo:Event("changed", { doc = "the volume changed", data = { volume = "number" } })
```

### 文字与语言

- 给玩家看的文字写中英两份：`Kit:Words { zhCN = {...}, enUS = {...} }`。玩家可以在 `/wk` → 核心里切换语言（或 `/wk lang`），切换立即生效。
- 运行时用 `L.KEY`；声明里的标题、范围、选项、按钮写 `L"KEY"`。后者在显示时才取值，所以会跟着语言切换。
- 给 Agent 的 `doc`、错误信息、`AGENT.md` 用英文。
- 用语要简洁、规范，像游戏自己的界面。

## 4. 五类能力

| 类别 | 声明 | 行为 |
|---|---|---|
| 读取 | `ext:See(name, spec)` | `run(self, args, opts)` 立即执行；不读机密值 |
| 存储 | `ext:Keep(name, spec)` | `run` 立即执行，数据存在本机 |
| 指引 | `ext:Point(name, spec)` | `run` 立即执行，只指给玩家看，不改游戏 |
| 发送 | `ext:Say(name, spec)` | 提案；`apply(self, args)`；聊天锁定（首领战、史诗钥石、PvP）时等待 |
| 更改 | `ext:Do(name, spec)` | 提案；`apply(self, args)`；战斗中排到脱战；有 `snapshot` 才能撤销 |

所有类别的 `spec`：

- `title`：玩家看到的名称（名词，如「客户端设置」）。
- `doc`：给 Agent 的说明（英文）。
- `args`：参数声明 `{ 名称 = 类型 }`。类型是 `"string"`、`"number"`、`"boolean"`、`"table"`、`"any"`，可以用 `|` 组合（`"string|number"`），也可以是可选的几个值（`"guild|party"`）；末尾加 `?` 表示可选。未声明的参数会被拒绝。
- `proposes = true`（读取、存储、指引类）：立即执行，答一个由别的步骤组成的提案，例如 `tune.profile.apply`。清单里注明，App 给它加上提案选项 `_title`、`_ttl`、`_after`，不把它当成只指不改的指引。

预览、标签、格式化里凡是来自参数的内容，都要经 `WuxianKit:Escape(text)` 转义（`|` 变成 `||`，换行变成空格），外来文字里的颜色、图标、链接代码就不会生效。Setting 的默认显示已经转义；自己写 `preview`、`label`、`format` 时自己转义。

Agent 交来、给玩家看的文字（`chat.send`、`guide.note`、`guide.tour`、`guide.highlight`）可以写链接记号 `{kind:id:name}`：先转义，再换成客户端给的链接，玩家可以悬停看提示（第 12 节）。

发送和更改类还可以有：

| 字段 | 作用 |
|---|---|
| `scope` | 所属的免确认类别（`ext:Scope` 的名称，或 `function(self, args)`）；不写就按能力本身 |
| `check(self, args)` | 返回不能执行的原因，提案当场被拒 |
| `preview(self, args)` | 预览的一行或几行 |
| `snapshot(self, args)` / `restore(self, snapshot)` | 执行前存快照，撤销时还原（不写 `restore` 就用快照再执行一次 `apply`） |
| `ready(self, args)` | 返回暂时不能执行的原因，「执行」按钮暂不可用 |
| `settled(self, args, result)` | 客户端过一会儿才生效时（建宏、换天赋、存装备方案），返回是否已生效；每 0.1 秒问一次，`settleTime` 秒（默认 5）内没生效就算失败 |
| `combat = true` | 战斗中也可以执行的更改 |
| `reload = true` | 重载界面后才生效，预览会自动注明 |
| `notes = false` | 不要核心自动加注（「不可撤销」「重载后生效」） |
| `links = true` | 预览行里可以有链接记号（来自参数的部分照样先转义）：调用方、总线、Agent 和执行记录读到的是 `[name]`，弹窗画的时候换成客户端的链接（第 12 节） |
| `alone` | 这一步必须单独成为一个提案（`true`，或 `function(self, args)`），例如发到公开频道的消息：它要在玩家点击的那一刻发出 |

## 5. 两种模式

### Setting：游戏里存着的一个值

```lua
demo:Setting("volume", {
  title = L"VOLUME", doc = "the demo's volume, 0-10", value = "number", scope = "settings",
  validate = function(self, key, v) if v < 0 or v > 10 then return "0-10" end end,
  get = function(self, key) return self.db.volume end,
  set = function(self, key, v) self.db.volume = v end,
})
```

生成 `demo.volume.get`（读取）和 `demo.volume.set`（更改）。核心负责预览「旧 → 新」、执行前存旧值、执行后读回核对（游戏没有保留新值就算失败，这一步也还原旧值）、撤销还原旧值。

可选字段：`key`（指明是哪一个值的参数，如 `{ name = "string" }`）、`change`（只在更改时成立的说明，只写进 `.set` 的说明：不填值的结果、长度限制、游戏过一会儿才显示）、`validate`、`normalize`、`format`、`label`、`explain`、`info`、`same`、`check`、`settle = true`（过一会儿才生效）、`keep` / `restore`（撤销需要多存的内容）、`reload = true`。

### Feed：一段时间里监听一组游戏事件

```lua
ext:Feed("listen", { title = L"LISTEN", event = "message", events = { "CHAT_MSG_GUILD" },
  options = { channels = "table" }, read = function(self, event, ...) return { ... } end })
```

生成 `<名称>`（开始，带 `minutes`）、`<名称>.stop`、`<名称>.status`，并自动声明事件 `<扩展>.<event>`（不写 `event` 时用 Feed 的名称）。开始后记在存储里，重载后接着听；到点自动停止，玩家和 Agent 都会收到通知（`kit.feed`）。监听属于启动它的角色：换角色登录不会接着转发，也不会停掉它。窗口里显示正在运行，并有「停止」按钮。可选字段：`accept`、`prepare`、`describe`、`minutes`（默认 60）、`most`（最长，默认 720）、`eventDoc`、`data`。

`ext:Feed` 返回 Feed 本身。不是由单个游戏事件产生的条目（定时器、别的插件的回调、跨几个事件的统计）用 `feed:Push(data)` 发出：Feed 在运行、`accept` 放行时才发，返回是否发出。`feed:Running()` 在运行时返回它的选项（就是存着的那张表，扩展可以就地改它的 `digest`），否则返回 nil，没人听时可以跳过统计。

条目编号：每个发出的条目（表）都带 `id` 和 `time`。条目自己带 `id`（数字）时沿用（例如聊天消息的编号），否则取 `WuxianKit:NewId()`：核心只有一个计数器，聊天消息、各个 Feed 和应用的条目都从它取号，重载后接着数，永不重号；没有 `time` 时填 `time()`。

`feed:Push(data, { key, every })`：同一个 `key` 在 `every` 秒内只发第一条，其余丢掉（返回 false）。不写 `key` 时按整个 Feed 算。

`lease = 秒`（可选，至少 60）：Agent 这么久没有调用这个扩展的任何能力（`seen`，开始时算一次），Feed 就自动停止（`kit.feed` 的 `why = "left"`）。运行中选项里的 `lease` 优先于 spec 的；设了租期时状态里有 `lease` 和 `present`（还在租期内）。`seen` 每 5 秒存进运行状态，重载后接着算。Feed 停止时 `kit.feed` 带 `why`：`stopped`（玩家或 Agent 停的）、`expired`（到时）、`left`（租期过了）、`extension`（扩展停用）。

回看（`keep = n`，最多 200）：Feed 记住最近 `n` 个条目（存在存储里，重载、停止后仍在；换角色登录时从空开始），另生成 `<名称>.recent`（读取，参数 `since`、`limit`，默认 50）：答 `{ items, next }`，`items` 是编号大于 `since` 的最近 `limit` 个（从旧到新），`next` 是最新的编号。Lua 里用 `feed:Recent(since, limit)` 和 `feed:Item(id)`。

汇总（`digest = { gather, every, idle, most, urgent }`）：条目不再一个一个发出，先攒着，到时候合成一次「唤醒」：

- `urgent(self, options, item)` 为真的条目到了，再等 `gather` 秒（默认 5，让人把话说完）就唤醒；`urgent` 也可以是一张表（`{ "mention", "question" }`）：条目的 `why` 或 `kind` 在表里就算紧急；
- 其余条目：攒下的第一个到了之后 `every` 秒唤醒（默认 60；`false` 只在紧急或攒满时唤醒）；
- 攒满 `most` 个（默认 30）立即唤醒；
- `idle` 秒（默认 `false`：不唤醒）里既没有条目也没有唤醒，就唤醒一次，`items` 为空（冷场，供 Agent 开个话题）。
- 一次唤醒就是一个总线事件 `<扩展>.<event>`：`{ reason, items, skipped }`。`reason` 是 `urgent`、`full`、`batch` 或 `idle`；`items` 从旧到新；单个事件太大时去掉最旧的几个，`skipped` 是去掉的个数（它们仍在回看里）。
- 运行时的参数以选项里的 `digest` 表为准（`prepare` 可以按玩家的设置填它，运行中也可以经 `feed:Running().digest` 就地改），没有的字段用 spec 的。

`<名称>.status` 还答 `heard`（这次运行收到的条目数）、`wakes`（唤醒次数）、`lastWake`、`seen`（Agent 最近一次调用这个扩展任何能力的时间，由核心记录；没有调用过为 nil）。窗口里正在运行的 Feed 一行下面显示「Agent 最近应答」或「Agent 尚未应答」。

## 6. 提案

| 状态 | 含义 |
|---|---|
| `pending` | 等玩家确认 |
| `waiting` | 免确认或已确认，还没到 `after` 时刻，或暂时不能执行（如聊天锁定） |
| `queued` | 已确认，含更改步骤，等脱战后执行（或执行到一半进入战斗，其余步骤等脱战） |
| `running` | 执行中：某一步在等客户端生效 |
| `done` | 已执行；之后可以撤销，撤销后为 `undone` |
| `failed` | 执行失败，已执行的步骤（含失败前已改动游戏的这一步）按快照撤回 |
| `declined` | 玩家拒绝，或在执行前取消，或所属扩展被停用 |
| `expired` | 到期没有处理 |

- 来源：`agent`、`addon:<插件>`、`rule:<名称>`、`remote:<玩家>`（别的玩家经远程扩展发来）、`import:<配置档>`（别人分享的配置档）。
- 一个提案可以有多步，玩家确认一次。某一步失败就停下，已执行的步骤按快照撤回。只执行仍然有效的能力：所属扩展被停用后，还没执行的提案作废，执行到一半的撤回已执行的步骤。
- `pending`、`waiting` 默认 300 秒内没有处理就过期（`ttl`，10–600 秒）；`queued`、`running` 不会过期。`after` 指定不早于某个时刻执行，必须早于过期时间。
- 战斗中确认的提案，脱战后重新检查一遍（免确认、时间、聊天锁定、就绪）再执行；步骤之间进入战斗时，其余步骤等脱战后接着执行。
- 免确认：一个提案的每一步都属于玩家勾选的类别时，不弹窗直接执行；执行前会再确认一次，玩家已取消勾选的改为待确认。别的玩家发来的提案和别人分享的配置档始终需要确认。免确认只能由玩家在窗口里设置。
- 分层：类别按点分层，一步属于 `chat.guild.reply` 时，从它往上找（`chat.guild.reply` → `chat.guild`）最近一个玩家勾选的类别，按那个类别算。勾选上一层就覆盖下一层。
- 限额：勾选时可以带限额 `{ per = 秒, most = 次数 }`（默认用类别建议的 `budget`，玩家可以改成别的或不限）。一个类别在 `per` 秒里免确认执行过的步骤（只数免确认执行的，玩家点执行的不算）加上这个提案里属于它的步骤超过 `most` 时，这个提案改为待确认，预览里注明「已到免确认上限」。限额只能由玩家设置；旧存档里的勾选（`true`）视为不限。
- `Kit:Granted(scope)` 答两个值：这一步现在会不会免确认（按分层），以及限额里还剩几次（不限时为 nil）。
- 提案标题经转义，最长 120 字节。弹窗里显示的提案被换成另一个时，「执行」按钮和 `/wk yes` 等 1 秒，防止误点。
- 执行过的提案保留最近 50 条，按角色区分：只能在执行它的角色上撤销。玩家可以在窗口里撤销，Agent 用 `kit.undo` 发起撤销提案。
- 每次状态变化都发出总线事件 `kit.proposal`。

接口：`Kit:Call(id, args, opts)`（读取、存储、指引类立即返回结果；发送、更改类返回提案）、`Kit:Propose(steps, opts)`、`Kit:Check(id, args)`（预检：现在提议是否会被拒及原因，不产生提案）、`Kit:Proposal(id)`、`Kit:Proposals()`。

## 7. Agent 接入

- 清单：`Kit:Manifest()`（Agent 经 `kit.manifest` 读取）：`protocol`、`kit`（版本）、`language`、`revision`，以及每个扩展的 `id`、`title`、`version`、`addon`、`builtin`、`state`、`docs`；已启用扩展还有 `capabilities` 和 `events`。
- 修订号：扩展启用或停用、能力变化、语言切换时改变；变化后约 0.5 秒发出 `kit.changed`，这半秒内的变化合并为一次。
- 事件经开发组件交给 Agent：核心的事件（`kit.*`）被挡下时留在队列里（最多 50 条）等有空再发；扩展的事件限速，丢掉的每 5 秒用 `kit.dropped` 报告一次。无限工坊未连接时，开发组件只保留最近的少数事件。
- 能力的完整 id（`<扩展>.<名称>`）与事件的完整主题都不超过 64 字节（开发组件能传的长度）；超出的在声明或发出时就报错，有没有无限工坊都一样。
- Agent 接入需要开发组件 WoWBridge 0.9.7 或更新版本（调用以数据传入，关闭热加载也能用）；没有它或版本更旧时，扩展框架照常运行，只是 Agent 用不到。
- 说明与技能放在 `docs` 指向的文件夹（`Interface\AddOns\<插件>[\<docs>]`）：`AGENT.md`，以及 `skills/<名称>.md`。无限工坊 App 直接从磁盘读取，不经过游戏。
- 技能文件开头写：

  ```
  ---
  name: tune-setup
  title: Tune a setup
  title-zh: 调一套设置
  description: Change a set of settings ... in one proposal
  description-zh: 按玩家的要求调整一组设置……合成一个可以整体撤销的提案
  arguments: goal, role?
  needs: shell
  mcp: wuxianwow https://wuxianwow.com/mcp
  ---
  正文：给 Agent 的步骤（英文）。参数写成 {{goal}}。
  ```

  `needs`、`mcp` 可选，都用逗号分开：`needs` 是技能对客户端的要求，已知的 `shell` 指能在后台跑命令（等待靠 `wuxian listen`），不认得的值原样保留；`mcp` 是技能会用到、但不是无限工坊的 MCP 服务器，每项 `<名字> <URL>`（只收 `https://`），无限工坊 App 据此列准备清单、帮玩家接入。`name` 是提示词的名字；`description` 和正文给 Agent 看；`title` 是提示词的显示名称；`title`、`title-zh`、`description-zh` 显示在无限工坊 App 和网站的扩展目录里。参数用逗号分开，末尾加 `?` 表示可选。技能只写需要几个工具按顺序配合的用法，单个工具怎么用写在 `AGENT.md`。

- App 的翻译规则：每个能力一个工具 `wk_<扩展>_<名称>`（点换成下划线），参数按声明生成 JSON Schema，读取类标为只读；另有 `wk_docs`（说明）、`wk_wait`（等待提案结果）、`wk_propose`（多步合成一个提案）；`AGENT.md` 成为资源 `wuxian://kit/<扩展>`，技能成为提示词。
- 边界：说明和技能只描述用法，不授予权限。发送和更改仍需玩家确认；免确认只能由玩家设置。

## 8. 让别的插件成为扩展

1. `.toc` 写：

   ```
   ## Dependencies: WuxianKit
   ## X-WuxianKit-Extension: demo
   ## LoadOnDemand: 1
   ```

   扩展框架在登录时载入它（玩家停用的除外），没载入时也会列在 `/wk` 里。玩家不一定装了扩展框架；已有的插件要在没有它时照常工作，就改写
   `## OptionalDeps: WuxianKit`（不写 `LoadOnDemand`），并只在 `if WuxianKit then ... end` 里注册扩展。
2. 代码：`Kit:Words`、`Kit:Extension`，再声明能力、事件、类别（见第 3–5 节）。
3. 在插件文件夹放 `AGENT.md`，需要时加 `skills/`。
4. 检查：用无限工坊的 `check` 检查插件；进游戏后 `/wk` 里应出现它的一页（不装无限工坊时，也可以用 `/run` 调 `WuxianKit:Capabilities()` 看能力是否齐全）；装了无限工坊时，Agent 用 `wk_docs` 查看它的工具和说明。
5. 发布：可以申请收录进无限工坊网站的扩展目录，玩家就能在 App 的「扩展」页安装。

## 9. 公共接口与约定

公共表 `WuxianKit`：`Extension`、`Words`、`Call`、`Propose`、`Proposal`、`Proposals`、`Capabilities`、`Capability`、`Manifest`、`Granted`、`On`、`Off`、`Emit`、`Escape`（转义外来文字）、`AgentOnline`、`Window`（打开扩展框架窗口，可指定扩展或应用：`app:<id>`，同名时扩展优先）、`Comm`（插件消息）、`Skin`（窗口样式）、`Copy`（复制框）、`OptionsPanel`（在别的窗口里画选项）、`Requires`（版本判断）、`Chat`（聊天扩展给别的插件用的解析：`Read`、`Mentions`、`Message`、`Names`、`On`、`Off`，见 `Extensions/Chat/AGENT.md`）、`Game`（游戏动态，第 11 节）、`App`、`AppControl`、`AppSay`、`AppPanel`（应用，第 10 节）、`Value`、`Clean`、`Links`、`Link`、`Linkify`、`Unlink`、`Preload`、`Unit`、`Pattern`、`NewId`、`Me`（第 12 节）、`VERSION`。

- 不模拟输入、不读内存、不注入代码。施法、使用物品、选择目标、摆动作条这类受保护操作，插件做不到，用指引类指给玩家。
- 机密值不读：读到的值是机密值时跳过。
- 硬边界：玩家关掉无限工坊的热加载后，Agent 只能调用插件公开的能力（不带代码的调用，需要无限工坊 0.9.7 或更高版本）。热加载开着时，Agent 可以执行任意代码，权限只是约定。
- 代码注释用英文；给玩家看的文字中英两份。

## 10. 应用（0.6）

一个 AI 应用（本机的陪玩进程、Claude Code 里的公会聊天、以后的副本解说……）不写扩展也能接入：用一份**声明**说清楚它听什么、怎么攒成唤醒、玩家能在游戏里对它下什么指令、多久没有音信算离开、玩家给它设什么选项。核心按声明组成一个 Feed，在 `/wk` 的「应用」页给它一页。

声明可以来自插件（Lua，可以带函数），也可以来自 Agent（`kit.app.open` 的参数，只有数据；会被记住，下次只写 `app` 就行）：

```lua
WuxianKit:App("officers", {
  title = "官员频道", prompt = "officer-chat", addon = "MyGuildTools", extension = "myguild",
  hear = { "chat:officer", "game:guild" },
  pace = true, urgent = { "mention", "followup", "question", "burst" },
  controls = { "stop" }, lease = 600, minutes = 120,
  options = { topics = { kind = "list", title = "想多聊的话题" }, avoid = { kind = "list", title = "不聊的话题" } },
  check = function() if not IsInGuild() then return "你还没有加入公会" end end,
  enrich = function(item) if item.kind == "guild.join" then item.recruited = IsMine(item.data.name) or nil end end,
})
```

| 字段 | 含义 |
|---|---|
| `id` | 小写字母、数字和 `_`，最长 24 字节；事件主题是 `app.<id>` |
| `title` | 显示名称（Agent 给的最长 48 字节，转义后显示） |
| `hear` | 来源的列表（被同一份声明里更宽的来源覆盖的会去掉：`chat:*` 覆盖各频道，`game:*` 覆盖各主题）：`chat:<频道>`（聊天扩展能听的频道：guild、officer、party、raid、instance、whisper、say、yell、channel、community）、`game:<主题>`（第 11 节）、`bus:<主题>`（任何总线主题，可以带 `.*`；`kit.*`、`app.*` 不行） |
| `digest` | `false` / 不写：每个条目到了就发（`reason = "item"`）；一张表 `{ gather, every, idle, most }`：攒成唤醒（同 Feed 的汇总） |
| `pace` | `true` 或三档的表 `{ quiet = {...}, normal = {...}, lively = {...} }`（每档 `{ gather, every, idle, most, wake = { why... } }`）：攒成唤醒，节奏跟玩家的选项走；`true` 用核心的三档（见下）。有 `pace` 时不看 `digest` |
| `urgent` | 不用 `pace` 时，哪些条目立即唤醒：`why` 或 `kind` 的列表；Lua 声明也可以是函数 `urgent(item)`。有 `pace` 时只看当前档的 `wake`（同样按 `why` 或 `kind`） |
| `controls` | 玩家能下的指令：`mute`、`unmute`、`less`、`more`、`test`、`pause`、`resume`、`stop` 里挑；`stop` 由核心执行（停止应用），其余只转告应用 |
| `say` | `true`：玩家可以用 `/wk <id> <一句话>` 对应用说话 |
| `me` | `true`：游戏动态的条目带 `me`（`WuxianKit:Me()`） |
| `lease` | 秒（默认 600，至少 60；`0` 不设）：这么久没有 `kit.app.*` 调用就算离开，应用停止（`why = "left"`） |
| `minutes` | 最长运行多久（默认 120，最多 720）；`kit.app.open` 的 `minutes` 优先 |
| `options` | 玩家给应用设的选项，`name → { kind, title, default, hint, choices, min, max, step, unit, order }`，种类同扩展选项；按 `order`（再按名字）排，核心的两个在最前；Agent 给的最多 8 个 |
| `prompt` | 技能名：有了它就有启动语 `start`（见下），卡片上有「交给 AI」 |
| `addon`、`extension` | 所属插件、所属扩展（Lua 声明）：所属扩展停用时应用停止、不能开始 |
| `check` | （Lua）开始前的前提，返回原因就不开始，卡片上显示原因 |
| `enrich` | （Lua）条目发出前就地补字段 |

框架自己带一个应用 `guild`（公会聊天，`Extensions/Chat/GuildApp.lua`）：所属插件 WuxianKit、所属扩展 `chat`，听 `chat:guild` 和 `game:guild`，`pace = true`，指令 `mute`、`unmute`、`stop`，`say = true`，租期 600 秒、最长 120 分钟，选项 `topics`「想多聊的话题」与 `avoid`「不聊的话题」（`order` 1、2），`check`：没有公会就不开始。没有 `enrich`。技能是聊天扩展的 `skills/guild-chat.md`（提示词 `guild-chat`）：游戏事实由 Agent 自己用无限图鉴的 MCP（wuxianwow.com/mcp）查。装了框架和无限工坊的玩家都有它；id 沿用无限公会助手 0.3 的 `guild`，玩家存在 `WuxianKitDB.apps.guild` 的选项接着用。无限公会助手不再声明它；旧版（0.3.0）还声明时，它后载入，它的声明替换框架的（同 id 后声明的为准，不报错）。

核心的三档（`pace = true`）：

| 档 | gather | every | idle | wake |
|---|---|---|---|---|
| `quiet` 安静 | 6 | `false` | `false` | mention |
| `normal` 适中（默认） | 5 | 60 | 1200 | mention、followup、question |
| `lively` 活跃 | 3 | 20 | 480 | mention、followup、question、burst |

`most` 都是 30。有 `pace` 时核心给应用加两个选项：`activity`「活跃度」（quiet / normal / lively）和 `quiet`「免打扰时段」（如 `01:00-08:00`，也认全角冒号、`～`、`至`、`到` 和只写小时的 `1-8`，可以跨午夜）。免打扰时段里 `every`、`idle` 都不唤醒，只有 `why = "mention"` 立即唤醒。选项变了、进出免打扰时段、重载后，运行中的应用马上按新节奏走。

条目（都带 `id`、`time`、`source`）：

| source | 字段 |
|---|---|
| `chat` | 聊天消息的全部字段（第 5 节 chat.message，含 `why`）；`id` 就是聊天消息的编号，回复用它 |
| `game` | `kind`、`topic`、`data`、`me?` |
| `bus` | `topic`、`data` |
| `addon` | `data`（`app:Push(data)`） |
| `control` | `cmd` |
| `player` | `text`（玩家在游戏里对应用说的话） |

`control` 与 `player` 条目总是立即唤醒（不等 `gather`）。

事件 `app.<id>` 只有一个形状：`{ app, reason, items, skipped, pace?, quiet? }`。`reason`：`item`（不汇总）、`urgent`、`full`、`batch`、`idle`。单个事件太大时去掉最旧的，`skipped` 是去掉的个数（它们在回看里）。另有核心事件 `kit.app`：`{ app, on, why?, ends? }`，应用开始和停止时发出；`why`：`stopped`（Agent 停的）、`player`、`expired`（到时）、`left`（租期过了）、`extension`（所属扩展停用）、`replaced`。

能力（核心扩展 kit）：

- `kit.app.open { app, minutes?, ...声明 }`（读取）：开始应用，答状态。同名应用正在运行时只续时间和租期（发一次 `kit.app` `on = true`）；只有 Agent 给了不同的声明，才先停掉旧的（`why = "replaced"`）再开。插件声明过的应用只认 `app`、`minutes`、`lease`，多给的字段列在回答的 `ignored` 里；Agent 声明的会被记住（最多 8 个，玩家可以在窗口里移除）。现在不能开始时不报错（报错会在玩家游戏里弹红字，Agent 每次重试都弹一次），答它的状态：`on = false`，`blocked` 是原因：`check()` 不过、所属扩展停用，或听 `chat:`、`game:` 但聊天扩展、游戏动态关着。
- `kit.app.status { app }`：`{ app, title, by, on, ends, started, next, heard, wakes, lastWake, seen, present, lease, pace?, quiet?, said, hear, controls, say, blocked?, extension?, why?, start? }`；`lease` 没设为 0；`blocked` 是现在不能开始的原因；`extension` 只在声明了所属扩展时出现（false = 停用）；停着时 `why` 是上一次怎么停的。`said` 是今天 Agent 来源、执行完的 `chat.send` 里发到应用所听频道的条数。它也是心跳：Agent 的每次 `kit.app.*` 调用都更新 `seen`。
- `kit.app.stop { app }`、`kit.app.recent { app, since?, limit? }`（回看最近 100 个条目，同 Feed 的 `.recent`）、`kit.apps`（`[{ id, title, by = addon|agent, addon?, on, ends, present, prompt?, start?, extension?, blocked? }]`；`blocked` 只在停着时给；它不是心跳，不续应用的租期，所以工坊 App 的页面读它而不读 `kit.app.status`）。清单的 `apps` 也带 `extension`。

启动语（`start`）：有 `prompt` 的应用才有，按当前语言生成，`%s` 依次是应用标题、技能名。中文 `开始无限工坊的应用「%s」：先调用工具 wk_docs，参数 {"skill": "%s"}，照读到的步骤做。`，其他语言 `Start the 无限工坊 app "%s": first call the tool wk_docs with {"skill": "%s"} and follow the steps it gives.`。它出现在 `kit.apps`、`kit.app.status`（含 `kit.app.open` 的回答）和清单的 `apps` 里。提示词只有技能文件一份，启动语只是指向它的一句话：任何接了无限工坊 MCP 的客户端都能照着开工。卡片上的「交给 AI」打开复制框：标题是应用名，框里是启动语，下面一行「按 Ctrl+C 复制，粘贴到 AI 对话里」；应用运行中不显示。
- `kit.options { app }`：应用的选项（同扩展；显示顺序 `activity`、`quiet` 在前，其余按名字）。改了应用的选项，总线事件 `kit.option` 是 `{ app, name, value }`。

运行状态按角色存（同 Feed），重载后接着跑；换角色登录不接着转发。存储：`WuxianKitDB.apps[id] = { decl, run, recent, options, said, last }`（`decl` 只有 Agent 声明的应用才存）。

`/wk <id>` 打开应用页；`/wk <id> <词>`：词（如「静音」「少说」「停止」）换成指令且在它的 `controls` 里，就是指令；否则 `say = true` 时当作对应用说的话；都不行就提示它接受的指令。

等唤醒：无限工坊 0.9.13 的 `wuxian listen <id> [--open 声明.json] [--minutes N] [--since N] [--once] [--max 秒] [--replace]`。它先问 `kit.app.status`，在跑就接上，不在跑才 `kit.app.open`（`--replace` 强制重开）；每个唤醒打印一行 JSON（`{ id, t, topic, data }`），每批之后 `NEXT <id>`，应用停了 `END <why>`，到 `--max` 打印 `TIMEOUT`；自己按 max(30, lease/3) 秒心跳，`kit.ready` 后重新接上。游戏外的长驻程序可以用无限工坊仓库的 Python SDK `sdk/python/wuxiankit.py`（`Client().app(id, ...)` 迭代唤醒）。

Lua：`WuxianKit:App(id, decl)` 返回应用对象（`app:Get(name)`、`app:Running()`、`app:Push(data)`）；`WuxianKit:AppControl(id, cmd)`、`WuxianKit:AppSay(id, text)`（玩家的指令与话；`/wk <id> <词或话>`、卡片按钮都走它们）；`WuxianKit:AppPanel(id, parent, width)`：在插件自己的窗口里画应用卡片（状态、交给 AI、停止、指令按钮、选项），和 `/wk` 的应用页是同一张，返回带 `:Refresh()` 的框体。

清单：`Kit:Manifest()` 多一个 `apps`：`[{ id, title, by, addon?, topic = "app.<id>", hear, prompt?, start? }]`，修订号包含它；游戏不在线时无限工坊也从保留的清单拿到启动语。

权限不变：应用只「听」已有读取类能听到的东西，说话、改游戏照旧走发送和更改类的提案与类别。Agent 给的文字限长、原样存，显示时转义。

## 11. 游戏动态（0.6）

内置扩展 `game`（「游戏动态」）：游戏里发生的事，按主题分组。某个主题只在有人听（运行中的 `game.listen` 含它，或有匹配的 `Game:On`）时才运行它的探测，打开时重建基线（经验、天赋、任务日志、公会名单），不会一开始就误报。高频事件更省：UNIT_COMBAT、UNIT_HEALTH、NAME_PLATE_UNIT_REMOVED 只在听到的战斗中注册，UNIT_AURA 只在脱战时注册；区域到访一直记（`first` 要用）。时间都是整数秒。读不到的值（机密值）不报，字段就不写。

- Feed `game.listen { topics?, me?, minutes }`（不写 topics 就是全部）→ 事件 `game.moment`：`{ id, time, kind, topic, me?, data }`；回看 50 个（`game.listen.recent`）。
- Lua：`WuxianKit.Game:On(kind 或 主题 或 "*", fn(item))` 返回记号，`WuxianKit.Game:Off(记号)`；`item = { kind, topic, time, data }`（每个订阅者一份，不带编号）；`what` 不认识时报错。`Game.TOPICS`、`Game.KINDS`（kind → 主题）。

单位结构 `unit` 即 `WuxianKit:Unit(unit)`：`{ name, fullName, level, classification, creature, player, hostile, class }`。

| 主题 | kind | data | 什么时候 |
|---|---|---|---|
| combat | `combat.start` | `target: unit?`、`foes` | 进战斗，约 0.5 秒后数仇恨表里有你的敌人（至少 1） |
| | `combat.end` | `secs`、`kills`、`foes`（最多同时几只） | 脱战 |
| | `danger` | `why = "adds"`、`foes`（正在打你的敌人数） | 3 个以上敌人在打你；同一场战斗 8 秒内一次 |
| | `cast.at_me` | `caster: unit` | 目标读条且目标的目标是你；同一目标 6 秒一次 |
| | `kill` | `unit` | 打过你或被你打过的目标死了（副本里目标的名字、GUID 是机密值时数不到） |
| | `death`、`alive` | `alive`：`how = spirit|revive` | 死亡、复活 |
| | `spell.big` | `spell`、`id`、`cd`（秒） | 自己施放基础冷却 ≥ 60 秒的技能；同一技能 30 秒一次 |
| | `target` | `unit` | 选中敌对的精英、稀有、首领或玩家；同一目标 60 秒一次 |
| aura | `aura.gift` | `spell`、`from` | 脱战时别的玩家给你加增益；同一技能 60 秒一次 |
| | `aura.bad` | `spell`、`type`（Poison / Curse / Disease / Magic） | 脱战时中了可驱散的负面效果；同一技能 60 秒一次 |
| growth | `xp` | `gained`、`pct`、`from = kill|quest|other` | 经验跨过 25 / 50 / 75 / 90%，或一次 ≥ 5%（升级那次不报） |
| | `level` | `level`、`talentPoints?` | 升级 |
| | `talent` | `name?`、`points?` | 学了天赋（脱战时比较） |
| | `spell.new` | `spell`、`id` | 学会新技能 |
| quest | `quest.accept` | `quest`、`id` | 接任务 |
| | `quest.progress` | `quest`、`id`、`objective` | 某个目标刚完成 |
| | `quest.ready` | `quest`、`id` | 目标全部完成 |
| | `quest.turnin` | `quest?`、`id`、`xp?`、`money?`（铜） | 交任务 |
| travel | `zone` | `zone`、`first`（本角色第一次来） | 换大区域 |
| | `taxi` | `to?` | 坐上飞行点 |
| | `rest` | — | 进入休息区 |
| guild | `guild.join`、`guild.leave` | `name` | 有人入会、退会（系统消息）；同一人 5 秒一次 |
| | `guild.achievement` | `name`、`plain`、`links` | 公会成员获得成就 |
| | `guild.level` | `name`、`level` | 成员升到整十级或满级（公会名单前后比较；主题打开时先要一次名单，之后每 60 秒一次；第一份名单只记下） |
| guide | `guide.step` | `guide`、`index`、`lines`（最多 6 行文字）、`goto?`（`{ map, zone, x, y }`）、`targets?`（最多 5 个名字） | RestedXP 换了当前步（安静 0.3 秒后取当前步；步号没变不报） |
| | `guide.arrive` | `guide`、`index` | 到达当前步的路点 |

`guide` 只在装了 RestedXP（RXPGuides）时有内容，经它的 AceEvent 消息收（`RXP_STEP_ACTIVATED`、`RXP_OBJECTIVE_COMPLETE`、`RXP_TARGET_LIST_UPDATE`、`RXP_GUIDE_LOADED`）。主题打开时挂上，关掉时摘下。游戏里的文字只是数据。

## 12. 公共小工具与称呼（0.6）

| 接口 | 作用 |
|---|---|
| `WuxianKit:Value(v)` | 机密值或读不到给 nil，其余原样 |
| `WuxianKit:Clean(text)` | 游戏文字变成一行纯文字：去颜色、贴图、图集，链接留文字（`[名字]`），换行和连续空白变一个空格；空了给 nil |
| `WuxianKit:Links(text)` | 文字里的链接：`[{ kind, id, name }]`，kind 与下面的链接记号一致（`enchant` 读作 `recipe`） |
| `WuxianKit:Link(kind, id)` | 客户端给的链接，给不出时为 nil；物品数据还没载入时先请求，这次为 nil |
| `WuxianKit:Linkify(text)` | 文字里的每个 `{kind:id:name}` 换成客户端的链接，给不出的写成 `[name]`（没写名字就是 `[id]`）；第二个返回值是换上的链接数 |
| `WuxianKit:Unlink(text)` | 记号都写成 `[name]`：数字节、纯文字预览、给 Agent 的副本 |
| `WuxianKit:Preload(text)` | 请求记号里还没载入的物品，链接在显示、发送时就有了；返回还在载入的个数 |
| `WuxianKit:Unit(unit)` | 单位结构（第 11 节） |
| `WuxianKit:Pattern(fmt)` | GlobalStrings 的格式串变成匹配它的模式：`%s` 捕获文字、`%d` 捕获数字 |
| `WuxianKit:NewId()` | 核心计数器的下一个编号 |
| `WuxianKit:Me()` | `{ name, nickname, level, class, classToken, zone, subzone, combat }` |
| `ext:Char()` | 本角色的存储 |

### 链接记号

Agent 在交来的文字里写 `{kind:id:name}`（名字可以省略：`{item:2589}`），`Linkify` 换成客户端给的链接；`Links` 把游戏文字里的链接读成同样的 kind 和 id，两个方向一套写法。

| kind | 客户端接口（实测 1.60.1） | 链接类型 | 说明 |
|---|---|---|---|
| `item` | `C_Item.GetItemInfo(id)` | `item` | 物品数据载入后才有；没载入时 `C_Item.RequestLoadItemDataByID` 请求，过一会儿才有 |
| `spell` | `C_Spell.GetSpellLink(id)` | `spell` | 任何法术；坐骑、专业也是法术（458 棕马、2550 烹饪 (初级)） |
| `recipe` | `C_TradeSkillUI.GetRecipeLink(配方法术 id)` | `enchant` | 没学会的配方也有（2538 烹饪：烧烤狼肉）；记号也可以写 `enchant` |
| `achievement` | `GetAchievementLink(id)` | `achievement` | 链接带玩家自己的 GUID 和进度，别人看到的是这位玩家的进度 |
| `currency` | `C_CurrencyInfo.GetCurrencyLink(id)` | `currency` | 3402 商人青睐；客户端没有的编号给 nil |
| `quest` | `GetQuestLink(任务 id)` | `quest` | 只有玩家任务日志里的任务，其余给 nil |

- 只用客户端给的链接，核心不拼 `|H` 代码：一个记号最多换出那个编号在客户端里的链接。
- 给不出链接（不认识的 kind、客户端不认识的编号、不在日志里的任务、还没载入的物品）就写成 `[name]`，不算错。
- 外来文字先转义（`WuxianKit:Escape`，或保留换行的 `|` 加倍），再 `Linkify`：除了客户端的链接，别的代码都不生效。
- 这个客户端没有地下城手册（`EJ_GetNumTiers()` 为 0），没有副本、首领链接；NPC、地区、头衔没有链接类型；地图标记要用玩家自己的路标，不做。
- 用在：`chat.send`（发送时换，255 字节按换好链接后算；提出提案时先请求物品）；提案弹窗（`links = true` 的预览，每秒重画时换，物品载入后就成了链接）；`guide.note` 的文字和标题、`guide.tour` 的步骤和标题、`guide.highlight` 的文字（物品载入后重画）。
- 悬停提示：`WuxianKit.Skin.Hyperlinks(frame, hover)` 给自己的窗口打开链接和 `GameTooltip` 提示；本身不接鼠标的框体传 `hover`（有链接时才接鼠标移动，点击照样穿过）。

核心选项 `nickname`「称呼」（文本，AI 应用怎么叫玩家；空的就叫角色名），在 `/wk` 的核心页设置。`kit.me`（读取）：`{ name, nickname, aliases }`，`aliases` 是聊天扩展的 `Chat.Names()`（完整角色名、它的各段和「别人怎么叫我」；聊天扩展关着时为空）。

聊天消息（第 5 节 `chat.message`）在 0.6 多一个字段 `why`：

- `mention`：点到玩家（或密语给玩家：密语总是 `mention`）；
- `followup`：玩家在同一个对话（频道，密语按对方，频道按频道名）里说完 90 秒内别人说的；
- `question`：像在提问（问号、吗、怎么、哪、多少……，不是求组、买卖），至少 6 字节；
- `burst`：20 秒里两个以上的人说了三句以上，话题正热；同一个对话 45 秒最多一次；
- 玩家自己的话、都不是：没有 `why`。

`WuxianKit.Chat:On(频道 或 "*", fn(msg))` 返回记号，`WuxianKit.Chat:Off(记号)`：聊天扩展开着时，那个频道读到的每条消息（不管 chat.listen 在不在跑），每条只读一次。

## 13. 版本 0.5 的由来

0.5 的新接口都来自「无限公会助手」这个实际场景（本机 Agent 参与公会聊天），判断标准是：第二个扩展也会用到的进核心，只和公会有关的留在公会助手，Agent 自己管得好的（记忆、资讯）放在 Agent 那边。

| 新接口 | 公会助手用它做什么 | 别的用处 |
|---|---|---|
| 选项的 `number`、`choice`、`list`，`kit.options`，`OptionsPanel` | 活跃度、话题、免打扰；同一份设置画在自己的窗口里 | 陪玩的称呼、调校 |
| Feed 的编号、回看、汇总 | 公会聊天攒一批叫醒 Agent，有人点名立即叫醒，冷场时叫醒 | 陪玩的时刻、答疑；忙的频道不再被限速丢事件 |
| 类别分层与限额 | 「回复点名我的人」与「公会频道」分开授权，免确认也有上限 | 密语回复、队伍频道 |
| `Copy`、`info.prompt`、`Requires` | 邀请命令、接入提示词 | 复制框给应用卡片的「交给 AI」用（0.6 起扩展页不再有「接入 Agent」） |
| 聊天扩展的点名、回复、让玩家先说、`WuxianKit.Chat` | 认出有人叫我，回复可以单独免确认 | 答疑、陪玩、队伍助手 |
| `sense.guild` | 公会概况与在线成员 | 答疑、Agent 了解公会 |

## 14. 版本 0.6 的由来

0.6 来自两个实际应用：无限陪玩（本机进程听游戏里的大事件，用语音陪玩）和无限公会助手（Claude Code 里的 Agent 参与公会聊天）。两个应用为了接入各写了一个扩展，加起来约 1,800 行，几乎都是通用的：探测游戏里发生的事、Agent 在不在与节奏、聊天语境、外部进程的接入、读值的小工具。0.6 把它们收进框架，下一个 AI 应用写一份声明就能接入。0.5 没有单独发布，与 0.6 合成一次发布，0.5 里的 `WuxianKit.Chat.NewId`、「汇总 Feed 的事件名要和 Feed 不同」两条在 0.6 去掉。

| 新接口 | 两个应用原来怎么做 |
|---|---|
| 游戏动态 `game` | 陪玩的 Combat / Progress / RXP 三个文件；公会助手解析入会、成就与比较公会名单 |
| 应用 `WuxianKit:App`、`kit.app.*`、卡片 | 陪玩每 6 小时续一次 Feed、`/wk voice` 指令；公会助手的活跃度三档、免打扰时段、接入状态页 |
| 租期 `lease` | 消费方走了 Feed 还在跑 |
| 聊天的 `why`、`Chat:On` | 公会助手自己判断点名、接话、提问、话题正热 |
| `Value`、`Clean`、`Links`、`Unit`、`Pattern`、`NewId`、`Me`、`ext:Char`、称呼 | 两个应用各写一份 |
| 链接记号 `Link`、`Linkify`、`Unlink`、`Preload` | 只有 `chat.send` 换物品和法术，弹窗和指引里看不到链接 |
| 工坊 `wuxian listen`、`sdk/python/wuxiankit.py` | 陪玩自写长轮询客户端；公会技能里手写等待循环 |
