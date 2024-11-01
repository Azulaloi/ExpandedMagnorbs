require "/scripts/vec2.lua"
require "/scripts/util.lua"
require "/scripts/status.lua"
require "/scripts/activeitem/stances.lua"

function init()
    activeItem.setCursor("/cursors/reticle0.cursor")

    self.projectileType = config.getParameter("projectileType")
    self.projectileParameters = config.getParameter("projectileParameters")
    self.projectileParameters.power = self.projectileParameters.power * root.evalFunction("weaponDamageLevelMultiplier", config.getParameter("level", 1))
    self.cooldownTime = config.getParameter("cooldownTime", 0)
    self.cooldownTimer = self.cooldownTime
    self.orbTotal = config.getParameter("orbTotal")
    self.level = config.getParameter("level")
    self.shieldEnergyCost = config.getParameter("shieldEnergyCost", 50)

    initStances()
    storage.projectiles = storage.projectiles or {}
    storage.projectileIds = storage.projectileIds or {false, false, false, false, false}
    checkProjectiles()

    storage.portalIds = storage.portalIds or {}
    self.portalActive = false
    checkPortals()

    storage.portalProjectileIds = storage.portalProjectileIds or {false, false, false, false, false}

    self.orbitRate = config.getParameter("orbitRate", 1) * -2 * math.pi

    animator.resetTransformationGroup("orbs")
    for i = 1, self.orbTotal do
        animator.setAnimationState("orb"..i, storage.projectileIds[i] == false and "orb" or "hidden")
    end
    setOrbPosition(1)

    setStance("idle")

    updateHand()

  --  message.setHandler("spawnPortalNorb", function(_,_, projectileId, index)
   --     storage.portalProjectileIds[index] = projectileId
   -- end)
end

function update(dt, fireMode, shiftHeld)
    self.cooldownTimer = math.max(0, self.cooldownTimer)

    updateStance(dt)
    checkProjectiles()
    checkPortals()

    if fireMode == "alt" and not status.resourceLocked("energy") then
        if not self.portalActive then
            activatePortal()
        end
    end

    if fireMode == "primary" and self.lastFireMode ~= "primary" and (self.cooldownTimer == 0) and not self.portalActive then
        local nextOrbIndex = nextOrb()
        if nextOrbIndex then
            fire(nextOrbIndex)
        end
    end
    self.lastFireMode = fireMode

    if self.portalActive then
        updateProjectiles()
    end

    animator.resetTransformationGroup("orbs")
    animator.rotateTransformationGroup("orbs", -self.armAngle or 0)
    for i = 1, self.orbTotal do
        animator.rotateTransformationGroup("orb"..i, self.orbitRate * dt)
        animator.setAnimationState("orb"..i, storage.projectileIds[i] == false and "orb" or "hidden")
    end


    updateAim()
    updateHand()
end

function uninit()
    local id = storage.portalIds[1]
    if id then
        if world.entityExists(id) then
            world.sendEntityMessage(id, "kill")
        end
    end

    activeItem.setItemShieldPolys()
    activeItem.setItemDamageSources()
end

function nextOrb()
    for i = 1, self.orbTotal do
        if not storage.projectileIds[i] then
            return i
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

function updateHand()
    local isFrontHand = (activeItem.hand() == "primary") == (mcontroller.facingDirection() < 0)
    animator.setGlobalTag("hand", isFrontHand and "front" or "back")
    activeItem.setOutsideOfHand(isFrontHand)
end

function fire(orbIndex)
    local params = copy(self.projectileParameters)
    params.powerMultiplier = activeItem.ownerPowerMultiplier()
    params.ownerAimPosition = activeItem.ownerAimPosition()
    local firePos = firePosition(orbIndex)
    if world.lineCollision(mcontroller.position(), firePos) then return end
    local projectileId = world.spawnProjectile(
        self.projectileType .. orbIndex,
        firePosition(orbIndex),
        activeItem.ownerEntityId(),
        aimVector(orbIndex),
        false,
        params
    )
    if projectileId then
        storage.projectileIds[orbIndex] = projectileId
        self.cooldownTimer = self.cooldownTime
        animator.playSound("fire")
    end
end

function firePosition(orbIndex)
    return vec2.add(mcontroller.position(), activeItem.handPosition(animator.partPoint("orb"..orbIndex, "orbPosition")))
end

function aimVector(orbIndex)
    return vec2.norm(world.distance(activeItem.ownerAimPosition(), firePosition(orbIndex)))
end

function checkProjectiles()
    for i, projectileId in ipairs(storage.projectileIds) do
        if projectileId and not world.entityExists(projectileId) then
            storage.projectileIds[i] = false
        end
    end
end

function checkPortals()
    for i, portalId in ipairs(storage.portalIds) do
        if portalId and not world.entityExists(portalId) then
            self.portalActive = false
            storage.portalIds[i] = false
        end
    end
end

function setOrbPosition(spaceFactor, distance)
    for i = 1, self.orbTotal do
        animator.resetTransformationGroup("orb"..i)
        animator.translateTransformationGroup("orb"..i, {distance or 0, 0})
        animator.rotateTransformationGroup("orb"..i, 2 * math.pi * spaceFactor * ((i - 2) / self.orbTotal))
    end
end

function setOrbAnimationState(newState)
    for i = 1, self.orbTotal do
        animator.setAnimationState("orb"..i, newState)
    end
end

function activatePortal()
    self.portalActive = true
    animator.playSound("shieldOn")
    animator.playSound("shieldLoop", -1)
    if targetValid(activeItem.ownerAimPosition())  then
        animator.playSound("fire")
        createProjectiles()
    else
        return
    end
end



function targetValid(aimPos)
    local focusPos = focusPosition()
    return --world.magnitude(focusPos, aimPos) <= self.maxCastRange
        --and
    not world.lineTileCollision(mcontroller.position(), focusPos)
            and not world.lineTileCollision(focusPos, aimPos)
end

function focusPosition()
    return vec2.add(mcontroller.position(), activeItem.handPosition(animator.partPoint("glove", "focalPoint")))
end

function createProjectiles()
    local aimPosition = activeItem.ownerAimPosition()
    local fireDirection = world.distance(aimPosition, focusPosition())[1] > 0 and 1 or -1
    local pOffset = {fireDirection * (self.projectileDistance or 0), 0}
    local basePos = activeItem.ownerAimPosition()

    local pCount = 1

    for i = 1, 1 do
        local projectileId = world.spawnProjectile(
            "rainbowportal",
            vec2.add(basePos, pOffset),
            activeItem.ownerEntityId(),
            pOffset,
            false,
            pParams
        )

        if projectileId then
            table.insert(storage.portalIds, projectileId)
            world.sendEntityMessage(projectileId, "updateProjectile", aimPosition)
        end

        pOffset = vec2.rotate(pOffset, (2 * math.pi) / pCount)
    end
end


function updateProjectiles()
    local aimPosition = activeItem.ownerAimPosition()
    local newProjectiles = {}
    for i = 1, 1 do
        if world.entityExists(storage.portalIds[1]) then
            local projectileResponse = world.sendEntityMessage(storage.portalIds[1], "updateProjectile", aimPosition)
            if projectileResponse:finished() then
                local newIds = projectileResponse:result()

                storage.portalProjectileIds = newIds
            end
        end
    end
end