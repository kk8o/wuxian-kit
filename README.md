# WuxianKit · 扩展框架

《魔兽世界：无限》插件的 Agent 接入框架。插件把功能声明为能力，AI Agent 经[无限工坊](https://wuxianwow.com/workshop)调用；更改游戏的操作在游戏中预览，玩家执行后生效，可以撤销。

[English](#english)

## 概述

- **声明能力**：扩展用 `WuxianKit:Extension` 声明能力（读取、存储、指引、发送、更改五类）和事件，并在插件文件夹里附一份给 Agent 的说明 `AGENT.md`。确认、撤销、权限和窗口由框架提供。
- **提案与撤销**：发送、更改类操作生成提案，在游戏中逐项预览，玩家执行后生效；执行前存快照，可以撤销。多项改动可以合成一个提案，一次执行，一次撤销。
- **权限**：免确认只能由玩家在 `/wk` 窗口中按类别开启，Agent 无法更改。其他玩家发来的提案始终需要确认。
- **接入 Agent**：安装了无限工坊时，已启用扩展的能力由 App 转成 MCP 工具；没有无限工坊时照常运行，其他插件可以通过 Lua 接口直接调用。

扩展框架是可选插件，无限工坊不会自动安装它。

## 内置扩展

| 扩展 | 能力 |
|---|---|
| 调校 | 系统设置（按设置面板中的名称查找与修改）、按键、宏、编辑模式布局、天赋配置、装备方案、背包整理、插件启用与停用；配置档的保存、应用与分享 |
| 聊天 | 收听公会、小队、团队、密语等频道；发送消息 |
| 角色信息 | 角色、位置、背包、任务、专业、声望、货币、队伍 |
| 图鉴 | 记下登录过的角色；`/wk codex` 导出链接，导入无限图鉴的「我的角色」 |
| 指引 | 高亮界面元素、显示说明、标记地图、分步讲解 |
| 数据 | 在本机保存记录 |
| 远程 | 向队友和公会成员发送调校类提案；默认不接收其他玩家的提案 |

## 安装

在无限工坊 App 的「扩展」页安装；或从[扩展目录](https://wuxianwow.com/workshop/extensions)下载 zip，解压到游戏目录的 `Interface\AddOns`。首次安装后完整重启游戏；之后的更新按 App 的提示重载界面，新增了文件时需完整重启。游戏中输入 `/wk` 打开窗口。

## 开发扩展

[`WuxianKit/ARCHITECTURE.md`](WuxianKit/ARCHITECTURE.md) 说明分层、扩展的写法、五类能力、Setting 与 Feed 两种模式、提案、Agent 接入，以及怎样让已有插件成为扩展。给 Agent 的总览见 [`WuxianKit/AGENT.md`](WuxianKit/AGENT.md)。

```
WuxianKit/                 插件本身（Interface\AddOns\WuxianKit）
  WuxianKit.toc  Bindings.xml  Media/  AGENT.md  ARCHITECTURE.md  skills/
  Core/                    核心
    Locale.lua             核心的中英文字
    Kit.lua                公共表 WuxianKit：文字与语言、总线、载入 / 登录 / 退出钩子
    Schema.lua             参数声明与校验
    Extension.lua          扩展对象与生命周期、存储、游戏事件、定时器、选项、命令
    Kinds.lua              五类能力、Setting 与 Feed 两种模式；Call / Propose；清单与修订号
    Proposals.lua          提案：预览、执行、战斗中排队、等待生效、快照撤销、执行前取消、免确认
    Comm.lua               玩家客户端之间的插件消息（WuxianKit.Comm）
    Bridge.lua             经无限工坊的开发组件（WoWBridge）交给 Agent
    UI/                    提案窗口、扩展框架窗口（/wk）、样式
    Builtins.lua           核心自己的扩展 kit：扩展开关、提案查询、撤销、清单
  Extensions/<名称>/        内置扩展：代码、AGENT.md、skills/
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

- **Capabilities** come in five kinds: Read, Store, Guide, Send and Change. An extension declares them with `WuxianKit:Extension`, together with its events and an `AGENT.md` for the agent; confirmation, undo, permissions and the window come from the framework.
- **Proposals**: Send and Change make proposals, previewed step by step in the game and run when the player confirms. A snapshot taken before they run makes them undoable. Several changes can form one proposal, run and undone as one.
- **Permissions**: only the player can pre-approve a category, in the `/wk` window; the agent cannot. Proposals from other players and shared profiles always need the player's click. With hot loading off in Wuxian Workshop (0.9.7 or later) the agent can only call what addons expose; with it on, the agent can run any code, and these permissions are a convention.
- **The agent**: with Wuxian Workshop, the capabilities of enabled extensions become MCP tools. Without it, WuxianKit still runs, and other addons can call it through its Lua API.

WuxianKit is optional: Wuxian Workshop does not install it.

Built-in extensions: Tune (the game's settings, found by their names in the Settings panel; key bindings, macros, Edit Mode layouts, talent loadouts, equipment sets, bag sorting, addons on or off, profiles), Chat, Character info, Guide, Data, and Remote (tune proposals between players; accepting them is off by default).

Install it from the Extensions page of the Wuxian Workshop app, or unzip the download from the [extension catalog](https://wuxianwow.com/workshop/extensions) into `Interface\AddOns` and restart the game. `/wk` opens its window.

To write an extension, see [`WuxianKit/ARCHITECTURE.md`](WuxianKit/ARCHITECTURE.md) (in Chinese) and [`WuxianKit/AGENT.md`](WuxianKit/AGENT.md). Tests: `pip install lupa`, then `python -m unittest discover -s tests -t tests`.

License: [MIT](LICENSE).
