require "/scripts/vec2.lua"
require "/scripts/util.lua"
require "/scripts/status.lua"
require "/scripts/activeitem/stances.lua" 
require "/scripts/az_actions.lua"
require "/scripts/az_dynamics.lua"
require "/magnorbs/legrainbow/rainbow_portal.lua"

function init()
  -- TODO: portal indicator on cursor?
  activeItem.setCursor("/cursors/reticle0.cursor")

  self.projectileType = config.getParameter("projectileType")
  self.projectileParameters = config.getParameter("projectileParameters")
  self.projectileParameters.power = self.projectileParameters.power * root.evalFunction("weaponDamageLevelMultiplier", config.getParameter("level", 1))
  self.cooldownTime = config.getParameter("cooldownTime", 0)
  self.cooldownTimer = self.cooldownTime
  self.orbTotal = config.getParameter("orbTotal")
  self.level = config.getParameter("level")
  self.shieldEnergyCost = config.getParameter("shieldEnergyCost", 50)

  -- TODO: move this into self.tune
  self.orbitRate = config.getParameter("orbitRate", 1) * -2 * math.pi

  -- TODO: figure out actual baseline values, then read these from config parameter
  self.tune = {
    throwKick = 1.0, -- Impulse scale for firing orbs
    catchKick = 1.0, -- Impulse scale for catching orbs

    ringSpinKick = 0.1, -- Impulse scale for orbital ring spin
    ringSpinRelax = 3.0, -- Ring spinner recovery rate (3.0 should be roughly 1 second)

    orbSpinBase = 0.5, -- Orbs base self-spin rate
    orbSpinKick = 0.5, -- Impulse scale for individual orbs self-spin
    orbSpinRelax = 1.5, -- Individual orb self-spinner recovery rate (1.5 should be roughly 2 seconds)

    springRad = 0.3, -- Impulse scale for radial component of individual orb spring kick response 
    springTan = 0.3, -- Impulse scale for tangential component of individual orb spring kick response
    springK = 90, -- Spring konstant for orb spring. Governs stiffness. Oscillation frequency == sqrt(K)/2pi. Peak displacement from impulse is vel/sqrt(K). Unless I did it wrong.
    springDamp = 9, -- Damping value for orb spring. Governs wobble decay. Critical damping is: 2*sqrt(K), higher is goopy, lower is jiggly.
    
    armAngular = 0.08, -- Mult for angular recoil felt by arm
    armAxial = 0.03, -- Mult for axial recoil felt by arm
    armK = 120, -- Spring konstant for arm spring.
    armDamp = 14, -- Damping value for arm spring.
    armAngularClamp = {-0.25, 0.25}, -- min, max
    armAxialClamp = {-0.4, 0.15}, -- min, max

    -- Idle self-jiggle of orbs-in-orbit. Self-jiggle is not part of the spring mechanism.
    jiggle = {
      radialAmplitude = 0.08,
      tangentialAmplitude = 0.08,

      -- Frequency is radians per second (Hz == freq / (2*pi))
      -- Irrational ratios produce non-repeating motion
      radialFrequency = 4.0 * math.sqrt(1.1),
      tangentialFrequency = 3.5 * math.sqrt(2.0),
 
      -- Phase is radians of offset per orb index (differing values for decorrelation)
      radialPhase = 2.3,
      tangentialPhase = 1.7
    },

    fallbackRadSpeed = 50, -- 100 = full speed
    fallbackTanSpeed = 10,

    deltaTracking = {
      strength = 0.3, -- Multiplier for injected hand delta force. 0 = none, 1 = full motion is inherited.
      threshold = 20, -- Minimum acceleration (tiles/s^2) to be injected. Motion below this threshold is ignored.

      -- The length of the delta-injection suppression window triggered on init and flip,
      -- during which further hand motion does not add to orb spring, and a new delta history is sampled.
      -- Basically, this value is used by the mechanism which prevents the orbs from exploding when the character sprite flips left/right, or on equip.
      -- 0.15 seems to work fine so far. More testing might find a more optimal value. But, like, it's fine.
      warmingInterval = 0.15
    },

    portal = {
      radius = 2.5,
      squash = -0.15,
      precessRate = 3.0,
      spinBase = 2.5,
      spinRelax = 1.5,
      depthScale = 0.2, -- Shrink effect at "far" arc
      backDirectives = "?brightness=-45", -- Darkening effect of "far" arc
      frontLayer = "Player+1", -- Layer for near arc
      backLayer = "Player-1", -- Layer for far arc
      flickTime = 0.065, -- Time for an orb fired with portal up to "flick" into the space orb, after which it emerges from portal
      transitKick = 2.0
    }
  }

  self.projectileSpeed = root.projectileConfig(self.projectileType .. "1").speed

  -- DYNAMICS CONSTRUCTORS

  self.ringSpin = azDynamics.Spinner.new(self.orbitRate * (storage.spinSign or 1), self.tune.ringSpinRelax)

  self.orbSpin, self.orbSpinAngle, self.orbSpring = {}, {}, {}
  for i = 1, self.orbTotal do
    -- TODO: optional per-orb tuning
    self.orbSpin[i] = azDynamics.Spinner.new(self.tune.orbSpinBase, self.tune.orbSpinRelax)
    self.orbSpinAngle[i] = 0
    self.orbSpring[i] = azDynamics.Spring2D.new(self.tune.springK, self.tune.springDamp)
    self.orbSpring[i]:reset({-1.5, 0}) -- Emerge offset. TODO: read 1.5 from orb radius
  end

  self.armAngularSpring = azDynamics.Spring1D.new(self.tune.armK, self.tune.armDamp, self.tune.armAngularClamp)
  self.armAxialSpring = azDynamics.Spring1D.new(self.tune.armK, self.tune.armDamp, self.tune.armAxialClamp)
  self.handTracker = azDynamics.MomentumFrame.new(self.tune.deltaTracking)

  self.debugHideRing = false -- hide ring orbs for tuning the space orb

  self.animTime = 0
  self.orbAngle = 0

  self.pendingReturns = {}
  message.setHandler("orbReturn", function(_, _, projId, velocity)
    self.pendingReturns[projId] = velocity
  end)

  initStances()

  storage.projectileIds = storage.projectileIds or {false, false, false, false, false}  -- need to figure out how to init these weird lua arrays with arbitrary sizes for other sets
  storage.projectileFlags = storage.projectileFlags or {false, false, false, false, false}
  checkProjectiles(true)
  sendSafely(storage.projectileIds, "triggerResurrection")

  magPortal.init()

  animator.resetTransformationGroup("orbs")
  for i = 1, self.orbTotal do
    local home = storage.projectileIds[i] == false

    animator.setAnimationState("orb"..i, home and "orb" or "hidden")
    animator.setParticleEmitterActive("idleparticles"..i, home)
  end

  setStance("idle")
  updateHand()
  resyncHandTracking()
