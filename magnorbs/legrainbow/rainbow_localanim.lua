require "/scripts/vec2.lua"
require "/scripts/az-exnorb/lib/az_dynamics.lua"

function update(dt)
  localAnimator.clearDrawables()

  if not animationConfig.animationParameter("spaceOrbActive") then return end

  local center = animationConfig.animationParameter("spaceOrbCenter")
  local phase = animationConfig.animationParameter("spaceOrbPhase")
  local tune = animationConfig.animationParameter("spaceOrbTune")
  local image = animationConfig.animationParameter("spaceOrbImage")
  if not (center and phase and tune and image) then return end

  local pos, depth = azDynamics.squashedOrbit(tune.radius, tune.squash, phase)
  local behind = depth > 0
  local scale = 1 - tune.depthScale * math.max(0, depth)

  localAnimator.addDrawable({
    image = image .. (behind and tune.backDirectives or ""),
    position = vec2.add(center, pos),
    centered = true,
    fullbright = true,
    scale = scale
  }, behind and tune.backLayer or tune.frontLayer)
end