# Data

Keeps records on this computer, in the game's saved variables: `wk_data_put`, `wk_data_get`, `wk_data_list`,
`wk_data_delete`.

- A key is 1–64 bytes; use `name/thing` to keep things apart. A value is a string, a number, a boolean or a table of
  them: at most 64 KB a record and 1 MB in all.
- The game writes records to disk when the player logs out or reloads.
- Keep what you need between sessions (the player's goals, a checklist). Keep nothing private about other players.
