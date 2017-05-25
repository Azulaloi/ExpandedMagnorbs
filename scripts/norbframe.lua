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
    self.checkProjectiles()

    --Begin animating orbs
    animator.resetTransformationGroup("orbs")
    for i = 1, self.Magnorb.orbTotal do
        animator.setAnimationState("orb"..i, storage.projectileIds[i] == false and "orb" or "hidden")
    end
    setOrbPosition(1)
end

function Magnorb:update(dt, fireMode, shiftHeld)
    for _,ability in pairs(self.abilities) do
        ability:update(dt, fireMode, shiftHeld)
    end

    self.checkProjectiles()
end

function Magnorb:checkProjectiles()
    for i, projectileId in ipairs(storage.projectileIds) do
        if projectileId and not world.entityExists(projectileId) then
            storage.projectileIds[i] = false
        end
    end
end

function availableOrbCount()
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
    animator.rotateTransformationGroup("orbs", aimAngle or 0)
    for i = 1, config.getParameter("orbTotal"), 1 do
        animator.rotateTransformationGroup("orb"..i, (config.getParameter("orbitRate", 1) * -2 * math.pi) * dt)
     animator.setAnimationState("orb"..i, storage.projectileIds[i] == false and "orb" or "hidden")
   end
end



