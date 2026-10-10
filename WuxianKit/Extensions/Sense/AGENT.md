# Character info

Extension id `sense`. Reads the player's character. All tools are Read tools: they answer at once and change nothing,
so call them freely.

- `wk_sense_character`: name, realm, level, class, race, faction, experience, money, item level, specialization,
  guild.
- `wk_sense_position`: the map, zone and subzone, x and y on the map (0–100), the instance.
- `wk_sense_bags`: free and total slots; with `text`, e.g. `{"text": "potion"}`, the stacks whose item name holds it;
  without, the items summed, most first.
- `wk_sense_quests`: the quest log with each quest's objectives.
- `wk_sense_professions`, `wk_sense_reputation`, `wk_sense_currency`, `wk_sense_group`.

In combat and some restricted situations a few values are secret; they are left out, never guessed. Prefer these
tools to running Lua: they need no hot loading and answer the same way every time.
