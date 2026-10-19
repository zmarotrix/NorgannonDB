-- Runs after all data and locale files.
local DB = NorgannonDB

DB:_UnpackProvenance()

DB.locale = GetLocale and GetLocale() or "enUS"
if DB.locale == "enGB" then DB.locale = "enUS" end

-- Faction and class are known at load time once a character is logged in. Neutral
-- characters (unchosen Pandaren-style starts) keep the base view until they pick a side.
local faction = UnitFactionGroup and UnitFactionGroup("player")
local class = UnitClassBase and UnitClassBase("player") or (UnitClass and select(2, UnitClass("player")))
if faction == "Alliance" or faction == "Horde" then
  DB:ApplyPlayerVariants(faction, class)
end

DB.loaded = true
DB:Fire("LOADED")
