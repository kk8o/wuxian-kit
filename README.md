# WuxianKit · 扩展框架

《魔兽世界：无限》插件的 Agent 接入框架。插件把功能声明为能力，AI Agent 经[无限工坊](https://wuxianwow.com/workshop)调用；更改游戏的操作在游戏中预览，玩家执行后生效，可以撤销。

[English](#english)

## 概述

- **零件、成品、运行时**：扩展是零件，声明能力（读取、存储、指引、发送、更改五类）、来源（应用能听的条目）、状态面（应用能看的现状）和事件，并附一份给 Agent 的说明 `AGENT.md`；应用是成品，一份声明，由 Agent 照技能驱动；核心是运行时，负责确认、撤销、权限、窗口和应用的运行。应用用扩展，扩展不知道有哪些应用。
- **事实归核心，说法归应用**：发生了什么（来源）、现在怎样（状态面）由框架给出；说不说、何时说、怎么说由应用决定。核心不认识第三方插件，第三方插件经自定义扩展的适配器接到框架的接口上。
- **提案与撤销**：发送、更改类操作生成提案，在游戏中逐项预览，玩家执行后生效；执行前存快照，可以撤销。多项改动可以合成一个提案，一次执行，一次撤销。
- **权限**：免确认只能由玩家在 `/wk` 窗口中按类别开启，Agent 无法更改。其他玩家发来的提案始终需要确认。
- **接入 Agent**：安装了无限工坊时，已启用扩展的能力由 App 转成 MCP 工具；没有无限工坊时照常运行，其他插件可以通过 Lua 接口直接调用。
- **应用**：在游戏外听游戏只走应用。应用声明听哪些来源（聊天频道、游戏动态、任务指引、总线事件）、看哪些状态面（玩家、队伍、当前任务步骤、今天的进度）、怎么攒成唤醒、玩家能下什么指令；`/wk` 里每个应用一张卡片，「交给 AI」复制启动语，由 Agent 照技能驱动；无限工坊的本机扩展也可以带应用。

扩展框架是可选插件，无限工坊不会自动安装它。

## 内置扩展

| 扩展 | 能力 |
|---|---|
| 调校 | 系统设置（按设置面板中的名称查找与修改）、按键、宏、编辑模式布局、天赋配置、装备方案、背包整理、插件启用与停用；配置档的保存、应用与分享 |
| 聊天 | 来源 `chat`：公会、小队、团队、密语等频道；发送消息 |
| 游戏动态 | 来源 `game`：战斗、光环、成长、任务、旅行、公会；状态面 `today`：今天的进度 |
| 任务指引 | 来源与状态面 `route`：玩家现在要做的一步，按标准形状给出；内置提供者「游戏自带」读任务追踪，第三方指引插件经适配器接入 |
| 角色信息 | 角色、位置、背包、任务、专业、声望、货币、队伍；状态面 `group` |
| 图鉴 | 记下登录过的角色；`/wk codex` 导出链接，导入无限图鉴的「我的角色」 |
| 界面指引 | 高亮界面元素、显示说明、标记地图、分步讲解 |
| 数据 | 在本机保存记录 |
| 远程 | 向队友和公会成员发送调校类提案；默认不接收其他玩家的提案 |

核心自己登记状态面 `me`（玩家的名字、称呼、等级、职业、区域、战斗、经验等）。

自带应用：公会聊天（`guild`），用玩家自己的角色参与公会聊天，由 AI 对话照技能 `guild-chat` 驱动。

自定义扩展「任务指引适配」（`WuxianKit_Guides`，单独的插件）：把 RestedXP 接到任务指引上。装了 RestedXP 的玩家另装它。

## 安装

在无限工坊 App 的「扩展」页安装；或从[扩展目录](https://wuxianwow.com/workshop/extensions)下载 zip，解压到游戏目录的 `Interface\AddOns`。首次安装后完整重启游戏；之后的更新按 App 的提示重载界面，新增了文件时需完整重启。游戏中输入 `/wk` 打开窗口。

## 开发扩展与应用

[`WuxianKit/ARCHITECTURE.md`](WuxianKit/ARCHITECTURE.md) 说明分层（零件、成品、运行时）、扩展的写法、五类能力、Setting、来源与状态面、提案、Agent 接入、应用（含无限工坊本机扩展带的应用）、任务指引与适配器，以及怎样让已有插件成为扩展。给 Agent 的总览见 [`WuxianKit/AGENT.md`](WuxianKit/AGENT.md)；交给 Agent 的开发做法见 `WuxianKit/skills/`（`kit-extension.md` 写扩展、`kit-app.md` 写应用）。

```
WuxianKit/                 插件本身（Interface\AddOns\WuxianKit）
  WuxianKit.toc  Bindings.xml  Media/  AGENT.md  ARCHITECTURE.md  skills/
  Core/                    核心（运行时）
    Locale.lua             核心的中英文字
    Kit.lua                公共表 WuxianKit：文字与语言、总线、载入 / 登录 / 退出钩子
    Schema.lua             参数声明与校验
    Extension.lua          扩展对象与生命周期、存储、游戏事件、定时器、选项、命令、来源、状态面
    Kinds.lua              五类能力与 Setting；Call / Propose；清单与修订号
    Digest.lua             摘要：条目攒成唤醒、租期、回看
    Proposals.lua          提案：预览、执行、战斗中排队、等待生效、快照撤销、执行前取消、免确认
    Comm.lua               玩家客户端之间的插件消息（WuxianKit.Comm）
    Bridge.lua             经无限工坊的开发组件（WoWBridge）交给 Agent
    UI/                    提案窗口、扩展框架窗口（/wk）、应用卡片、样式
    Builtins.lua           核心自己的扩展 kit：扩展开关、提案查询、撤销、清单；来源 bus、状态面 me
    Apps/                  应用运行时（Decl、Deliver、Run、Api 四个文件）：kit.app.*、WuxianKit:App
  Extensions/<名称>/        内置扩展（零件）：代码、AGENT.md、skills/；Route/ 是任务指引
  Apps/<名称>/              自带应用（成品）：Guild/（公会聊天：App.lua、skills/guild-chat.md）
WuxianKit_Guides/          自定义扩展「任务指引适配」（单独的插件）：Guides.lua、RestedXP.lua
tests/                     在 Lua 5.1（lupa）模拟的客户端里测试
tools/install.py           装进游戏
tools/package.py           打包成 zip，并把条目写进扩展目录 extensions.json
```

## 测试与打包

```
pip install lupa
python -m unittest discover -s tests -t tests
```

`tests/test_agent.py` 经无限工坊的开发组件做端到端测试，需要无限工坊的源码和它的 Python 环境：环境变量 `WUXIAN_WORKSHOP` 指向源码，并用无限工坊的 Python 运行测试；否则跳过。

- `python tools/install.py [--game <游戏目录>]`：装进游戏，替换整个插件文件夹。新增或移动了文件要完整重启游戏，只改 .lua 时重载即可。
- `python tools/package.py [--out <目录>] [--notes-zh "…"] [--notes-en "…"]`：生成 `WuxianKit-<版本>.zip`，并把条目写进该目录的 `extensions.json`（默认 `dist/`）。条目取自 .toc 和测试客户端里的清单。版本号只在 .toc 里改；发布过的版本不再更换文件。

## 约定

- 代码注释用英文。给玩家看的文字写中英两份（核心在 `Core/Locale.lua`，扩展用 `Kit:Words`）；给 Agent 的说明和报错用英文。
- 不模拟输入、不读内存、不注入代码。施法、使用物品、摆放动作条等受保护操作不做，由指引类标出位置，玩家自己操作。
- 不读机密值。
- 关闭无限工坊的热加载后（无限工坊 0.9.7 起），Agent 只能调用插件公开的能力；热加载开着时，Agent 可以执行任意代码，权限只是约定。

## 许可证

[MIT](LICENSE)

---

## English

WuxianKit is an extension framework for World of Warcraft: Wuxian addons that work with an AI agent. Addons declare what they can do as capabilities, and the agent uses them through [Wuxian Workshop](https://wuxianwow.com/workshop). Changes to the game are previewed in the game, run only when the player confirms, and can be undone.

- **Parts, products, runtime**: an extension is a part. It declares capabilities in five kinds (Read, Store, Guide, Send and Change), sources (items apps can hear), facets (how things stand now, which apps see) and events, with an `AGENT.md` for the agent. An app is a product: a declaration an agent drives by following a skill. The core is the runtime: confirmation, undo, permissions, the window and running apps. Apps use extensions; extensions do not know about apps.
- **Facts in the kit, words in the app**: what happens (sources) and how things stand (facets) come from the kit; whether, when and how to speak is the app's. The core knows no third-party addon: such addons plug into the kit's interfaces through adapters in custom extensions.
- **Proposals**: Send and Change make proposals, previewed step by step in the game and run when the player confirms. A snapshot taken before they run makes them undoable. Several changes can form one proposal, run and undone as one.
- **Permissions**: only the player can pre-approve a category, in the `/wk` window; the agent cannot. Proposals from other players and shared profiles always need the player's click. With hot loading off in Wuxian Workshop (0.9.7 or later) the agent can only call what addons expose; with it on, the agent can run any code, and these permissions are a convention.
- **The agent**: with Wuxian Workshop, the capabilities of enabled extensions become MCP tools. Without it, WuxianKit still runs, and other addons can call it through its Lua API.
- **Apps**: outside the game, the game is heard only through apps. An app declares the sources it hears (chat channels, game events, the quest guide, bus events), the facets it sees (the player, the group, the quest step now, the day so far), how items are gathered into wakes and the player's commands. Each app has a card in `/wk`: 交给 AI (Hand to AI) copies its start line for an AI client. A local extension of Wuxian Workshop can bring apps too.

WuxianKit is optional: Wuxian Workshop does not install it.

Built-in extensions: Tune (the game's settings, found by their names in the Settings panel; key bindings, macros, Edit Mode layouts, talent loadouts, equipment sets, bag sorting, addons on or off, profiles), Chat (sending, and the source `chat`), Game events (the source `game`, the facet `today`), Quest guide (the source and facet `route`: the step the player is on, from the game's own quest tracking or from a guide addon through an adapter), Character info (and the facet `group`), Codex, UI guide, Data, and Remote (tune proposals between players; accepting them is off by default). The core registers the facet `me`. Built-in app: Guild chat (`guild`), driven by an AI conversation that follows the skill `guild-chat`. A custom extension in its own addon, Quest guide adapters (`WuxianKit_Guides`), plugs RestedXP into the quest guide.

Install it from the Extensions page of the Wuxian Workshop app, or unzip the download from the [extension catalog](https://wuxianwow.com/workshop/extensions) into `Interface\AddOns` and restart the game. `/wk` opens its window.

To write an extension, see [`WuxianKit/ARCHITECTURE.md`](WuxianKit/ARCHITECTURE.md) (in Chinese) and [`WuxianKit/AGENT.md`](WuxianKit/AGENT.md). Tests: `pip install lupa`, then `python -m unittest discover -s tests -t tests`.

License: [MIT](LICENSE).
