require "/scripts/vec2.lua"
require "/scripts/util.lua"

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

  self.controlMovement = config.getParameter("controlMovement")

  if self.ignoreTerrain then mcontroller.applyParameters({collisionEnabled=false}) end

  self.aimPosition = mcontroller.position()
  self.isFocusing = false
  self.isCharged = false
  
  self.velocityLast = {0,0}
  self.velocityCurrent = {0,0}
  self.collidedThisFrame = false
  self.velocityOfLastCollision = false

  message.setHandler("updateProjectile", function(_, _, aimPosition, isFocusing, isCharged)
    self.aimPosition = aimPosition
    self.isFocusing = isFocusing

    if not self.isCharged and isCharged then
      enterCharged()
    end
    if self.isCharged and not isCharged then 
      exitCharged()
    end 
    self.isCharged = isCharged

    if self.returning and self.isFocusing then self.returning = false end
    if self.isFocusing then projectile.setTimeToLive(self.timeToLive) end
  end)
end

function update(dt)
  controlRotation(dt)
  checkCollision(dt)

  mcontroller.applyParameters({stickyCollision = false})
  if self.isCharged then mcontroller.applyParameters({stickyCollision = true}) end

  if self.ownerId and world.entityExists(self.ownerId) then
    if self.isFocusing then
      controlTo(self.aimPosition)
    elseif not self.returning then
      mcontroller.approachVelocity({0, 0}, self.controlForce)
      
      if (not self.ignoreTerrain and mcontroller.isColliding()) or vec2.mag(mcontroller.velocity()) < self.minVelocity then
        self.returning = true
      end
    else
      controlReturn()
    end
  else
    projectile.die()
  end

  drawDebug()
end

function enterCharged()
  if mcontroller.isColliding() then
    self.angleOfLastCollision = vec2.norm(world.distance(self.aimPosition, mcontroller.position()))
  end

  for i = 1, 24 do projectile.processAction({action = "particle", specification = "psynorb_energy_spark"}) end
end

function exitCharged()
  if mcontroller.isColliding and self.angleOfLastCollision then
    mcontroller.addMomentum(vec2.mul(self.angleOfLastCollision, -60))
    for i = 1, 24 do projectile.processAction({action = "particle", specification = "psynorb_energy_spark"}) end
  end
end

function checkCollision()
  local isColliding = mcontroller.isColliding()

  if not isColliding then
    self.angleOfLastCollision = false
  end

  self.velocityLast = self.velocityCurrent
  self.velocityCurrent = mcontroller.velocity()

  if isColliding and (self.wasColliding == false) then
    self.angleOfLastCollision = vec2.norm(self.velocityLast)

    if self.isCharged then 
      -- do a min velocity check or cooldown for charged impact effects


      actionSound({ "/sfx/projectiles/magnorb_impact1.ogg",
      "/sfx/projectiles/magnorb_impact2.ogg",
      "/sfx/projectiles/magnorb_impact3.ogg"  })
    end
  end

  if self.isCharged and isColliding and self.wasColliding and self.angleOfLastCollision then 
    
    --for i = 1, 2 doprojectile.processAction({action = "particle", specification = "rainproj5"}) end

    local angle = vec2.mul(self.angleOfLastCollision, -10)
    local params = copy(root.projectileConfig("psynorb_action"))
    params.parametersOrbReturn.actionOnReap[1].list[1].count = 4
    params.parametersOrbReturn.actionOnReap[1].list[1].body[1].specification.initialVelocity = angle
    projectile.processAction(params.parametersOrbReturn.actionOnReap[1])

    -- TODO: fix weird circle interpolation
    self.angleOfLastCollision = vec2.approach(self.angleOfLastCollision, vec2.norm(world.distance(self.aimPosition, mcontroller.position())), 0.01)
  end

  self.wasColliding = isColliding
end

function controlTo(position) 
  local direction = vec2.norm(world.distance(position, mcontroller.position()))
  
  local speedMult = 1
  local forceMult = 1

  if self.isCharged then
    speedMult = 1.4
    forceMult = 4.5
  elseif self.isFocusing then
    speedMult = 1.2
    forceMult = 1.9
  end

  local maxSpeed = self.controlMovement.maxSpeed * speedMult
  local controlForce = self.controlMovement.controlForce * forceMult
  mcontroller.approachVelocity(vec2.mul(direction, maxSpeed), controlForce)
end

function controlReturn()
  local toTarget = world.distance(world.entityPosition(self.ownerId), mcontroller.position())
  if vec2.mag(toTarget) < self.pickupDistance then projectile.die()
  elseif projectile.timeToLive() < self.timeToLive * 0.5 then
    mcontroller.applyParameters({collisionEnabled=false})
    mcontroller.approachVelocity(vec2.mul(vec2.norm(toTarget), self.speed), 500)
  elseif vec2.mag(toTarget) < self.snapDistance then
    mcontroller.approachVelocity(vec2.mul(vec2.norm(toTarget), self.speed), 500)
  else
    mcontroller.approachVelocity(vec2.mul(vec2.norm(toTarget), self.speed), self.controlForce)
  end
end

function controlRotation(dt)
  local speed = 0.2
  if self.isCharged then speed = 8 end
   
  mcontroller.setRotation(mcontroller.rotation() + (dt * speed))
end

function hit(entityId)
  if self.returnOnHit and not self.isFocusing then self.returning = true end
end

function projectileIds()
  return {entity.id()}
end

function drawDebug()
  local pos = mcontroller.position()
  --world.debugText("TTL:  " .. (projectile.timeToLive()), vec2.add(pos, {4, 2}), "green")

  --local col = self.isFocusing and "green" or "red"
  --util.debugCircle(pos, 3, col, 6)
  world.debugText("onGround:  " .. (mcontroller.onGround() and "true" or "false"), vec2.add(pos, {4, 2}), "green")
  world.debugText("isStuck:  " .. (mcontroller.isCollisionStuck() and "true" or "false"), vec2.add(pos, {4, 1.5}), "green")
  world.debugText("isColliding:  " .. (mcontroller.isColliding() and "true" or "false"), vec2.add(pos, {4, 1}), "green")

  world.debugLine(mcontroller.position(), vec2.add(mcontroller.position(), vec2.mul(vec2.norm(mcontroller.velocity()), 3)), "blue")
  world.debugLine(mcontroller.position(), vec2.add(mcontroller.position(), vec2.withAngle(mcontroller.rotation(), 5)), "red")

  if self.angleOfLastCollision then
    world.debugLine(mcontroller.position(), vec2.add(mcontroller.position(), vec2.mul(self.angleOfLastCollision, 15)), "white")
  end

  -- if entering charge mode while already colliding, set last colision angle to desired velocity
end

function actionSound(sound)
	if type(sound) == "table" then
		projectile.processAction({action = "sound", options = sound })
	else projectile.processAction({action = "sound", options = {sound}}) end
end

function doParticleAction(position, pParams, count)
  local c = count or 1
  for i = 1, c do world.spawnProjectile("psynorb_action", position, activeItem.ownerEntityId(), {0,0}, false, pParams) end
end