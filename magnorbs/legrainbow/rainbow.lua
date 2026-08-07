require "/scripts/vec2.lua"
require "/scripts/util.lua"
require "/scripts/status.lua"
require "/scripts/activeitem/stances.lua" 

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
      handWarmingInterval = 0.15
    }
  }
  self.projectileSpeed = root.projectileConfig(self.projectileType .. "1").speed
  self.ringSpin = newSpinner(self.orbitRate * (storage.spinSign or 1), self.tune.ringSpinRelax)

  self.orbSpin = {}
  self.orbSpinAngle = {}
  for i = 1, self.orbTotal do
    self.orbSpin[i] = newSpinner(self.tune.orbSpinBase, self.tune.orbSpinRelax)
    self.orbSpinAngle[i] = 0
  end


  self.armRecoil, self.armRecoilVel = 0, 0
  self.armPush, self.armPushVel = 0, 0

  self.animTime = 0
  self.orbAngle = 0
  self.orbOffset = {}
  self.orbOffsetVel = {}
  for i = 1, self.orbTotal do
    self.orbOffset[i] = {-1.5, 0} -- TODO: derive radius/offset, or make one truth
    self.orbOffsetVel[i] = {0, 0}
  end
  
  self.pendingReturns = {}
  message.setHandler("orbReturn", function(_, _, projId, velocity)
    self.pendingReturns[projId] = velocity
  end)

  initStances()
  storage.projectileIds = storage.projectileIds or {false, false, false, false, false}
  storage.projectileOutLast = storage.projectileOutLast or {false, false, false, false, false} -- TODO: rename this
  checkProjectiles(true)

  storage.portalId = storage.portalId or false
  self.portalActive = false
  checkPortal()
  self.portalActiveLast = self.portalActive


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
  checkPortal()

  -- TODO: add shift, hold, double-tap, and dual press detection/variation

  if fireMode == "alt" and self.lastFireMode ~= "alt" and not status.resourceLocked("energy") then
    if (not self.portalActive) and (not storage.portalId) then activatePortal()
    else collapsePortal(storage.portalId) end
  end

  if fireMode == "primary" and self.lastFireMode ~= "primary" and (self.cooldownTimer == 0) then
    local nextOrbIndex = nextOrb()
    if nextOrbIndex then fire(nextOrbIndex, self.portalActive, storage.portalId) end
  end
  self.lastFireMode = fireMode

  updateAim()
  updateAnim(dt)
  updateHand()
  drawDebug()
end


function uninit()
  activeItem.setItemShieldPolys()
  activeItem.setItemDamageSources()
  -- Reset home offset of away projectiles, so they return to player center while item is stowed.
  sendSafely(storage.projectileIds, "setHomeOffset", {0, 0})

  -- TODO: create ghost orbs for stashing return animation
end



-- ANIM DYNAMICS


