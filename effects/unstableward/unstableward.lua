require "/scripts/util.lua"
require "/scripts/status.lua"

function init()
    script.setUpdateDelta(5)
    self.triggerDamageThreshold = config.getParameter("triggerDamageThreshold")
    self.timeUntilActive = config.getParameter("activateDelay")

    animator.setParticleEmitterActive("sparks", true)
    effect.setParentDirectives("fade=FFFFCC;0.03?border=2;FFFFCC20;00000000")
end

function update(dt)
    if self.timeUntilExpire then
        self.timeUntilExpire = self.timeUntilExpire - dt
        if self.timeUntilExpire <= 0 then
            effect.expire()
        end
    elseif self.timeUntilActive > 0 or not self.damageListener then
        self.timeUntilActive = self.timeUntilActive - dt
        if self.timeUntilActive <= 0 then
            self.damageListener = damageListener("damageTaken", function(notifications)
                local totalDamage = 0
                for _, notification in pairs(notifications) do
                    if notification.hitType == "Hit" then
                        totalDamage = totalDamage + notification.damageDealt
                        if totalDamage >= self.triggerDamageThreshold then
                            trigger()
                            break
                        end
                    end
                end
            end)
        end
    else
        self.damageListener:update()
    end


end

function uninit()

end

function trigger()
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

    world.spawnProjectile(
        "invisibleprojectile",
        mcontroller.position(),
        entity.id(),
        {0, 0},
        true,
        projectileConfig
    )
    animator.burstParticleEmitter("sparks")
    animator.setParticleEmitterActive("sparks", false)
    animator.setLightActive("glow", false)
    self.timeUntilExpire = config.getParameter("deactivateDelay")
end
