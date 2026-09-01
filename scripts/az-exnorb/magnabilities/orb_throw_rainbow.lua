require "/scripts/az-exnorb/magnabilities/orb_throw.lua"
require "/scripts/az_actions.lua"
require "/scripts/vec2.lua"

OrbThrowRainbow = OrbThrow:new()

-- I need to change the naming convention, `doOrbReturnAction` sounds way more like a module hook than onOrbReturn, right?
-- Or maybe it's the other way around? Either way I need to make sure it's consistent
-- Like, comparing rainbow.lua to bracer.lua, all the rainbow-specific stuff sure seems like a hook
-- But once I build the extended actions toolset, these actions can be done in the item def, in which case,
-- the hooks would probably be in bracer.lua, right? I guess I could just call these in the same place...
-- figure that out when I'm less dizzy


function OrbThrowRainbow:onOrbReturn(orbIndex, originFlag, returnVelocity) -- TODO: use action grammar TODO: localize particles
  -- animator.playSound("impact") -- Bracer does this already before calling hook
  local orbPos = firePosition(orbIndex)
  local burstCount = 16

  -- TODO: need better ergo on these particle FX functions. especially for adding momentum to particles easily 

  if originFlag == ORB_FROM_PORTAL then
    local sparks = azActions.loopGroup({
      azActions.makeParticleAction("astraltearsparkle1"),
      azActions.makeParticleAction("astraltearsparkle2"),
      azActions.makeParticleAction("astraltearsparkle2")
    }, 3)

    azActions.processAt(sparks, orbPos)
    burstCount = 12
  end

  local vel = {0, 0}
  if returnVelocity then
    vel = vec2.norm(returnVelocity)
    if vec2.mag(vel) < 0.5 then
      vel = {0, 0}
    end
  end


  local sparkle = root.assetJson("/particles/special/rain_spark"..orbIndex..".particle").definition
  local sparkleParams = {
    layer = "middle",
    timeToLive = 0.3,
    destructionTime = 0.2,
    initialVelocity = vec2.mul(vel, 3.5),
    size = 0.45,
    
    variance = {
      position = {0.5, 0.5},
      initialVelocity = {2, 2},
      size = 0.1,
      timeToLive = 0.15
    }
  }

  local actions = azActions.makeParticleAction(sparkle, burstCount, sparkleParams)
  azActions.processAt(actions, firePosition(orbIndex))
end

function OrbThrowRainbow:onOrbFired(orbIndex, aimVec, firePos)
  local spec = azActions.modify(
    azActions.getDef("/particles/special/rain_spark"..orbIndex..".particle"), 
    {
      layer = "middle",
      timeToLive = 0.3,
      destructionTime = 0.2,
      size = 0.45,
  
      variance = {
        position = {0.25, 0.25},
        size = 0.1,
        timeToLive = 0.15
      }
    }
  )

  azActions.processAt(azActions.makeParticleAction(azActions.alongAngle(spec, aimVec, 5.5, {1.5, 1.5}), 12), firePos)
end