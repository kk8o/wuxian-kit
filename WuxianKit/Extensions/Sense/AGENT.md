# Character info

Extension id `sense`. Reads the player's character. All tools are Read tools: they answer at once and change nothing,
so call them freely.

- `wk_sense_character`: name (whole, as others address the player), realm, level, class, race, faction, experience,
  money, item level, specialization, guild.
- `wk_sense_position`: the map, zone and subzone, x and y on the map (0–100), the instance.
- `wk_sense_bags`: free and total slots; with `text`, e.g. `{"text": "potion"}`, the stacks whose item name holds it;
  without, the items summed, most first.
- `wk_sense_quests`: the quest log with each quest's objectives.
- `wk_sense_professions`, `wk_sense_reputation`, `wk_sense_currency`, `wk_sense_group`.
- `wk_sense_guild`: the player's guild: `name`, `rank` (the player's), `motd`, `total` and `online` member counts,
  `classes` (`{"MAGE": 3, ...}`, of those online) and `levels` (`avg`, `median`, `atMax`: how many are at the level cap,
  of those online), and `members`: the online members `{name, level, class, zone, rank, online}`, highest level first,
  at most `limit` (default 100, up to 300); `{"members": false}` leaves the list out. `name` is whole, as for a whisper.
  Not in a guild: `{"guild": false}`. Guild notes are never read. The roster is the one the client has; right after
  login it may be incomplete for a moment.

In combat and some restricted situations a few values are secret; they are left out, never guessed. Prefer these
tools to running Lua: they need no hot loading and answer the same way every time.
