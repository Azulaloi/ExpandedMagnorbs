require "/scripts/util.lua"
require "/scripts/status.lua"

function init()
  animator.setParticleEmitterOffsetRegion("sparkles", mcontroller.boundBox())
  animator.setParticleEmitterActive("sparkles", config.getParameter("particles", true))
  --effect.setParentDirectives("fade=FFFFCC;0.03?border=2;FFFFCC20;00000000")
  effect.setParentDirectives("?saturation=-80?multiply=B890DB20")
  --8A25DD
  effect.addStatModifierGroup({{stat = "invulnerable", amount = 1}})
end

function update(dt)
end

function uninit()
	status.expire()
end
