require "/scripts/az-exnorb/magnability.lua"

OrbThrow = Magnability:new()

function OrbThrow:consumeEvent(event)
  if event.button ~= "primary" or event.type ~= "press" then return false end
  if rig.cooldownTimer and rig.cooldownTimer > 0 then return true end
  local orbIndex = nextOrb() -- TODO: nextorb strategy
  if orbIndex then fire(orbIndex) end
  return true
end

-- hold primary to charge shot
-- hold primary to rapidly fire (violium chainsaw)
-- fire mode that tells projectile to return after exceeding distance(firePos, aimPos) from player? for chainsaw

-- fire behaviour that divekicks to tangent firepos before departing, blitzproj style (but not broken lol)
-- tangent firepos should respond to spinsign of course (and have different kick impulse behaviour)

-- orb "depletion"? heat? spin? for nondisjunctive cooldown 