end


function update(dt, fireMode, shiftHeld)
  self.cooldownTimer = math.max(0, self.cooldownTimer)

  updateStance(dt)
  checkProjectiles(false)
  magPortal.checkPortal()

  -- TODO: add shift, hold, double-tap, and dual press detection/variation

  if fireMode == "alt" and self.lastFireMode ~= "alt" and not status.resourceLocked("energy") then
    magPortal.altTap()
  end

  if fireMode == "primary" and self.lastFireMode ~= "primary" and (self.cooldownTimer == 0) then
    local nextOrbIndex = nextOrb()
    if nextOrbIndex then fire(nextOrbIndex) end
  end
  self.lastFireMode = fireMode

  updateAim()
  magPortal.update(dt)
  updateAnim(dt)
  updateHand()
  drawDebug()
end


function uninit()
  activeItem.setItemShieldPolys()
  activeItem.setItemDamageSources()
  -- Reset home offset of away projectiles, so they return to player center while item is stowed.
  sendSafely(storage.projectileIds, "setHomeOffset", {0, 0})
  createGhosts()
end


function createGhosts()
  -- TODO: store ghosts/ids, check for them on init. if any returning ghosts are out, mark them as away, and begin notifying them of new orbital targets... maybe just promote them to real returning orbs? same difference?
  -- (for the rare case where the bracer is reequipped before all ghosts have returned)
  
  local params = copy(self.projectileParameters)
  params.ghost = true
  params.returning = true
  params.ignoreTerrain = true
  params.power = 0
  params.damageTeam = {type = "passive"}
  params.timeToLive = 2
  params.processing = "?multiply=FFFFFF88"

  for i = 1, self.orbTotal do
    if storage.projectileIds[i] == false then
      local pid = world.spawnProjectile(self.projectileType .. i, firePosition(i), 
        activeItem.ownerEntityId(), {0, 0}, false, params) 
        -- {
        --   ghost = true, returning = true, ignoreTerrain = true,
        --   power = 0, damageTeam = {type = "passive"}, timeToLive = 2,
        --   processing = "?multiply=FFFFFF88", controlForce = 140,
        --   pickupDistance = 1.5, snapDistance = 4.0
        -- })
      if pid then
        storage.projectileIds[i] = pid
        storage.projectileFlags[i] = 1
      end
    end
  end