function updateAnim(dt)
  self.animTime = self.animTime + dt
  
  -- TODO: recoil/push aren't properly descriptive. recoil made sense when I hadn't done push yet, but now it should probably be "tilt" or "pitch" or something
  self.armRecoilVel = self.armRecoilVel + (-self.tune.armK * self.armRecoil - self.tune.armDamp * self.armRecoilVel) * dt
  self.armRecoil = util.clamp(self.armRecoil + self.armRecoilVel * dt, self.tune.armAngularClamp[1], self.tune.armAngularClamp[2])
  self.armPushVel = self.armPushVel + (-self.tune.armK * self.armPush - self.tune.armDamp * self.armPushVel) * dt
  self.armPush = util.clamp(self.armPush + self.armPushVel * dt, self.tune.armAxialClamp[1], self.tune.armAxialClamp[2])

  activeItem.setArmAngle(self.armAngle + self.armRecoil)
  animator.resetTransformationGroup("weapon")
  animator.translateTransformationGroup("weapon", {self.armPush, 0})

  self.orbAngle = self.orbAngle + spinnerUpdate(self.ringSpin, dt)

  animator.resetTransformationGroup("orbs")
  animator.rotateTransformationGroup("orbs", -(self.armAngle or 0))
  local facing = mcontroller.facingDirection()
  if facing ~= self.lastFacing then resyncHandTracking() end
  self.lastFacing = facing

  local handBase = vec2.add(mcontroller.position(), activeItem.handPosition({0, 0}))
  local handVel = vec2.div(vec2.sub(handBase, self.lastHandBase or handBase), dt)
  local dvel = vec2.sub(handVel, self.lastHandVel or handVel)
  -- TODO: check for teleport discontinuity?

  self.lastHandBase = handBase
  self.lastHandVel = handVel

  if self.handWarmup > 0 then
    self.handWarmup = self.handWarmup - dt
  else
    if vec2.mag(dvel) / dt > self.tune.deltaTracking.threshold then
      local thatSweetMotion = vec2.mul(dvel, -self.tune.deltaTracking.strength) 
      for i = 1, self.orbTotal do
        if storage.projectileIds[i] == false then
          local toOrb = world.distance(firePosition(i), handBase)
          if vec2.mag(toOrb) > 0.5 then
            local radDir = vec2.norm(toOrb)
            local tanDir = vec2.rotate(radDir, math.pi / 2)
            self.orbOffsetVel[i][1] = self.orbOffsetVel[i][1] + vec2.dot(thatSweetMotion, radDir)
            self.orbOffsetVel[i][2] = self.orbOffsetVel[i][2] + vec2.dot(thatSweetMotion, tanDir) * facing
          end
        end
      end
    end
  end

  for i = 1, self.orbTotal do
    local home = storage.projectileIds[i] == false

    for axis = 1, 2 do
      self.orbOffsetVel[i][axis] = self.orbOffsetVel[i][axis] + (-self.tune.springK * self.orbOffset[i][axis] - self.tune.springDamp * self.orbOffsetVel[i][axis]) * dt
      self.orbOffset[i][axis] = self.orbOffset[i][axis] + self.orbOffsetVel[i][axis] * dt
    end

    local J = self.tune.jiggle
    local jx = math.sin(self.animTime * J.radialFrequency + i * J.radialPhase) * J.radialAmplitude
    local jy = math.cos(self.animTime * J.tangentialFrequency + i * J.tangentialPhase) * J.tangentialAmplitude

    animator.resetTransformationGroup("orb"..i)
    self.orbSpinAngle[i] = self.orbSpinAngle[i] + spinnerUpdate(self.orbSpin[i], dt)
    animator.rotateTransformationGroup("orb"..i, self.orbSpinAngle[i] * facing, {1.5, 0}) -- TODO: derive the orb offset/radius?
    -- TODO: should orb home pos radius affect ring torque?

    animator.translateTransformationGroup("orb"..i, {self.orbOffset[i][1] + jx, self.orbOffset[i][2] + jy})
    animator.rotateTransformationGroup("orb"..i, (self.orbAngle * facing) + 2 * math.pi * ((i - 2) / self.orbTotal))
    animator.setAnimationState("orb"..i, home and "orb" or "hidden")
    animator.setParticleEmitterActive("idleparticles"..i, home)
    if not home then
      world.sendEntityMessage(storage.projectileIds[i], "setHomeOffset", activeItem.handPosition(animator.partPoint("orb"..i, "orbPosition")))
    end
  end
end


-- TODO: add throw/catch coefficients for ring spin application
function applyImpulse(orbIndex, vel, kickSpring)
  local facing = mcontroller.facingDirection()
  local handBase = vec2.add(mcontroller.position(), activeItem.handPosition({0, 0}))

  local toOrb = world.distance(firePosition(orbIndex), handBase)
  if vec2.mag(toOrb) > 0.5 then
    local radDir = vec2.norm(toOrb)
    local tanDir = vec2.rotate(radDir, math.pi / 2)
    local tanVel = vec2.dot(vel, tanDir)

    spinnerKick(self.ringSpin, tanVel * self.tune.ringSpinKick, true)
    storage.spinSign = ((self.ringSpin.home < 0) == (self.orbitRate < 0)) and 1 or -1

    spinnerKick(self.orbSpin[orbIndex], tanVel * self.tune.orbSpinKick, true) -- TODO: make sure orb spins reset when they depart

    if kickSpring then
      self.orbOffsetVel[orbIndex][1] = self.orbOffsetVel[orbIndex][1] + vec2.dot(vel, radDir) * self.tune.springRad
      self.orbOffsetVel[orbIndex][2] = self.orbOffsetVel[orbIndex][2] + tanVel * facing * self.tune.springTan
    end
  end

  local armTip = vec2.add(mcontroller.position(), activeItem.handPosition({1, 0}))
  local armDir = vec2.norm(world.distance(armTip, handBase))
  local armPerp = vec2.rotate(armDir, math.pi / 2)
  self.armRecoilVel = self.armRecoilVel + vec2.dot(vel, armPerp) * facing * self.tune.armAngular
  self.armPushVel = self.armPushVel + vec2.dot(vel, armDir) * self.tune.armAxial
