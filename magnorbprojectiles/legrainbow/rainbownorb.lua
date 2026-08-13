require "/scripts/vec2.lua"
require "/scripts/az_actions.lua"

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
      self.targetPosition = targetPosition
    end)

  message.setHandler("triggerReturn", function(_, _) 
    self.returning = true
   end)

  --message.setHandler("triggerAltReturn", )

  self.homeOffset = {0, 0}
  message.setHandler("setHomeOffset", function(_, _, offset)
    self.homeOffset = offset
  end)

  message.setHandler("triggerResurrection", function(_, _) 
    self.ghost = false
  end)
   
  if boomerangExtra then
    boomerangExtra:init()
  end

  if self.fromPortal and self.fromPortalId then
    self.targetPosition = world.entityPosition(self.fromPortalId)
  end


  self.ghost = config.getParameter("ghost", false)



  self.lastPos = mcontroller.position()
  self.lastVel = mcontroller.velocity()
  self.impactActions = config.getParameter("impactActions", {})
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

    -- hmm... moving the portal checking logic to the controller would make this more generic...
    -- but it wouldn't solve the post-uninit problem... needs modules?

    if not self.returning then
      mcontroller.approachVelocity({0, 0}, self.controlForce)
      if self.graceTimer <= 0 and ((not self.ignoreTerrain and mcontroller.isColliding()) or vec2.mag(mcontroller.velocity()) < self.minVelocity) then
        self.returning = true
      end
    else
      -- Returning branch.

      -- local toTarget = world.distance(self.targetPosition or world.entityPosition(self.ownerId), mcontroller.position())

      local returnTarget = self.targetPosition or vec2.add(world.entityPosition(self.ownerId), self.homeOffset)
      local toTarget = world.distance(returnTarget, mcontroller.position())

      if self.ghost and (vec2.mag(toTarget) > 40) then 
        projectile.die()
      end
      
      if vec2.mag(toTarget) < self.pickupDistance then
        -- Return by pickup.
        if not self.ghost then
          world.sendEntityMessage(self.ownerId, "orbReturn", entity.id(), mcontroller.velocity())
        end
        projectile.die()
      elseif projectile.timeToLive() < self.timeToLive * 0.5 then
        -- Less than half of TTL remains, initiate no-clip fast return.
        mcontroller.applyParameters({collisionEnabled=false})
        mcontroller.approachVelocity(vec2.mul(vec2.norm(toTarget), self.speed), 500)
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

function bounce()
  if not self.lastPos then return end
  local reach = vec2.mag(self.lastVel) * (self.dt or 1/60) * 2 + 2
  local rayEnd = vec2.add(self.lastPos, vec2.mul(vec2.norm(self.lastVel), reach))
  local hitPoint = world.lineCollision(self.lastPos, rayEnd)
  azActions.processAt(self.impactActions, hitPoint or mcontroller.position())
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
