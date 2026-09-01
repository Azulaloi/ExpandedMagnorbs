require "/scripts/vec2.lua"
require "/scripts/az_actions.lua"

-- TODO: retroextrapolated oncollide effects
-- TODO: use a spinner to control angular velocity, simulate roll from collisions

function init()
  self.returning = config.getParameter("returning", false)
  self.returnOnHit = config.getParameter("returnOnHit", false)
  self.controlForce = config.getParameter("controlForce")
  self.pickupDistance = config.getParameter("pickupDistance")
  self.snapDistance = config.getParameter("snapDistance")
  self.timeToLive = config.getParameter("timeToLive")
  self.speed = config.getParameter("speed")
  self.ignoreTerrain = config.getParameter("ignoreTerrain")
  self.ownerId = projectile.sourceEntity()
  self.minVelocity = config.getParameter("minVelocity", 0.2)


  self.fromPortal = config.getParameter("fromPortal", false)
  self.fromPortalId = config.getParameter("fromPortalId", false)

  self.graceTimer = 0.15

  if self.ignoreTerrain then mcontroller.applyParameters({collisionEnabled=false}) end

  message.setHandler("projectileIds", projectileIds)

  message.setHandler("setTargetPosition", function(_, _, targetPosition)
      self.targetPosition = targetPosition end)

  --message.setHandler("triggerAltReturn", ) -- what was this for? portal?

  self.homeOffset = {0, 0}
  message.setHandler("setHomeOffset", function(_, _, offset)
    self.homeOffset = offset end)

  self.ghost = config.getParameter("ghost", false)
  message.setHandler("triggerResurrection", function(_, _) 
    self.ghost = false end)

  message.setHandler("triggerReturn", function(_, _)
    self.returning = true end)

  if boomerangExtra then -- ...
    boomerangExtra:init()
  end

  if self.fromPortal and self.fromPortalId then
    self.targetPosition = world.entityPosition(self.fromPortalId)
  end


  self.lastPos = mcontroller.position()
  self.lastVel = mcontroller.velocity()
  self.impactActions = config.getParameter("impactActions", nil)
end

function update(dt)
  self.graceTimer = self.graceTimer - dt

  if self.ownerId and world.entityExists(self.ownerId) then
    
    if boomerangExtra then
      boomerangExtra:update(dt)
    end

    -- Check that the portal still exists. We get a notification when the portal is set manually, but on on timeout, so we need to check here.
    -- Doing it here is more robust than from the item script because it should work even if the item isn't equipped.
    if self.fromPortal and self.fromPortalId and not world.entityExists(self.fromPortalId) then
      self.fromPortal = false
      self.targetPosition = false
    end

    if not self.returning then
      -- Decelerating branch.

      mcontroller.approachVelocity({0, 0}, self.controlForce)
      if self.graceTimer <= 0 and ((not self.ignoreTerrain and mcontroller.isColliding()) or vec2.mag(mcontroller.velocity()) < self.minVelocity) then
        self.returning = true
      end
    else
      -- Returning branch.
      local returnTarget = self.targetPosition or vec2.add(world.entityPosition(self.ownerId), self.homeOffset)
      local toTarget = world.distance(returnTarget, mcontroller.position())


      if self.ghost and (vec2.mag(toTarget) > 40) then  -- make ghost killdist tunble
        projectile.die()
      end
      

      if vec2.mag(toTarget) < self.pickupDistance then
        -- Return by pickup.

        if not self.ghost then
          world.sendEntityMessage(self.ownerId, "orbReturn", entity.id(), mcontroller.velocity())
        end

        projectile.die()
      elseif projectile.timeToLive() < self.timeToLive * 0.5 then -- this will need refactoring for sure
        -- Less than half of TTL remains, initiate no-clip fast return.

        mcontroller.applyParameters({collisionEnabled=false})
        mcontroller.approachVelocity(vec2.mul(vec2.norm(toTarget), self.speed), 500) -- these need to be tunable
      elseif vec2.mag(toTarget) < self.snapDistance then
        -- Within snap distance, initiate fast return.

        mcontroller.approachVelocity(vec2.mul(vec2.norm(toTarget), self.speed), 500)
      else
        -- Do normal speed return.

        mcontroller.approachVelocity(vec2.mul(vec2.norm(toTarget), self.speed), self.controlForce)
      end
    end
  else
    projectile.die()
  end

  self.dt = dt
  self.lastPos = mcontroller.position()
  self.lastVel = mcontroller.velocity()
end

-- TODO: projectile subclasses? not just for norb-specific FX, but also other ability behaviours (can't do solely in ability bc they stop running when unequipped)
function bounce()
  -- sb.logInfo("BOUNCE")
  if not self.impactActions then return end
  if not self.lastPos then return end
  local reach = vec2.mag(self.lastVel) * (self.dt or 1/60) * 2 + 2
  local rayEnd = vec2.add(self.lastPos, vec2.mul(vec2.norm(self.lastVel), reach))
  local hitPoint = world.lineCollision(self.lastPos, rayEnd)

  local actions = azActions.mapParticles(self.impactActions, function(spec) 
    return azActions.withMomentum(spec, self.lastVel, 0.014)
  end)
  azActions.processAt(actions, hitPoint or mcontroller.position())
  -- azActions.processAt(azActions.makeParticleAction("largehitspark", 1), hitPoint or mcontroller.position())
end

function hit(entityId)
  if self.returnOnHit then self.returning = true end
end

function projectileIds()
  if boomerangExtra and boomerangExtra.projectileIds then
    return boomerangExtra:projectileIds()
  else
    return {entity.id()}
  end
end

function setTargetPosition(targetPosition)
  self.targetPosition = targetPosition
end
