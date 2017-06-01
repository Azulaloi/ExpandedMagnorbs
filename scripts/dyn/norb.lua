require "/scripts/vec2.lua"
require "/scripts/util.lua"
require "/scripts/status.lua"
require "/scripts/activeitem/stances.lua"
require "/scripts/dyn/norbframe.lua"

function init()
    activeItem.setCursor("/cursors/reticle0.cursor")
    initStances()
    setStance("idle")
    self.magnorb = Magnorb:new()

    local secondaryAbility = getAltAbility(self.magnorb.elementalType)
    if secondaryAbility then
        self.magnorb:addAbility(secondaryAbility)
    end

    updateHand()
end

function update(dt, fireMode, shiftHeld)
    updateStance(dt)

    self.magnorb.cooldownTimer = math.max(0, self.magnorb.cooldownTimer)
    self.magnorb:update(dt, fireMode, shiftHeld)

--    if self.magnorb.shieldTransformTimer == 0 and fireMode == "primary" and self.lastFireMode ~= "primary" and self.Magnorb.cooldownTimer == 0 then
--        local nextOrbIndex = nextOrb()
--        if nextOrbIndex then
--            fire(nextOrbIndex)
--        end
--    end
--    self.lastFireMode = fireMode

    updateAim()
    updateHand()
end

function uninit()
    activeItem.setItemShieldPolys()
    activeItem.setItemDamageSources()
    status.clearPersistentEffects("magnorbShield")
    animator.stopAllSounds("shieldLoop")
end

function updateHand()
    local isFrontHand = (activeItem.hand() == "primary") == (mcontroller.facingDirection() < 0)
    animator.setGlobalTag("hand", isFrontHand and "front" or "back")
    activeItem.setOutsideOfHand(isFrontHand)
end



function firePosition(orbIndex)
    return vec2.add(mcontroller.position(), activeItem.handPosition(animator.partPoint("orb"..orbIndex, "orbPosition")))
end

function aimVector(orbIndex)
    return vec2.norm(world.distance(activeItem.ownerAimPosition(), firePosition(orbIndex)))
end
