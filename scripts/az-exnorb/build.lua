require "/scripts/util.lua"
require "/scripts/versioningutils.lua"

local MAGNABILITIES = "/scripts/az-exnorb/magnabilities.config"

local function setupMagnability(config, params, slot)
  local typeKey = slot .. "AbilityType"
  local abilityType = params[typeKey] or config[typeKey]

  local ability = {}
  if abilityType and abilityType ~= "none" then
    local path = root.assetJson(MAGNABILITIES)[abilityType]
    if not path then 
      sb.logError("buildnorb failed: unknown magnability type '%s'", abilityType)
    else
      ability = root.assetJson(path).ability
      ability.type = abilityType
    end
  end

  ability = sb.jsonMerge(ability, config[slot .. "Ability"] or {})
  ability = sb.jsonMerge(ability, params[slot .. "Ability"] or {})

  if ability.scripts then
    config[slot .. "Ability"] = ability
  end
end

-- Fill angle bracket placeholders
local function buildAbilityTooltip(ability)
  if not ability or not ability.tooltip then return nil end

  local tokens = {}
  local function gobble(prefix, tab)
    for k, v in pairs(tab) do
      local name = prefix and (prefix .. "." .. k) or k
      if type(v) == "table" then
        if k ~= "tooltip" then gobble(name, v) end
      elseif type(v) == "string" or type(v) == "number" then
        tokens[name] = tostring(v)
      end
    end
  end
  gobble(nil, ability)

  local tip = {}
  for field, text in pairs(ability.tooltip) do
    tip[field] = tostring(text):gsub("<([%w%.]+)>", function(name)
      return tokens[name] or ("<" .. name .. ">")
    end)
  end
  return tip
end

local function composeAltTooltip(fields, tip)
  fields.azSecondaryTitleLabel = tip.title or "Alt:"
  fields.azSecondaryLabel = tip.name or "<?>"
  if tip.cost ~= nil then
    fields.azSecondaryCostTitleLabel = tip.costTitle or "Alt Energy Cost:"
    fields.azSecondaryCostLabel = tip.cost or "<?>"
  end
  if tip.magnitude ~= nil then
    fields.azSecondaryMagnitudeTitleLabel = tip.magnitudeTitle or "Alt Strength:"
    fields.azSecondaryMagnitudeLabel = tip.magnitude or "<?>"
  end
end

function build(directory, config, params, level, seed)
  local configParam = function(keyName, defaultValue)
    if params[keyName] ~= nil then return params[keyName]
    elseif config[keyName] ~= nil then return config[keyName]
    else return defaultValue
    end
  end

  if level and not configParam("fixedLevel", true) then
    params.level = level
  end

  -- Fall back to default throw. `"primaryAbilityType": "none"` to force (will throw bracer.lua)
  config.primaryAbilityType = config.primaryAbilityType or "orbthrow"

  setupMagnability(config, params, "primary")
  setupMagnability(config, params, "alt")

  -- This wouldn't come up yet but I'm keeping it for future features (modular upgrades, random norbs)
  local elementalType = configParam("elementalType", "physical")
  replacePatternInData(config, nil, "<elementalType>", elementalType)

  -- Given that all sets currently have static levels, this is probably unnecessary, but I'm keeping it for future features (ancient anvil, modular upgrades, etc)
  config.damageLevelMultiplier = root.evalFunction("weaponDamageLevelMultiplier", configParam("level", 1))

  -- TODO: palette swaps, part offsets, buildrand etc, modules etc

  local fields = {
    orbTotalLabel = configParam("orbTotal"),
    hitDamageLabel = util.round(config.projectileParameters.power * config.damageLevelMultiplier, 1),
    levelLabel = configParam("level")
  }

  if elementalType ~= "physical" then
    fields.damageKindImage = "/interface/elements/" .. elementalType .. ".png"
  end

  -- TODO: manual overrides for tooltips, only implement if anything actually wants it during migration

  local tip = buildAbilityTooltip(config.altAbility)
  if tip then composeAltTooltip(fields, tip) end

  config.tooltipFields = fields
  config.price = (config.price or 0) * root.evalFunction("itemLevelPriceMultiplier", configParam("level", 1))

  return config, params
end