end



-- ANIM DYNAMICS


function updateAnim(dt)
  self.animTime = self.animTime + dt
  
  activeItem.setArmAngle(self.armAngle + self.armAngularSpring:step(dt))
  animator.resetTransformationGroup("weapon")
  animator.translateTransformationGroup("weapon", {self.armAxialSpring:step(dt), 0})

  self.orbAngle = self.orbAngle + self.ringSpin:step(dt)

  animator.resetTransformationGroup("orbs")
  animator.rotateTransformationGroup("orbs", -(self.armAngle or 0))

  local facing = mcontroller.facingDirection()
  if facing ~= self.lastFacing then resyncHandTracking() end
  self.lastFacing = facing

  local handBase = vec2.add(mcontroller.position(), activeItem.handPosition({0, 0}))
  local inject = self.handTracker:sample(handBase, dt)
  if inject then
    for i = 1, self.orbTotal do
      if storage.projectileIds[i] == false then
        local radDir, tanDir = azDynamics.frame(world.distance(firePosition(i), handBase))
        if radDir then
          self.orbSpring[i]:kick(vec2.dot(inject, radDir), vec2.dot(inject, tanDir) * facing)
        end
      end
    end
  end

  for i = 1, self.orbTotal do
    local home = storage.projectileIds[i] == false

    -- TODO: jiggle module for azDynamics?
    local J = self.tune.jiggle
    local jx = math.sin(self.animTime * J.radialFrequency + i * J.radialPhase) * J.radialAmplitude
    local jy = math.cos(self.animTime * J.tangentialFrequency + i * J.tangentialPhase) * J.tangentialAmplitude

    animator.resetTransformationGroup("orb"..i)
    self.orbSpinAngle[i] = self.orbSpinAngle[i] + self.orbSpin[i]:step(dt)

    animator.rotateTransformationGroup("orb"..i, self.orbSpinAngle[i] * facing, {1.5, 0}) 
    -- TODO: derive the orb offset/radius?
    -- TODO: should orb home pos radius affect ring torque?

    local offset = self.orbSpring[i]:step(dt)
    animator.translateTransformationGroup("orb"..i, {offset[1] + jx, offset[2] + jy})

    animator.rotateTransformationGroup("orb"..i, (self.orbAngle * facing) + 2 * math.pi * ((i - 2) / self.orbTotal))

    local shown = home and not self.debugHideRing
    animator.setAnimationState("orb"..i, shown and "orb" or "hidden")
    animator.setParticleEmitterActive("idleparticles"..i, shown)

    if not home then
      world.sendEntityMessage(storage.projectileIds[i], "setHomeOffset", activeItem.handPosition(animator.partPoint("orb"..i, "orbPosition")))
    end
  end

  magPortal.presentSpaceOrb(handBase, dt)
end


