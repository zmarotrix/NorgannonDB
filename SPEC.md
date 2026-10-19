# NorgannonDB data specification — schema 1.2

NorgannonDB is an addon-neutral game database: quests, NPCs, objects, items, loot, vendors,
spawns, area triggers, zones, maps, factions and tracking categories. Any addon may read it.
It ships no UI and needs no other addon.

This document is the contract. Field names, units and meanings below are stable within a
schema **major** version. Additive changes (new optional fields, new tables) bump the
**minor** version. Anything that changes or removes the meaning of an existing field bumps the
major version.

## 1. Loading and versioning

```lua
-- in your TOC:  ## OptionalDeps: NorgannonDB   (or ## Dependencies: NorgannonDB)
local DB = NorgannonDB
if not DB or not DB:RequireSchema(1, 1) then return end   -- major 1, at least minor 1
```

| Field | Meaning |
|---|---|
| `NorgannonDB.schema` | `{ major = 1, minor = 2 }` |
| `NorgannonDB.info` | `{ flavor, interface, build, generated, sources = { {name, version, commit, license} } }` |
| `NorgannonDB:RequireSchema(major, minMinor)` | `true` if this data can serve a consumer written for that version; otherwise `false, message` |
| `NorgannonDB:Get(kind, id)` | *(1.1)* the record with every field decoded; same table as `NorgannonDB[kind][id]` |
| `NorgannonDB:Peek(kind, id)` | *(1.1)* read-only view for bulk scans: a record not decoded yet comes back as a temporary copy and stays packed |
| `NorgannonDB:PeekLocale(kind, id)` | *(1.1)* the same for the active locale's entry (§4) |

Schema history: **1.2** quest `hidden` / `hiddenReason`, the `index` tables (hidden quests are left out of them). **1.1** packed records (§2 "Packed records"), `Get`, `Peek`, `PeekLocale`.

## 2. Conventions

* **IDs** are the game's own IDs: quest ID, creature entry, gameobject entry, item ID,
  AreaTable ID, faction ID, skill line ID, spell ID.
* **Zones** are AreaTable IDs (`areaId`), never UiMapIDs. Use `NorgannonDB.maps` to convert.
* **Coordinates** are percentages `0..100` of the zone's map **in the target client's map
  frame** (for Forever, the Forever map, which differs from Era in Mulgore, Eastern
  Plaguelands, Redridge Mountains and Stormwind City). `{-1, -1}` means "inside an instance in
  this zone, position unknown".
* **Spawn lists** (`SpawnList`): `{ [areaId] = { {x, y, respawn, phase}, ... } }`.
  `respawn` is seconds (`nil`/`0` = unknown). `phase` is an optional phase ID.
* **Waypoint lists**: `{ [areaId] = { { {x, y}, {x, y}, ... }, ... } }`, one array per path.
* **Faction reaction**: `"A"` friendly to Alliance, `"H"` friendly to Horde, `"AH"` friendly
  to both, `nil` hostile to both.
