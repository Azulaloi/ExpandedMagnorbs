require "/scripts/az-exnorb/magnabilities/mag_shield.lua"

MagWard = MagShield:new()

function MagWard:init()
  MagShield.init(self) -- Lua was named after the moon because ...
  self.wardEffects = self.wardEffects or {}
end

function MagWard:applyProtection()
  for _, effect in ipairs(self.wardEffects) do status.addEphemeralEffect(effect) end
  rig.armAngleOverride = self.armPose or 1.15
end 

-- novaflame status that lights someone on fire but like with the nova color

function MagWard:removeProtection()
  for _, effect in ipairs(self.wardEffects) do status.removeEphemeralEffect(effect) end
  rig.armAngleOverride = nil -- need some kind of stance system...
end

function MagWard:holdUpdate(dt)
  for _, effect in ipairs(self.wardEffects) do status.addEphemeralEffect(effect) end -- refresh
end
