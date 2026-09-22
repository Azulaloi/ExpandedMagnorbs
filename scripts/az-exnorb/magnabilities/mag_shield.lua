require "/scripts/az-exnorb/magnability.lua"

MagShield = Magnability:new()

function MagShield:init()
  self.active = false
  self.shieldPoly = animator.partPoly("glove", "shieldPoly")
  if (self.shieldKnockback or 0) > 0 then
    self.damageSource = {
      poly = self.shieldPoly,
      damage = self.contactDamage or 0,
      damageType = self.doesDamage and "Damage" or "Knockback",
      sourceEntity = activeItem.ownerEntityId(),
      team = activeItem.ownerTeam(),
      knockback = self.shieldKnockback,
      rayCheck = true,
      damageRepeatTimeout = 0.5
    }
  end

  self.allHomeTime = 0
  self.allHomeSettle = 0.1 -- param
end

function MagShield:uninit()
  if self.active then self:release() end
end


-- TODO: test out vanilla shield behaviours
-- TODO: test out vanilla shield/block/parry ability behaviours
-- TODO: shields that do status effects etc, configurable damage type, etc

-- TODO: shield formation controls orb spinners
-- TODO: kick/wobble when hit, etc

-- TODO: special function when going from active with held alt to primary without release? "explosive unshield"?
-- TODO: pester sb modding discord to see if anyone has a clever fix for the input issue

function MagShield:update(dt)
  local altHeld = rig.input:held("alt")
  self.allHomeTime = allNorbsAreHome() and (self.allHomeTime + dt) or 0

  local wants = altHeld
    and self.allHomeTime > self.allHomeSettle
    and not status.resourceLocked("energy")
    and status.resourcePositive("shieldStamina")
  

  if wants and not self.active then
    self:engage() -- why colon
  elseif self.active then
    if not altHeld
      or not status.resourcePositive("shieldStamina")
      or not status.overConsumeResource("energy", (self.shieldEnergyCost or 50) * dt) then
      
      self:release()
    else
      self:holdUpdate(dt)
    end
  end


  if not self.active and not rig.formation and rig.orbVisualOverride == "unshield" then
    setOrbVisualOverride(nil)
  end
end

function MagShield:consumeEvent(event)
  if event.button == "primary" and (self.active or rig.formationBlend > 0) then
    return true -- swallow input to block primary
  end
  return false
end


function MagShield:engage()
  self.active = true
  rig.input:setBridge("alt")

  setFormation(self:formFormation(), self.shieldTransformTime or 0.15)
  setOrbVisualOverride("shield")
  setStance(self.stanceName or "shield")

  animator.playSound("shieldOn") -- the playsafely util func should also warn if its absent
  animator.playSound("shieldLoop", -1)
  for i = 1, (self.emitterQuantity or 0) do
    animator.setParticleEmitterActive("shieldEmitter"..i, true)
  end

  self:applyProtection()

  for i = 1, rig.orbTotal do rig.orbSpring[i]:kick(-1.5, 0) end
end





function MagShield:release()
  self.active = false
  rig.input:setBridge(nil)

  setFormation(nil)
  for i = 1, rig.orbTotal do 
    animator.setAnimationState("orb"..i, "unshield") 
    -- rig.orbSpinner[i]:kick(((i % 2 == 0) and 1 or -1) * 1.5)
  end

  setOrbVisualOverride(nil) -- double check this reasoning later when I'm less tired
  setStance("idle")

  animator.stopAllSounds("shieldLoop")

  if not status.resourcePositive("shieldStamina") then
    animator.playSound("shieldBreak")
    -- maybe do some more stuff here
  end

  animator.playSound("shieldOff")
  for i = 1, (self.emitterQuantity or 0) do
    animator.setParticleEmitterActive("shieldEmitter"..i, false)
  end

  self:removeProtection()
end





function MagShield:applyProtection()
  activeItem.setItemShieldPolys({self.shieldPoly})
  if self.damageSource then activeItem.setItemDamageSources({self.damageSource}) end
  status.setPersistentEffects("magnorbShield", {{stat = "shieldHealth", amount = self.shieldHealth or 1024}})

  self.damageListener = damageListener("damageTaken", function(damageEvents)
    for _, event in pairs(damageEvents) do
      if event.hitType == "ShieldHit" then
        if status.resourcePositive("shieldStamina") then
          animator.playSound("shieldBlock")
          -- TODO: kick orb springs depending on source
        end
        return
      end
    end
  end)
end

function MagShield:removeProtection()
  activeItem.setItemShieldPolys()
  activeItem.setItemDamageSources()
  status.clearPersistentEffects("magnorbShield")
  self.damageListener = nil
end

function MagShield:holdUpdate(dt)
  if self.damageListener then self.damageListener:update() end
end


function MagShield:formFormation()
  return makeArcFormation(
    (self.shieldSpacingQ or 1) - (self.shieldRotateValue or 0.7),
    0.75, 
    {-1.5, 0}, 
    {orientation = 0, assign = (self.emitterQuantity or 0) > 0 and "anchored" or "nearest"}
  )
end