* **Masks**: `races` and `classes` are bitmasks; `nil` or `0` means "no restriction".
  Race bits are `NorgannonDB.enums.raceMaskById[raceId]` (UnitRace's 3rd return). Forever's race
  bits go above 2^32, so **test them with arithmetic, never with the 32-bit `bit` library**:
  `NorgannonDB.HasFlag(mask, flag)` does `mask % (2*flag) >= flag`.
* **Chances** are percentages (`12.5` = 12.5%). `0` means "drops, chance unknown or
  conditional".
* **Lists** are plain Lua arrays. Absent means empty. Records never contain empty tables.
* Records are shared, read-only tables. Copy before mutating, or use corrections (§6).

**Packed records** *(1.1)*. `quests`, `npcs`, `objects`, `items` and the active locale's
`quests` hold every ID as a real table, so `NorgannonDB.npcs[id]`, `pairs(NorgannonDB.npcs)` and
`record.field` work as before. To keep memory low, a record's `name` is stored as is and its
other fields are decoded the first time any of them is read; the decoded record then stays.
What this means for consumers:

* Iterating a whole kind and reading only `name` (or `NorgannonDB:L(kind, id)`) decodes nothing.
* `pairs(record)` / `next(record)` on a record none of whose other fields has been read yet
  only sees `name`. Call `NorgannonDB:Get(kind, id)` first when you iterate a record's fields.
* For scans that read more than `name` from many records once (building your own index), use
  `NorgannonDB:Peek(kind, id)`: it does not keep the decoded records in memory.
* `NorgannonDB.provenance[kind][id]` can still be read but cannot be iterated; use
  `GetProvenance`.

## 3. Entities

### 3.1 `NorgannonDB.quests[questId]`

| Field | Type | Meaning |
|---|---|---|
| `name` | string | enUS title (localized in `locales`) |
| `level` | number | quest level (`-1` = scales with player) |
| `minLevel`, `maxLevel` | number | player level window |
| `races`, `classes` | mask | allowed races / classes |
| `zoneOrSort` | number | `>0` areaId the quest belongs to, `<0` QuestSort (class/profession/holiday category) |
| `starters` | `{ npcs={}, objects={}, items={} }` | who/what starts it |
| `finishers` | `{ npcs={}, objects={} }` | who/what completes it |
| `objectives` | Objectives | see below |
| `text` | `{ objectives = {lines}, description = string }` | enUS quest text (`$N`, `$C`, `$R`, `$B`, `$G` tokens kept) |
| `sourceItem` | itemId | item handed out by the starter |
| `requiredItems` | {itemId} | items needed to start / that are not objectives |
| `prerequisites` | `{ all = {questIds}, any = {questIds} }` | all of `all` and one of `any` must be complete |
| `exclusiveTo` | {questIds} | completing/taking one of these locks this quest |
| `inGroupWith` | {questIds} | quests of the same group |
| `childQuests` | {questIds} | quests this unlocks |
| `nextQuestInChain`, `parentQuest` | questId | chain links |
| `breadcrumbFor` / `breadcrumbs` | questId / {questIds} | optional lead-in quests |
| `availableStartingWith` | questId | becomes available while that quest is active or done |
| `availableUntilCompleted` | questId | unavailable once that quest is done |
| `disabledByQuest` | questId | unavailable while that quest is active |
| `requiredSkill` | `{skillId, value}` | profession requirement |
| `requiredRanks` | `{ {skillId, value}, ... }` | alternative profession ranks |
| `requiredMinRep`, `requiredMaxRep` | `{factionId, value}` | reputation window |
| `requiredSpell`, `requiredSpecialization` | id | |
| `flags`, `specialFlags` | mask | QuestFlags / special flags (repeatable=1, event=2, monthly=4, ...) |
| `event` | true | seasonal / world-event quest |
| `hidden` | `true` \| `"map"` | *(1.2)* `true`: not obtainable in the game; never offer it (search, map, available quests). `"map"`: real, but don't show it as available on the map |
| `hiddenReason` | string | *(1.2)* `"questie"` (Questie's blacklist), `"notInQuestie"` (only in pfQuest's client-file data: cut or unconfirmed), `"placeholder"` (`<UNUSED>`, `<NYI>`, ...) |
| `rewards` | Rewards | see below |

**Objectives**

| Field | Type | Meaning |
|---|---|---|
| `npcs` | `{ {id, text, icon}, ... }` | kill / talk to |
| `objects` | `{ {id, text, icon}, ... }` | interact |
| `items` | `{ {id, text, icon}, ... }` | collect |
| `reputation` | `{factionId, value}` | reach standing |
| `killCredit` | `{ {npcs = {ids}, credit = npcId, text, icon}, ... }` | any of `npcs` gives credit for `credit` |
| `spells` | `{ {id, text, item}, ... }` | cast spell (optionally using item) |
| `areaTriggers` | {triggerIds} | explore (see `areaTriggers`) |
| `zones` | {areaIds} | use quest item somewhere in that area |
| `useItemOn` | `{ [itemId] = { npcs = {[npcId]=spellId}, objects = {[objectId]=spellId} } }` | item must be used on targets |
| `explore` | `{ text, spawns = SpawnList }` | completion trigger location |
| `extra` | `{ {spawns, icon, text, index, references}, ... }` | hidden/special objectives |

| `order` | `{ {kind, index}, ... }` | the client's objective index order, e.g. `{ {"items",1}, {"npcs",1} }`: quest-log objective *n* is `objectives[order[n][1]][order[n][2]]`. Absent when there is at most one objective (the order is then trivial) |

`text` and `icon` inside objective entries are optional overrides.

**Rewards**: `{ xp = number, xpLevel = number, reputation = { {factionId, value}, ... }, items = {itemIds} }`.
`items` lists every item this quest can reward (fixed or choice).

### 3.2 `NorgannonDB.npcs[npcId]`

| Field | Type | Meaning |
|---|---|---|
| `name`, `subName` | string | enUS name and title (e.g. "Weapon Vendor") |
| `minLevel`, `maxLevel` | number | |
| `rank` | number | 0 normal, 1 elite, 2 rare elite, 3 boss, 4 rare |
| `factionTemplate` | number | FactionTemplate ID |
| `reaction` | "A"/"H"/"AH"/nil | see §2 |
| `flags` | mask | NPC flags (`NorgannonDB.enums.npcFlags`) |
| `zone` | areaId | zone where it is most common |
| `spawns` | SpawnList | |
| `waypoints` | WaypointList | patrol paths |
| `respawn` | number | typical respawn seconds |
| `questStarts`, `questEnds` | {questIds} | |
| `sells` | `{ [itemId] = count }` | vendor stock (0 = unlimited/unknown) |
| `drops` | `{ [itemId] = chance }` | loot (direct; see also `lootTables`) |

### 3.3 `NorgannonDB.objects[objectId]`

`name`, `zone`, `spawns`, `waypoints` (transports), `factionTemplate`, `reaction`,
`questStarts`, `questEnds`, `respawn`, `drops = { [itemId] = chance }`.

### 3.4 `NorgannonDB.items[itemId]`

| Field | Type | Meaning |
|---|---|---|
| `name` | string | enUS name |
| `level`, `requiredLevel` | number | item level, level to use |
| `class`, `subClass` | number | ItemClass / subclass |
| `flags`, `foodType`, `ammoType` | number | |
| `startQuest` | questId | quest started by this item |
| `teachesSpell` | spellId | |
| `relatedQuests` | {questIds} | quests that involve the item |
| `rewardOf` | {questIds} | quests that reward it |
| `drops` | `{ npcs = {[npcId]=chance}, objects = {[objectId]=chance}, items = {[containerItemId]=chance}, lootTables = {[tableId]=chance} }` | where it comes from |
| `vendors` | `{ [npcId] = count }` | who sells it (0 = unlimited/unknown) |

`npcs[].drops`, `objects[].drops` and `npcs[].sells` are the same data indexed the other way.

### 3.5 Other tables

| Table | Shape | Meaning |
|---|---|---|
| `lootTables[id]` | `{ npcs = {ids}, objects = {ids} }` | shared reference loot tables |
| `areaTriggers[id]` | `{ spawns = SpawnList }` | exploration triggers |
| `zones[areaId]` | `{ name, parent, uiMapId, center = {x, y}, extent = {w, h} }` | `parent` = parent zone of a subzone; `center`/`extent` locate a subzone on its parent's map (percent) |
| `maps.areaToUiMap[areaId]`, `maps.uiMapToArea[uiMapId]` | number | AreaTable <-> UiMap |
| `maps.instanceToArea[instanceId]` | areaId | |
| `dungeons[areaId]` | `{ name, altAreaIds, parent, entrances = { {areaId, x, y} } }` | |
| `factionTemplates[id]` | number | reaction code (Questie encoding) |
| `professions[skillId]` | string | enUS skill line name |
| `categories[name]` | `{ npcs = {[id]=value}, objects = {[id]=value} }` | tracking lists, see below |
| `enums` | table | named constants: `raceMaskById`, `classKeys`, `npcFlags`, `questFlags`, `specialFlags`, `factionIDs`, `zoneIDs`, `sortKeys`, ... |
| `index.objectiveOf.npcs/objects/items[id]` | {questIds} | *(1.2)* quests this NPC, object or item is an objective of (kill credit included) |
| `index.zones[areaId]` | `{ npcs, objects, quests }` | *(1.2)* what spawns in the zone, and quests that start there or are sorted there |
| `index.unlocks[questId]` | {questIds} | *(1.2)* quests that list this one as a prerequisite |
| `index.hiddenQuests[questId]` | `true` \| `"map"` | *(1.2)* the quests' `hidden` flags, readable without decoding records |
| `legacy.minimapSize[areaId]` | `{width, height}` | Era zone size in yards (unreliable for changed zones) |

**Categories** — `value` is a required skill (`herbs`, `mines`, `fish`), a level (`rares`) or a
reaction code (`flight`, `innkeeper`, `vendor`, `repair`, `banker`, `auctioneer`,
`stablemaster`, `battlemaster`, `spirithealer`, `mailbox`, `meetingstone`, `trainer`,
`chests`).

## 4. Localization — `NorgannonDB.locales[locale]`

Only the client's locale is loaded. enUS lives in the base records.

```lua
locales.deDE = {
  quests  = { [id] = { name = "...", objectives = {lines}, description = "..." } },
  npcs    = { [id] = { name = "...", subName = "..." } },
  objects = { [id] = "name" },  items = { [id] = "name" },
  zones   = { [id] = "name" },  professions = { [id] = "name" },
}
```

`NorgannonDB:L(kind, id, field)` returns the localized value with enUS fallback.

## 5. Player-dependent variants

A few corrections depend on the player (for example a quest with a different starter for
Horde). The base records are the Alliance/Warrior view. `NorgannonDB.variants` holds field
overrides:

```lua
variants = {
  base    = { faction = "Alliance", class = "WARRIOR" },
  faction = { Horde = { quests = { [id] = { field = value | NorgannonDB.REMOVED } }, npcs = ... } },
  class   = { MAGE  = { quests = { ... } } },
}
```

At load NorgannonDB applies the player's overrides to the base records (`NorgannonDB.appliedVariants`
says which). Addons that need the neutral data call `NorgannonDB:GetVariantOverrides(axis, value)`.