end


function updateHand()
  local isFrontHand = (activeItem.hand() == "primary") == (mcontroller.facingDirection() < 0)
  animator.setGlobalTag("hand", isFrontHand and "front" or "back")
  activeItem.setOutsideOfHand(isFrontHand)
end


function resyncHandTracking()
  self.lastHandBase = vec2.add(mcontroller.position(), activeItem.handPosition({0, 0}))
  self.lastHandVel = {0, 0}
  self.handWarmup = self.tune.deltaTracking.handWarmingInterval
end


-- TODO: migrate spinner to a util script
-- TODO: add proper inertia + friction model? might be good for making different sets handle differently

-- TODO: alternate orbital behaviours? maybe worth testing at least
--  layered fake halo method like I used for the novablitz ioun stone thing?
--    this one would be hard to drive physically. might benefit from slight scaling to help with depth? 
--    oh, could I use scaling on the current model to make the orbs appear more 3D?
--    even if I don't use it for norbs, it could be used for alt abilities or something
--  relaxed orbit (no dock/anchor) with physically driven separation?
--    might provide a cool visual and some variation, but also might be tuning hell
--    and it would mean even more lua physics


function newSpinner(rate, relax)
  return {vel = rate, home = rate, relax = relax}
end


function spinnerUpdate(s, dt)
  -- TODO: more tuning control (friction, damping, clamps)

  s.vel = s.vel + (s.home - s.vel) * math.min(1, s.relax * dt)
  return s.vel * dt
end


function spinnerKick(s, kick, mayFlip)
  s.vel = s.vel + kick

  -- TODO: hysteresis for flip (must exceed X countervel before flipping)
  if mayFlip and (s.vel < 0) ~= (s.home < 0) and math.abs(s.vel) > math.abs(s.home) then
    s.home = -s.home
  end
end



-- PRIMARY/SECONDARY (ORB/PORTAL) MANAGEMENT


function fire(orbIndex, fromPortal, portalId)
  local params = copy(self.projectileParameters)
  params.powerMultiplier = activeItem.ownerPowerMultiplier()
  params.ownerAimPosition = activeItem.ownerAimPosition()
  params.fromPortal = fromPortal
  params.fromPortalId = portalId

  local firePos = firePosition(orbIndex)
  if world.lineCollision(mcontroller.position(), firePos) then return end
  
  local pos = fromPortal and world.entityPosition(portalId) or firePosition(orbIndex)
  local dir = fromPortal and aimVector(world.entityPosition(portalId)) or aimVector(firePosition(orbIndex))

  local projectileId = world.spawnProjectile(
    self.projectileType .. orbIndex, pos, activeItem.ownerEntityId(), dir, false, params
  )
  if projectileId then
    storage.projectileIds[orbIndex] = projectileId
    -- mark orb's last origin as "from portal" (2) or "from orbit" (1)
    storage.projectileOutLast[orbIndex] = fromPortal and 2 or 1
    self.cooldownTimer = self.cooldownTime
    animator.playSound("fire")
    applyImpulse(orbIndex, vec2.mul(dir, -self.projectileSpeed), false)
  end
end


