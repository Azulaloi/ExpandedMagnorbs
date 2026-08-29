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

  if self.ignoreTerrain then mcontroller.applyParameters({collisionEnabled=false}) end

  message.setHandler("projectileIds", projectileIds)

  message.setHandler("setTargetPosition", function(_, _, targetPosition)
      self.targetPosition = targetPosition
    end)


  self.homeOffset = {0, 0}
  message.setHandler("setHomeOffset", function(_, _, offset)
    self.homeOffset = offset
  end)


  self.ghost = config.getParameter("ghost", false)
  message.setHandler("triggerResurrection", function(_, _) 
    self.ghost = false
  end)



  if boomerangExtra then
    boomerangExtra:init()
  end


  self.lastPos = mcontroller.position()
  self.lastVel = mcontroller.velocity()
  self.impactActions = config.getParameter("impactActions", {})
end

function update(dt)
  if self.ownerId and world.entityExists(self.ownerId) then
    
    if boomerangExtra then
      boomerangExtra:update(dt)
    end

    if not self.returning then
      -- Decelerating branch.

      mcontroller.approachVelocity({0, 0}, self.controlForce)
      if (not self.ignoreTerrain and mcontroller.isColliding()) or vec2.mag(mcontroller.velocity()) < self.minVelocity then
        self.returning = true
      end
    else
      -- Returning branch.
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