-- <flags> = {spring?: bool, orbSpin?: bool, ring?: bool, arm?: bool} or nil
function applyImpulse(orbIndex, vel, flags, scale)
  flags = flags or {}
  vel = vec2.mul(vel, scale or 1)
  local facing = mcontroller.facingDirection()
  local handBase = vec2.add(mcontroller.position(), activeItem.handPosition({0, 0}))

  local radDir, tanDir = azDynamics.frame(world.distance(firePosition(orbIndex), handBase))
  if radDir then
    local tanVel = vec2.dot(vel, tanDir)
    
    if flags.ring ~= false then
      self.ringSpin:kick(tanVel * self.tune.ringSpinKick, true)
      storage.spinSign = ((self.ringSpin.home < 0) == (self.orbitRate < 0)) and 1 or -1
    end

    if flags.orbSpin ~= false then
      self.orbSpin[orbIndex]:kick(tanVel * self.tune.orbSpinKick, true)
    end

    if flags.spring ~= false then
      self.orbSpring[orbIndex]:kick(
        vec2.dot(vel, radDir) * self.tune.springRad,
        tanVel * facing * self.tune.springTan
      )
    end
  end

  -- I really wish activeItems supported actual arm-moving recoil
  if flags.arm ~= false then
    local armTip = vec2.add(mcontroller.position(), activeItem.handPosition({1, 0}))
    local armDir, armPerp = azDynamics.frame(world.distance(armTip, handBase), 0.1)
    if armDir then
      self.armAngularSpring:kick(vec2.dot(vel, armPerp) * facing * self.tune.armAngular)
      self.armAxialSpring:kick(vec2.dot(vel, armDir) * self.tune.armAxial)
    end
  end

  -- TODO: impart momentum on player if the caught momentum is high enough? orbs would need "mass". what is the player's mass?
  -- would also then want to impart momentum on fire, presumably? would an orb ever be returning faster than its fire rate? 
  -- maybe if charged through the portal? oh that could be cool
end


function updateHand()
  local isFrontHand = (activeItem.hand() == "primary") == (mcontroller.facingDirection() < 0)
  animator.setGlobalTag("hand", isFrontHand and "front" or "back")
  activeItem.setOutsideOfHand(isFrontHand)
end


function resyncHandTracking()
  self.handTracker:resync(vec2.add(mcontroller.position(), activeItem.handPosition({0, 0})))
end



-- TODO: alternate orbital behaviours? maybe worth testing at least
--  layered fake halo method like I used for the novablitz ioun stone thing?
--    this one would be hard to drive physically. might benefit from slight scaling to help with depth? 
--    oh, could I use scaling on the current model to make the orbs appear more 3D?
--    even if I don't use it for norbs, it could be used for alt abilities or something
--  relaxed orbit (no dock/anchor) with physically driven separation?
--    might provide a cool visual and some variation, but also might be tuning hell
--    and it would mean even more lua physics


-- PRIMARY/SECONDARY (ORB/PORTAL) MANAGEMENT


function fire(orbIndex)
  if self.portalActive then
    magPortal.beginConduitFire(orbIndex) -- TODO: rename to transit fire maybe?
    self.cooldownTimer = self.cooldownTime
    animator.playSound("fire")
    return
  end
  
  local params = copy(self.projectileParameters)
  params.powerMultiplier = activeItem.ownerPowerMultiplier()
  params.ownerAimPosition = activeItem.ownerAimPosition()

  local firePos = firePosition(orbIndex)
  if world.lineCollision(mcontroller.position(), firePos) then return end

  local projectileId = world.spawnProjectile(
    self.projectileType .. orbIndex, firePos, activeItem.ownerEntityId(), 
    aimVector(firePos), false, params
  )

  if projectileId then
    storage.projectileIds[orbIndex] = projectileId
    storage.projectileFlags[orbIndex] = 1 -- 1 means "from orbit", 2 means "from portal"
    storage.lastFired = orbIndex
    self.cooldownTimer = self.cooldownTime
    animator.playSound("fire")
    applyImpulse(
      orbIndex, vec2.mul(aimVector(firePos), -self.projectileSpeed), 
      {spring = false, orbSpin = false}, self.tune.throwKick
    )
    -- Since the orb is departing, reset its spin (regardless of whether firing added any)
    self.orbSpin[orbIndex]:reset()
  end
