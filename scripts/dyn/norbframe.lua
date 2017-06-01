require "/scripts/vec2.lua"
require "/scripts/util.lua"
require "/scripts/status.lua"
require "/scripts/activeitem/stances.lua"

Magnorb = {}

function Magnorb:new(weaponConfig)
    local newMagnorb = weaponConfig or {}
    newMagnorb.projectileType = config.getParameter("projectileType")
    newMagnorb.projectileParameters = config.getParameter("projectileParameters")
    newMagnorb.projectileParameters.power = newMagnorb.projectileParameters.power * root.evalFunction("weaponDamageLevelMultiplier", config.getParameter("level", 1))
    newMagnorb.cooldownTime = config.getParameter("cooldownTime", 0)
    newMagnorb.cooldownTimer = newMagnorb.cooldownTime
    newMagnorb.orbTotal = config.getParameter("orbTotal")
    storage.projectileIds = storage.projectileIds or {false, false, false, false, false, false}
    if config.getParameter("shieldLock") then
        newMagnorb.lockValue = (newMagnorb.orbTotal) + 1
    else
        newMagnorb.lockValue = (newMagnorb.orbTotal)
    end
    if config.getParameter("shieldRotateValue") then
        newMagnorb.shieldRotate = tonumber(config.getParameter("shieldRotateValue"))
    else
        newMagnorb.shieldRotate = 0.7
    end
    if config.getParameter("shieldSpacingQ") then
        newMagnorb.spacingQ = tonumber(config.getParameter("shieldSpacingQ"))
    else newMagnorb.spacingQ = 1
    end
    newMagnorb.orbitRate = config.getParameter("orbitRate", 1) * -2 * math.pi

    newMagnorb.abilities = {}
    setmetatable(newMagnorb, extend(self))
    return newMagnorb
end

function Magnorb:init()
    --self.storage.projectileIds = self.storage.projectileIds or {false, false, false, false, false, false}
    self:checkProjectiles()

    --Begin animating orbs
    animator.resetTransformationGroup("orbs")
    for i = 1, self.orbTotal do
        animator.setAnimationState("orb"..i, storage.projectileIds[i] == false and "orb" or "hidden")
    end
    self:setOrbPosition(1)
end

function Magnorb:update(dt, fireMode, shiftHeld)
    for _,ability in pairs(self.abilities) do
        ability:update(dt, fireMode, shiftHeld)
    end

    self:checkProjectiles()

    if self.shieldTransformTimer == 0 and fireMode == "primary" and self.lastFireMode ~= "primary" and self.cooldownTimer == 0 then
        local nextOrbIndex = self:nextOrb()
        if nextOrbIndex then
            self:fire(nextOrbIndex)
        end
    end
    self.lastFireMode = fireMode

--    local angle = 0
--    if self.stance.aimAngle then
--        angle = self.stance.aimAngle
--    end

    --local angle = activeItem.aimAngle()
    --local angle = self.stances.aimAngle
    --local angle = updateAim.aimAngle
    self:orbRotate(0) --\  -angle
    --sb.logInfo(storage.projectileIds)
end

function Magnorb:checkProjectiles()
    for i, projectileId in ipairs(storage.projectileIds) do
        if projectileId and not world.entityExists(projectileId) then
            self.storage.projectileIds[i] = false
        end
    end
end

function Magnorb:availableOrbCount()
    local available = 0
    for i = 1, self.orbTotal do
        if not storage.projectileIds[i] then
            available = available + 1
        end
    end
    return available
end

function Magnorb:uninit()
    for _,ability in pairs(self.abilities) do
        if ability.uninit then
            ability:uninit(true)
        end
    end
end

function Magnorb:orbRotate(aimAngle)
    local dt = script.updateDt()
    animator.resetTransformationGroup("orbs")
    animator.rotateTransformationGroup("orbs", aimAngle or 0)
    for i = 1, config.getParameter("orbTotal"), 1 do
        animator.rotateTransformationGroup("orb"..i, (config.getParameter("orbitRate", 1) * -2 * math.pi) * dt)
        animator.setAnimationState("orb"..i, storage.projectileIds[i] == false and "orb" or "hidden")
   end
end

function Magnorb:nextOrb()
    for i = 1, self.orbTotal do
        if not storage.projectileIds[i] then
            return i
        end
    end
end

function Magnorb:setOrbPosition(spaceFactor, distance)
    for i = 1, self.orbTotal do
        animator.resetTransformationGroup("orb"..i)
        animator.translateTransformationGroup("orb"..i, {distance or 0, 0})
        animator.rotateTransformationGroup("orb"..i, 2 * math.pi * spaceFactor * ((i - 2) / self.orbTotal))
    end
end

function Magnorb:fire(orbIndex)
    local params = copy(self.Magnorb.projectileParameters)
    params.powerMultiplier = activeItem.ownerPowerMultiplier()
    params.ownerAimPosition = activeItem.ownerAimPosition()
    local firePos = firePosition(orbIndex)
    if world.lineCollision(mcontroller.position(), firePos) then return end
    local projectileId = world.spawnProjectile(
        self.projectileType,
        firePosition(orbIndex),
        activeItem.ownerEntityId(),
        aimVector(orbIndex),
        false,
        params
    )
    if projectileId then
        storage.projectileIds[orbIndex] = projectileId
        self.Magnorb.cooldownTimer = self.Magnorb.cooldownTime
        animator.playSound("fire")
    end
end

-- Must be a global, called from norb.lua
function getAbility(abilitySlot, abilityConfig)
    for _, script in ipairs(abilityConfig.scripts) do
        require(script)
    end
    local class = _ENV[abilityConfig.class]
    abilityConfig.abilitySlot = abilitySlot
    return class:new(abilityConfig)
end

-- Must be a global, called from norb.lua
function getAltAbility()
    local altAbilityConfig = config.getParameter("altAbility")
    if altAbilityConfig then
        return getAbility("alt", altAbilityConfig)
    end
end