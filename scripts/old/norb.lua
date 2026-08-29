require "/scripts/vec2.lua"
require "/scripts/util.lua"
require "/scripts/status.lua"
require "/scripts/activeitem/stances.lua"
require "/scripts/norbframe.lua"

function init()
    activeItem.setCursor("/cursors/reticle0.cursor")
    initStances()
    setStance("idle")

    storage.projectileIds = storage.projectileIds or {false, false, false, false, false, false}
    self.Magnorb = Magnorb:new()
    updateHand()
end

function update(dt, fireMode, shiftHeld)
    updateStance(dt)
    Magnorb.orbRotate(-self.aimAngle)
    self.Magnorb.cooldownTimer = math.max(0, self.Magnorb.cooldownTimer)
    self.Magnorb:update(dt, fireMode, shiftHeld)

    if self.Magnorb.shieldTransformTimer == 0 and fireMode == "primary" and self.lastFireMode ~= "primary" and self.Magnorb.cooldownTimer == 0 then
        local nextOrbIndex = nextOrb()
        if nextOrbIndex then
            fire(nextOrbIndex)
        end
    end
    self.lastFireMode = fireMode

    updateAim()
    updateHand()
end

function uninit()
    activeItem.setItemShieldPolys()
    activeItem.setItemDamageSources()
    status.clearPersistentEffects("magnorbShield")
    animator.stopAllSounds("shieldLoop")
end

function nextOrb()
    for i = 1, self.Magnorb.orbTotal do
        if not storage.projectileIds[i] then
            return i
        end
    end
end

function updateHand()
    local isFrontHand = (activeItem.hand() == "primary") == (mcontroller.facingDirection() < 0)
    animator.setGlobalTag("hand", isFrontHand and "front" or "back")
    activeItem.setOutsideOfHand(isFrontHand)
end

function fire(orbIndex)
    local params = copy(self.Magnorb.projectileParameters)
    params.powerMultiplier = activeItem.ownerPowerMultiplier()
    params.ownerAimPosition = activeItem.ownerAimPosition()
    local firePos = firePosition(orbIndex)
    if world.lineCollision(mcontroller.position(), firePos) then return end
    local projectileId = world.spawnProjectile(
        self.Magnorb.projectileType,
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

function firePosition(orbIndex)
    return vec2.add(mcontroller.position(), activeItem.handPosition(animator.partPoint("orb"..orbIndex, "orbPosition")))
end

function aimVector(orbIndex)
    return vec2.norm(world.distance(activeItem.ownerAimPosition(), firePosition(orbIndex)))
end
