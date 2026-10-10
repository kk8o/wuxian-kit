---
name: guide-tour
title: Guided UI tour
title-zh: 分步讲解界面
description: Walk the player through a part of the game's UI step by step, with highlights and short notes
description-zh: 用高亮和简短说明，一步步带玩家熟悉游戏界面的某个功能
arguments: topic
---
What to show: {{topic}}

1. Work out the steps, in order: what the player should look at or click. Usually 3 to 6 steps, at most 20.
2. Find the frame of each step: its global name (`CharacterMicroButton`, `PlayerFrame`, `Minimap`) or a path from one
   (`PlayerFrame.healthbar`). Do not guess names. To check a name: the workshop's `inspect` with `{"target": "<name>"}`
   (needs hot loading on), or `wk_guide_highlight` with `{"frame": "<name>", "seconds": 1}`: an unknown name fails with
   "no frame", and `shown: false` means it is hidden (ask the player to open its window first). A step without a frame
   shows mid-screen.
3. Start the tour: `wk_guide_tour` with a `title` and `steps` [{text, frame?}]. Each text is one or two short
   sentences that name the button or menu to use. The player moves on with Next. Example: `{"title": "Character
   window", "steps": [{"text": "Click this button to open your character window.", "frame": "CharacterMicroButton"},
   {"text": "Your item level is at the top."}]}`.
4. Follow it with `events`: `{"addon": "WuxianKit", "topic": "guide.tour", "since": -1, "wait": 120}`, then the same
   with `since` = the `next` of the answer, until a step's state is done or closed. Answer questions the player asks
   along the way.
5. When it is done or closed, `wk_guide_clear` puts away anything left.
6. For a place in the world, `wk_guide_waypoint` with x and y (0 to 100) on a map; `wk_sense_position` gives the map
   the player is on.

The guide changes nothing. For things no addon may do (casting, using items, placing action bar buttons), the steps
tell the player what to click. Keep tours short, and start one only when the player asked for it.