end


function doOrbReturnAction(orbIndex, fromPortal, returnVelocity)
  animator.playSound("impact")
  local orbPos = firePosition(orbIndex)
  local burstCount = 16

  -- TODO: need better ergo on these particle FX functions. especially for adding momentum to particles easily 

  if fromPortal then
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

  if returnVelocity then
    applyImpulse(orbIndex, vec2.sub(returnVelocity, mcontroller.velocity()), nil, self.tune.catchKick)
  else
    -- No return velocity packet, orb returned through other means (reaped, was stowed, edge case)
    -- Synthesize a generic arrival packet.

    local handBase = vec2.add(mcontroller.position(), activeItem.handPosition({0, 0}))
    local toOrb = world.distance(firePosition(orbIndex), handBase)
    if vec2.mag(toOrb) > 0.5 then
      local spinSign = self.ringSpin.vel >= 0 and 1 or -1
      local radDir = vec2.norm(toOrb)
      local tanDir = vec2.rotate(radDir, math.pi / 2)
      local vel = vec2.add(
        vec2.mul(radDir, -self.tune.fallbackRadSpeed),
        vec2.mul(tanDir, spinSign * self.tune.fallbackTanSpeed)
      )
      applyImpulse(orbIndex, vel, nil, self.tune.catchKick)
    else
      -- degenerate case, fallback poke
      self.orbSpring[orbIndex]:setVelocity(-3, 0)
    end
  end
end


function checkProjectiles(silent)
  for i, projectileId in ipairs(storage.projectileIds) do
    if projectileId and not world.entityExists(projectileId) then
      storage.projectileIds[i] = false
      if storage.projectileFlags[i] then
        if not silent then
          doOrbReturnAction(i, storage.projectileFlags[i] == 2, self.pendingReturns[projectileId])

        end

        self.pendingReturns[projectileId] = nil
        storage.projectileFlags[i] = false
      end
    end
  end
end


-- TODO: generalize next orb functions (linear, round-robin, random, whatever) so param can select strategy
-- but the predicates... can I pass those with lua?

function nextOrb()
  -- for i = 1, self.orbTotal do
  --   if not storage.projectileIds[i] then
  --     return i
  --   end
  -- end

  -- Round-robin
  local last = storage.lastFired or 0
  for offset = 1, self.orbTotal do
    local i = (last + offset - 1) % self.orbTotal + 1
    if not storage.projectileIds[i] and not magPortal.isDiving(i) then return i end
  end
end


function availableOrbCount()
  local available = 0
  for i = 1, self.orbTotal do
    if not storage.projectileIds[i] then
      available = available + 1
    end
  end
  return available
end





-- MISC?


function firePosition(orbIndex)
  return vec2.add(mcontroller.position(), activeItem.handPosition(animator.partPoint("orb"..orbIndex, "orbPosition")))
end


function aimVector(firePos)
  -- If aimPos == firePos, norb will have sub-pickup velocity at spawn and instantly be recaptured.
  -- While the norb grace timer prevents this, the aim vector is still garbage. We check delta here to prevent that.
  local delta = world.distance(activeItem.ownerAimPosition(), firePos)
  if vec2.mag(delta) < 0.25 then
    delta = world.distance(firePos, mcontroller.position())
    if vec2.mag(delta) < 0.25 then
      return {mcontroller.facingDirection(), 0}
    end
  end
  
  return vec2.norm(delta)

  --return vec2.norm(world.distance(activeItem.ownerAimPosition(), firePos))
end




-- UTILITIES

function drawDebug()
  local pos = mcontroller.position()
  world.debugText("portal:  " .. (self.portalActive and "true" or "false"), vec2.add(pos, {4, 2}), "green")
end


function sendSafely(array, msg, ...)
  --sb.logInfo(sb.print{...})
  uponExtantEntities(array, function(_, v, ...) world.sendEntityMessage(v, msg, ...) end, ...)
end


function uponExtantEntities(array, handler, ...)
  for i, v in ipairs(array) do
    if v and world.entityExists(v) then
      handler(i, v, ...)
    end
  end
end

