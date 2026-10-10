# Data

Extension id `data`. Records kept on this computer, in WuxianKit's saved variables. Every tool acts at once; none is a
proposal, and a delete cannot be undone.

- `wk_data_put` with `{"key": "goals/today", "value": {"done": false}}`: saves a record, replacing one with the same key.
  A key is 1–64 bytes; use `topic/name` keys. A value is a string, number, boolean or a table of them: at most 64 KB a
  record and 1 MB in all.
- `wk_data_get` with `{"key": "goals/today"}`: `{key, value, bytes}`, or only `{key}` when there is no such record.
- `wk_data_list` with `{"prefix": "goals/"}`: the keys and their sizes, without values.
- `wk_data_delete` with `{"key": "goals/today"}`: deletes it; answers whether there was one.
- The game writes records to disk at logout or a UI reload; if the game crashes first, the latest changes are lost.
- Keep what helps between sessions (the player's goals, a checklist). Keep nothing private about other players.
