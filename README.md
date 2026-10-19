# NorgannonDB

An open, crowd-sourced game database for WoW Forever. It covers quests, NPCs, objects, items, loot,
vendors, spawns, zones and tracking categories, in an add-on that any other add-on can load.

- **Contract:** `SPEC.md` (schema 1.2), covering record shapes, coordinates, localization,
  player variants, corrections and the relation indexes.
- **Sources:** QuestieDB is the source of truth, and pfQuest fills the gaps. Players add sightings
  with the NorgannonDB Collector.
- **License:** GPL-3.0 (see `LICENSE` and `NOTICE.md`).

```lua
-- in your TOC:  ## Dependencies: NorgannonDB
local DB = NorgannonDB
if not DB or not DB:RequireSchema(1, 2) then return end
local quest = DB:Get("quests", 788)
```

Compiled by **Maro**.
