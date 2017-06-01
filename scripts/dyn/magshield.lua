require "/scripts/vec2.lua"
require "/scripts/util.lua"
require "/scripts/status.lua"
require "/scripts/activeitem/stances.lua"
require "/scripts/interp.lua"

MagShield = WeaponAbility:new()

function MagShield:init()

    --Store shield emitters
    self.emitterQuantity = config.getParameter("emitterQuantity")
    emitterQuantity = tonumber(self.emitterQuantity)
    emitters = {}
    if config.getParameter("emitterQuantity") then
        if (emitterQuantity >= 1) then
            for i = 1,(emitterQuantity) do
                table.insert(emitters, ("shieldEmitter" .. i))
                for i, v in ipairs(emitters) do sb.logInfo(i, v) end
            end
        end
    end

    --Define config parameters
    self.shieldActive = false
    self.shieldTransformTimer = 0
    self.shieldTransformTime = config.getParameter("shieldTransformTime", 0.1)
    self.shieldPoly = animator.partPoly("glove", "shieldPoly")
    self.shieldEnergyCost = config.getParameter("shieldEnergyCost", 50)
    --If defined, use shield health
    if config.getParameter("shieldHealth") then self.shieldHealth = tonumber(config.getParameter("shieldHealth"))
    else self.shieldHealth = 1000
    end
    self.shieldKnockback = config.getParameter("shieldKnockback", 0)
    --If defined, change shield damage type
    if config.getParameter("doesDamage") then self.knockbackDamageParam = "damage"
    else self.knockbackDamageParam = "Knockback"
    end
    --If defined, use shield damage
    if config.getParameter("contactDamage") then self.knockbackDamageQuantity = config.getParameter("contactDamage")
    else self.knockbackDamageQuantity = 0
    end
    --Define shield knockback parameters
    if self.shieldKnockback > 0 then
        self.knockbackDamageSource = {
            poly = self.shieldPoly,
            damage = self.knockbackDamageQuantity,
            damageType = self.knockbackDamageParam,
            sourceEntity = activeItem.ownerEntityId(),
            team = activeItem.ownerTeam(),
            knockback = self.shieldKnockback,
            rayCheck = true,
            damageRepeatTimeout = 0.5
        }
    end
end

function MagShield:update(dt, fireMode, shiftHeld)
    WeaponAbility.update(self, dt, fireMode, shiftHeld)

    --Right click for shield
    if fireMode == "alt" and availableOrbCount() == self.lockValue and not status.resourceLocked("energy") and status.resourcePositive("shieldStamina") then
        if not self.shieldActive then
            self.activateShield()
        end
        setOrbAnimationState("shield")
        self.shieldTransformTimer = math.min(self.shieldTransformTime, self.shieldTransformTimer + dt)
    else
        self.shieldTransformTimer = math.max(0, self.shieldTransformTimer - dt)
        if self.shieldTransformTimer > 0 then
            setOrbAnimationState("unshield")
        end
    end

    --Break or out of energy
    if self.shieldActive then
        if not status.resourcePositive("shieldStamina") or not status.overConsumeResource("energy", self.shieldEnergyCost * dt) then
            deactivateShield()
        else
            self.damageListener:update()
        end
    end

    --Transform to shield position
    if self.shieldTransformTimer > 0 then
        local transformRatio = self.shieldTransformTimer / self.shieldTransformTime
        setOrbPosition(SpacingQ - transformRatio * ShieldRotate, transformRatio * 0.75)
        animator.resetTransformationGroup("orbs")
        animator.translateTransformationGroup("orbs", {transformRatio * -1.5, 0})
    else
        if self.shieldActive then
            deactivateShield()
        end
        animator.resetTransformationGroup("orbs")

    end
end

function MagShield:activateShield()
    self.shieldActive = true
    animator.resetTransformationGroup("orbs")
    animator.playSound("shieldOn")
    animator.playSound("shieldLoop", -1)
    for i, v in ipairs(emitters) do
        animator.setParticleEmitterActive(v, 1)
    end
    self.Magnorb:setStance("shield")
    activeItem.setItemShieldPolys({self.shieldPoly})
    activeItem.setItemDamageSources({self.knockbackDamageSource})
    status.setPersistentEffects("magnorbShield", {{stat = "shieldHealth", amount = self.shieldHealth}})
    self.damageListener = damageListener("damageTaken", function(notifications)
        for _,notification in pairs(notifications) do
            if notification.hitType == "ShieldHit" then
                if status.resourcePositive("shieldStamina") then
                    animator.playSound("shieldBlock")
                else
                    animator.playSound("shieldBreak")
                end
                return
            end
        end
    end)
end

function deactivateShield()
    self.shieldActive = false
    animator.playSound("shieldOff")
    animator.stopAllSounds("shieldLoop")
    for i, v in ipairs(emitters) do
        animator.setParticleEmitterActive(v, false)
    end
    self.Magnorb:setStance("idle")
    activeItem.setItemShieldPolys()
    activeItem.setItemDamageSources()
    status.clearPersistentEffects("magnorbShield")
end