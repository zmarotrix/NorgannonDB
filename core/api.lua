-- NorgannonDB public API. The data contract is documented in SPEC.md.
-- This file loads first; data files fill the tables it creates, core/finalize.lua runs last.

local SCHEMA_MAJOR, SCHEMA_MINOR = 1, 4

local DB = _G.NorgannonDB or {}
_G.NorgannonDB = DB

DB.schema = { major = SCHEMA_MAJOR, minor = SCHEMA_MINOR }
DB.REMOVED = DB.REMOVED or setmetatable({}, { __tostring = function() return "NorgannonDB.REMOVED" end })

DB.quests, DB.npcs, DB.objects, DB.items = DB.quests or {}, DB.npcs or {}, DB.objects or {}, DB.items or {}
DB.locales = DB.locales or {}

-------------------------------------------------------------------------------------------
-- Packed records (SPEC.md section 2): quests, npcs, objects and items are stored as `name`
-- plus their other fields as Lua table-constructor text, decoded on first access.
-------------------------------------------------------------------------------------------

local loadstring, setmetatable, rawget, rawset, pairs = loadstring, setmetatable, rawget, rawset, pairs
local pending = {}   -- record -> packed text, until the record is decoded

-- Decoded fields of a packed record as a new table (name excluded).
local function unpackFields(packed)
  local fields = assert(loadstring("return {" .. packed .. "}"))()
  -- spawn points leave out a respawn equal to the record's and write an unknown one as 0
  local respawn = fields.respawn
  if respawn and fields.spawns then
    for _, points in pairs(fields.spawns) do
      for _, p in pairs(points) do
        local r = p[3]
        if r == nil then p[3] = respawn elseif r == 0 then p[3] = nil end
      end
    end
  end
  return fields
end

local function decode(record)
  local packed = pending[record]
  if not packed then return end
  pending[record] = nil
  for field, value in pairs(unpackFields(packed)) do rawset(record, field, value) end
end

local PACKED = {
  __index = function(record, field)
    if pending[record] then
      decode(record)
      return rawget(record, field)
    end
  end,
}

---Used by the generated data files: returns R(id, name, packed) that registers one record
---in NorgannonDB[kind] (or in `kind` itself when it is a table, for locale quest entries).
function DB:_PackedLoader(kind)
  local target = type(kind) == "table" and kind or self[kind]
  return function(id, name, packed)
    local record = { name = name }
    if packed then
      setmetatable(record, PACKED)
      pending[record] = packed
    end
    target[id] = record
  end
end

---The record with every field decoded (same table as NorgannonDB[kind][id]), or nil.
function DB:Get(kind, id)
  local record = self[kind] and self[kind][id]
  if record and pending[record] then decode(record) end
  return record
end

-- A packed entry's fields as a temporary table; anything else is returned as is.
local function peek(entry)
  local packed = type(entry) == "table" and pending[entry]
  if not packed then return entry end
  local fields = unpackFields(packed)
  fields.name = rawget(entry, "name")
  return fields
end

---Read-only view of a record for bulk scans: a record that is not decoded yet is returned as a
---temporary copy and stays packed, so scanning every record does not keep them all in memory.
function DB:Peek(kind, id)
  return peek(self[kind] and self[kind][id])
end

---Like Peek, for the active locale's entry (SPEC.md section 4), or nil.
function DB:PeekLocale(kind, id)
  local loc = self:GetLocale()
  return peek(loc and loc[kind] and loc[kind][id])
end

local KINDS = {
  quests = true, npcs = true, objects = true, items = true, lootTables = true,
  areaTriggers = true, zones = true, dungeons = true,
}

---Returns true when this data can serve a consumer written for schema `major`.`minMinor`.
function DB:RequireSchema(major, minMinor)
  if major == SCHEMA_MAJOR and (minMinor or 0) <= SCHEMA_MINOR then
    return true
  end
  return false, string.format("NorgannonDB schema %d.%d installed, consumer needs %d.%d",
    SCHEMA_MAJOR, SCHEMA_MINOR, major or 0, minMinor or 0)
end

---Bit test that stays correct above 2^32 (Forever race masks); nil/0 masks mean "any".
function DB.HasFlag(mask, flag)
  if not mask or mask == 0 then return true end
  return mask % (2 * flag) >= flag
end

---Active locale table, or nil for enUS / missing locale files.
function DB:GetLocale()
  return self.locale and self.locales[self.locale]
end

---Localized value with enUS fallback.
---kind: "quests" (field: name/objectives/description), "npcs" (name/subName),
---"objects", "items", "zones", "professions" (name only).
function DB:L(kind, id, field)
  local loc = self:GetLocale()
  local entry = loc and loc[kind] and loc[kind][id]
  if entry ~= nil then
    if type(entry) ~= "table" then return entry end
    if field and entry[field] ~= nil then return entry[field] end
    if not field and entry.name ~= nil then return entry.name end
  end

  local base = self[kind] and self[kind][id]
  if type(base) ~= "table" then return base end
  if kind == "quests" and (field == "objectives" or field == "description") then
    return base.text and base.text[field]
  end
  return base[field or "name"]
