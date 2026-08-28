function init()
  self.blinkTimer = 0
end

function update(dt)
  self.blinkTimer = self.blinkTimer - dt
  if self.blinkTimer <= 0 then self.blinkTimer = 0.5 end

  if self.blinkTimer < 0.2 then
    effect.setParentDirectives(config.getParameter("flashDirectives", ""))
  else
    effect.setParentDirectives("")
  end

  explode()
  if self.exploded then
	effect.expire()
  end
end

function uninit()
  
end

function explode()
  if not self.exploded then
    local sourceEntityId = effect.sourceEntity() or entity.id()
    local sourceDamageTeam = world.entityDamageTeam(sourceEntityId)
    --local bombPower = status.resourceMax("health") * config.getParameter("healthDamageFactor", 1.0)
    local bombPower = config.getParameter("power", 1.0)
    local projectileConfig = {
      power = bombPower,
      damageTeam = sourceDamageTeam,
      onlyHitTerrain = true,
      timeToLive = 0,
      actionOnReap = {
        {
          action = "config",
          file = config.getParameter("bombConfig")
        }
      }
    }
    world.spawnProjectile("invisibleprojectile", mcontroller.position(), 0, {0, 0}, false, projectileConfig)
    self.exploded = true
  end
end
