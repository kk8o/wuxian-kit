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
    UI/                    提案窗口、扩展框架窗口（/wk）、样式（WuxianKit.Skin）
    Builtins.lua           核心自己的扩展 kit：扩展开关、提案查询、撤销、清单
  Extensions/<名称>/        内置扩展：<名称>.lua 等代码，AGENT.md，skills/
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
- `info` 的字段：`title`、`version`、`notes`、`addon`（所属插件的文件夹名，别的插件的扩展写它）、`defaults`（存储的默认值）、`setup(self)`（启用时）、`teardown(self)`（停用时）、`docs`（`AGENT.md` 与 `skills/` 所在的子文件夹，相对于插件文件夹；不写就是插件文件夹本身）。
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
| `ext:Scope(name, title)` | 免确认的类别，玩家在窗口里勾选 |
| `ext:Option(name, { title, kind, default, hint, changed })` | 玩家在窗口里设置的选项（勾选框或文本框）；只能由玩家修改，没有任何能力能读写 |
| `ext:Get(name)` | 读选项的值 |
| `ext:Command(word, fn, help)` | 斜杠命令 `/wk <word>` |
| `ext:Status(fn)`、`ext:Button(label, fn)` | 窗口里这一页的一行状态和几个按钮 |
| `ext:Tell(text)` | 以扩展名义在聊天框给玩家一行提示 |

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
  ---
  正文：给 Agent 的步骤（英文）。参数写成 {{goal}}。
  ```

  `name` 是提示词的名字；`description` 和正文给 Agent 看；`title` 是提示词的显示名称；`title`、`title-zh`、`description-zh` 显示在无限工坊 App 和网站的扩展目录里。参数用逗号分开，末尾加 `?` 表示可选。技能只写需要几个工具按顺序配合的用法，单个工具怎么用写在 `AGENT.md`。

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

公共表 `WuxianKit`：`Extension`、`Words`、`Call`、`Propose`、`Proposal`、`Proposals`、`Capabilities`、`Capability`、`Manifest`、`Granted`、`On`、`Off`、`Emit`、`Escape`（转义外来文字）、`AgentOnline`、`Window`（打开扩展框架窗口，可指定扩展）、`Comm`（插件消息）、`Skin`（窗口样式）、`VERSION`。

- 不模拟输入、不读内存、不注入代码。施法、使用物品、选择目标、摆动作条这类受保护操作，插件做不到，用指引类指给玩家。
- 机密值不读：读到的值是机密值时跳过。
- 硬边界：玩家关掉无限工坊的热加载后，Agent 只能调用插件公开的能力（不带代码的调用，需要无限工坊 0.9.7 或更高版本）。热加载开着时，Agent 可以执行任意代码，权限只是约定。
- 代码注释用英文；给玩家看的文字中英两份。