end

---Variant overrides for one axis value (faction "Horde", class "MAGE", ...), or nil.
function DB:GetVariantOverrides(axis, value)
  return self.variants and self.variants[axis] and self.variants[axis][value]
end

-------------------------------------------------------------------------------------------
-- Callbacks
-------------------------------------------------------------------------------------------

local callbacks = {}

function DB:RegisterCallback(event, func)
  callbacks[event] = callbacks[event] or {}
  table.insert(callbacks[event], func)
end

function DB:Fire(event, ...)
  for _, func in ipairs(callbacks[event] or {}) do
    local ok, err = pcall(func, ...)
    if not ok and geterrorhandler then geterrorhandler()(err) end
  end
end

-------------------------------------------------------------------------------------------
-- Corrections and provenance
-------------------------------------------------------------------------------------------

local correctionOwners = {}
local SOURCE_NAMES = { [1] = "questie", [2] = "pfquest", [3] = "questie+pfquest" }

---Replace fields of one record; `fields` values of NorgannonDB.REMOVED delete a field.
---Creates the record when it does not exist yet.
function DB:RegisterCorrection(owner, kind, id, fields)
  assert(type(owner) == "string" and owner ~= "", "RegisterCorrection: owner required")
  assert(KINDS[kind], "RegisterCorrection: unknown kind " .. tostring(kind))
  assert(type(id) == "number" and type(fields) == "table", "RegisterCorrection: id and fields required")

  self[kind] = self[kind] or {}
  local record = self:Get(kind, id)
  if not record then
    record = {}
    self[kind][id] = record
  end
  for field, value in pairs(fields) do
    if value == self.REMOVED then
      record[field] = nil
    else
      record[field] = value
    end
  end

  correctionOwners[kind] = correctionOwners[kind] or {}
  correctionOwners[kind][id] = owner
  self:Fire("CORRECTION_APPLIED", kind, id, owner)
  return record
end

---"questie", "pfquest", "questie+pfquest", a correction owner, or nil.
function DB:GetProvenance(kind, id)
  local owner = correctionOwners[kind] and correctionOwners[kind][id]
  if owner then return owner end
  local code = self.provenance and self.provenance[kind] and self.provenance[kind][id]
  return code and SOURCE_NAMES[code]
end

-- data/provenance.lua stores a default code per kind and, for each other code, the IDs that
-- have it as one sorted string of 4-digit base-64 numbers ('(' = 0).
local byte, floor = string.byte, math.floor

local function hasPackedId(ids, id)
  local lo, hi = 1, #ids / 4
  while lo <= hi do
    local mid = floor((lo + hi) / 2)
    local a, b, c, d = byte(ids, mid * 4 - 3, mid * 4)
    local value = ((a - 40) * 64 + (b - 40)) * 4096 + (c - 40) * 64 + (d - 40)
    if value == id then return true end
    if value < id then lo = mid + 1 else hi = mid - 1 end
  end
  return false
end

---Makes NorgannonDB.provenance[kind][id] read like the full code table without storing it.
function DB:_UnpackProvenance()
  local packed = self.packedProvenance
  if not packed then return end
  self.packedProvenance = nil
  self.provenance = {}
  for kind, default in pairs(packed.default) do
    local records, except = self[kind], packed.except[kind] or {}
    self.provenance[kind] = setmetatable({}, {
      __index = function(_, id)
        if type(id) ~= "number" or not rawget(records, id) then return nil end
        for code, ids in pairs(except) do
          if hasPackedId(ids, id) then return code end
        end
        return default
      end,
    })
  end
end

-------------------------------------------------------------------------------------------
-- Variants
-------------------------------------------------------------------------------------------

local function applyOverrides(overrides)
  for kind, rows in pairs(overrides or {}) do
    local target = DB[kind]
    if target then
      for id, fields in pairs(rows) do
        if fields == DB.REMOVED then
          if target[id] then pending[target[id]] = nil end
          target[id] = nil
        else
          local record = DB:Get(kind, id)
          if not record then
            record = {}
            target[id] = record
          end
          for field, value in pairs(fields) do
            if value == DB.REMOVED then record[field] = nil else record[field] = value end
          end
        end
      end
    end
  end
end

---Apply the player's faction/class overrides once. Called by core/finalize.lua.
function DB:ApplyPlayerVariants(faction, class)
  if self.appliedVariants or not self.variants then return end
  local base = self.variants.base or {}
  if faction and faction ~= base.faction then
    applyOverrides(self:GetVariantOverrides("faction", faction))
  end
  if class and class ~= base.class then
    applyOverrides(self:GetVariantOverrides("class", class))
  end
  self.appliedVariants = { faction = faction, class = class }
end