function doOrbReturnAction(orbIndex, fromPortal, returnVelocity)
  animator.playSound("impact")
  local params = copy(root.projectileConfig("legrain_action"))
  local col = fromPortal and {0,0,0} or config.getParameter("rainColors")[orbIndex]
  params.parametersOrbReturn.actionOnReap[1].list[1].body[1].specification.color = col
  doParticleAction(firePosition(orbIndex), {actionOnReap = params.parametersOrbReturn.actionOnReap}, 1)

  -- TODO: fix the particles...
  -- params.parametersOrbReturn.actionOnReap[1].list[1].body[1].specification = {kind = "rain_spark"..orbIndex}
  -- doParticleAction(firePosition(orbIndex), {actionOnReap = params.parametersOrbReturn.actionOnReap}, 1)

  if returnVelocity then
    applyImpulse(orbIndex, vec2.sub(returnVelocity, mcontroller.velocity()), true)
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
      applyImpulse(orbIndex, vel, true)
    else
      -- degenerate case, fallback poke
      self.orbOffsetVel[orbIndex] = {-3, 0}
    end
  end
end


function checkProjectiles(silent)
  for i, projectileId in ipairs(storage.projectileIds) do
    if projectileId and not world.entityExists(projectileId) then
      storage.projectileIds[i] = false
      if storage.projectileOutLast[i] then
        if not silent then
          doOrbReturnAction(i, storage.projectileOutLast[i] == 2, self.pendingReturns[projectileId])

        end

        self.pendingReturns[projectileId] = nil
        storage.projectileOutLast[i] = false
      end
    end
  end
end


function nextOrb()
  for i = 1, self.orbTotal do
    if not storage.projectileIds[i] then
      return i
    end
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





function checkPortal()
  if storage.portalId and not world.entityExists(storage.portalId) then
    self.portalActive = false
    storage.portalId = false
    if self.portalActiveLast then
      -- portal collapsed non-manually
      doPortalCollapseAction()
    end

  elseif storage.portalId and world.entityExists(storage.portalId) then
    self.portalActive = true
  end

  self.portalActiveLast = self.portalActive
end


function activatePortal()
  animator.playSound("shieldOn")
  --animator.playSound("shieldLoop", -1)

  if targetValid(activeItem.ownerAimPosition()) then
    animator.playSound("fire")
    createPortal()
    checkPortal()
  else
    -- maybe make a little blocking indicator poof?
    local params = copy(root.projectileConfig("legrain_action"))
    params.parametersOrbReturn.actionOnReap[1].list[1].body[1].specification.color = {0,0,0}
    doParticleAction(activeItem.ownerAimPosition(), {actionOnReap = params.parametersOrbReturn.actionOnReap}, 1)

    return
  end
end


function collapsePortal(portalId)
  if portalId and world.entityExists(portalId) then
    sendSafely(storage.projectileIds, "triggerReturn")
    
    self.portalActiveLast = false
    doPortalCollapseAction()

    world.sendEntityMessage(portalId, "collapse")
  end
end


function doPortalCollapseAction()
  for i, v in ipairs(storage.projectileOutLast) do
    -- any orbs that are marked as having emerged from a portal will divert back to player
    -- because their portal collapsed, so they should be marked as not from a portal
    -- so that the return fx is correct
    if v == 2 then storage.projectileOutLast[i] = 1 end
  end

  sendSafely(storage.projectileIds, "setTargetPosition", false)
end


function targetValid(aimPos)
  local focusPos = focusPosition()
  return --world.magnitude(focusPos, aimPos) <= self.maxCastRange
    --and
  not world.lineTileCollision(mcontroller.position(), focusPos)
      and not world.lineTileCollision(focusPos, aimPos)
end


function focusPosition()
  return vec2.add(mcontroller.position(), activeItem.handPosition(animator.partPoint("glove", "focalPoint")))
end


function createPortal()
  local aimPosition = activeItem.ownerAimPosition()
  local fireDirection = world.distance(aimPosition, focusPosition())[1] > 0 and 1 or -1
  local pOffset = {fireDirection * (self.projectileDistance or 0), 0}
  local basePos = activeItem.ownerAimPosition()

  local pCount = 1

  for i = 1, 1 do
    local projectileId = world.spawnProjectile(
      "rainbowportal",
      vec2.add(basePos, pOffset),
      activeItem.ownerEntityId(),
      pOffset,
      false,
      pParams
    )

    if projectileId then storage.portalId = projectileId end
    pOffset = vec2.rotate(pOffset, (2 * math.pi) / pCount)
  end
end



-- MISC?




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


function doParticleAction(position, pParams, count)
  local c = count or 1
  for i = 1, c do world.spawnProjectile("legrain_action", position, activeItem.ownerEntityId(), {0,0}, false, pParams) end
end