## 6. Corrections (runtime additions)

Addons and data collectors may add or fix records without editing data files:

```lua
NorgannonDB:RegisterCorrection("MyAddon", "npcs", 1234, { spawns = { [12] = { {40.1, 52.3} } } })
NorgannonDB:RegisterCallback("CORRECTION_APPLIED", function(kind, id, owner) ... end)
```

Corrections merge field by field (a field is replaced, never deep-merged).
`NorgannonDB:GetProvenance(kind, id)` reports where a record came from: `"questie"`,
`"pfquest"`, `"questie+pfquest"`, or the owner of the last correction.

## 7. Sources and precedence

The data is compiled offline by `tools/norgannondb/build.py`:

1. **QuestieDB** (GPL-3.0), loaded through its own code so all of its corrections apply. It
   is the source of truth: any field it provides wins.
2. **pfQuest** (MIT) fills fields QuestieDB lacks: drop chances, respawn timers,
   reference loot tables, area triggers, tracking categories, quest descriptions, vendor stock
   counts. pfQuest coordinates are projected into the target client's map frame first.
3. If QuestieDB lists an item's drop or vendor sources, that list is authoritative and pfQuest
   only adds chances. pfQuest's lists are used only where QuestieDB has none.
4. Entities only pfQuest knows are kept and marked `"pfquest"` in provenance. Consumers decide
   whether to trust them (the pfQuest adapter skips pfQuest-only quests).

Because it includes QuestieDB data, the compiled database is distributed under **GPL-3.0**.

A JSON export with the same structure (string keys) is written to `dist/json/` for
non-Lua tools.
