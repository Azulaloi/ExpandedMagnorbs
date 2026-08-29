require "/scripts/vec2.lua"
require "/scripts/util.lua"
require "/scripts/status.lua"
require "/scripts/activeitem/stances.lua" 
require "/scripts/az_cues.lua"
require "/scripts/az_actions.lua"
require "/scripts/az_dynamics.lua"
require "/scripts/az_input.lua"


-- TODO: internalize stances.lua maybe

-- Norb projectile flags
ORB_FROM_ORBIT, ORB_FROM_PORTAL = 1,2

function initTune()
  local defaults = {
    throwKick = 0.75, -- Impulse scale for firing orbs
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
    armAxial = 0.06, -- Mult for axial recoil felt by arm
    armK = 60, -- Spring konstant for arm spring.
    armDamp = 10, -- Damping value for arm spring.
    armAngularClamp = {-0.25, 0.25}, -- min, max
    armAxialClamp = {-0.75, 0.25}, -- min, max

    formationHandoff = 0.4,

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

    input = {
      holdThreshold = 0.15, 
      doubleTapWindow = 0.3
    }
  }

  self.tune = sb.jsonMerge(defaults, config.getParameter("tune", {}))
end



function init()
  rig = self

  activeItem.setCursor("/cursors/reticle0.cursor") -- TODO: custom cursor management
  
  self.projectileType = config.getParameter("projectileType")
  self.projectileParameters = config.getParameter("projectileParameters")
  self.projectileParameters.power = self.projectileParameters.power * root.evalFunction("weaponDamageLevelMultiplier", config.getParameter("level", 1))
  self.cooldownTime = config.getParameter("cooldownTime", 0)
  self.cooldownTimer = self.cooldownTime
  self.level = config.getParameter("level")


  self.sequenced = config.getParameter("sequenced", false)
  self.projectileSpeed = root.projectileConfig(projectileName(1)).speed

  self.orbTotal = config.getParameter("orbTotal") -- kinda want to put this in a magnorb block
  self.orbitRate = config.getParameter("orbitRate", 1) * -2 * math.pi   -- magnorb block or tune block?

  self.debugHideRing = false
  self.hasOrbEmitters = config.getParameter("hasOrbEmitters", false)


  self.formation = nil
  self.formationBlend = 0 -- current blend factor  
  self.formationGoal = 0 -- blend goal
  self.formationTime = 0.1 -- blend ramp duration
  self.orbVisualOverride = nil
  self.ringHalted = false


  initTune()
  initDynamics()
  initStances() -- need to read what all these built in stance functions actually do


  self.pendingReturns = {}
  message.setHandler("orbReturn", function(_, _, projId, velocity)
    self.pendingReturns[projId] = velocity
  end)

  storage.projectileIds = storage.projectileIds or {}
  storage.projectileFlags = storage.projectileFlags or {} -- I guess these are multipurpose? Should magportal keep its own flag set, or can everything share some kind of mechanism?
  for i = 1, self.orbTotal do
    storage.projectileIds[i] = storage.projectileIds[i] or false
    storage.projectileFlags[i] = storage.projectileFlags[i] or false
  end

  checkProjectiles(true)
  sendSafely(storage.projectileIds, "triggerResurrection")


  self.input = azInput.Grammar.new(self.tune.input)
  
  -- ability init
  self.abilities = {}
  for _, key in ipairs({"altAbility", "primaryAbility"}) do
    local abilityConfig = config.getParameter(key)
    if abilityConfig then
      for _, script in ipairs(abilityConfig.scripts) do require(script) end
      local magnability = _ENV[abilityConfig.class]:new(abilityConfig) -- Lua was named after the moon because it'll drive you crazy
      table.insert(self.abilities, magnability)
      magnability:init()
    end
  end

  animator.resetTransformationGroup("orbs")
  for i = 1, self.orbTotal do
    local home = storage.projectileIds[i] == false

    animator.setAnimationState("orb"..i, home and "orb" or "hidden")
    if self.hasOrbEmitters then 
      animator.setParticleEmitterActive("idleparticles"..i, home)
    end
  end

  setStance("idle")
  updateHand()
  resyncHandTracking()
end

function initDynamics()
  self.ringSpinner = azDynamics.Spinner.new(self.orbitRate * (storage.spinSign or 1), self.tune.ringSpinRelax)

  self.orbRho = {} -- rhadius
  self.orbDelta = {} -- dhelta
  self.orbTwist = {} -- tuh-wist


  self.orbSpinner = {}
  self.orbSpring = {}
  self.orbSpinAngle = {} -- differentiate objects from storage?
  
  for i = 1, self.orbTotal do
    self.orbSpinner[i] = azDynamics.Spinner.new(self.tune.orbSpinBase, self.tune.orbSpinRelax)
    self.orbSpinAngle[i] = 0

    self.orbSpring[i] = azDynamics.Spring2D.new(self.tune.springK, self.tune.springDamp)
    self.orbSpring[i]:reset({-1.5, 0}) -- TODO: read emerge offset from orb radius
  
    self.orbRho[i] = 0
    self.orbDelta[i] = 0
    self.orbTwist[i] = 0
  end

  self.armAngularSpring = azDynamics.Spring1D.new(self.tune.armK, self.tune.armDamp, self.tune.armAngularClamp)
  self.armAxialSpring = azDynamics.Spring1D.new(self.tune.armK, self.tune.armDamp, self.tune.armAxialClamp)
  self.handTracker = azDynamics.MomentumFrame.new(self.tune.deltaTracking)


  self.animTime = 0
  self.armAngle = 0
  self.orbAngle = 0



end

function uninit()
  for _, ability in ipairs(self.abilities) do
    if ability.uninit then ability:uninit() end
  end

  activeItem.setItemShieldPolys()
  activeItem.setItemDamageSources()

  -- Reset home offset of away projectiles, so they return to player center while item is stowed.
  sendSafely(storage.projectileIds, "setHomeOffset", {0, 0})
  createGhosts()
end

function update(dt, fireMode, shiftHeld)
  self.cooldownTimer = math.max(0, self.cooldownTimer - dt) -- If I kept a local clock, I could use epoch for times, right?

  updateStance(dt) -- ?
  checkProjectiles(false)
  -- ability check here


  for _, inputEvent in ipairs(self.input:step(fireMode, shiftHeld, dt)) do
    consumeInputEvent(inputEvent)
  end

  updateAim()
  for _, ability in ipairs(self.abilities) do ability:update(dt) end
  updateAnim(dt)
  updateHand()

  drawDebug()
end

function consumeInputEvent(event)
  -- if event.button == "alt" and event.type == "tap" then
  --   if self.formation then setFormation(nil)
  --   else setFormation(makeArcFormation(0.3, 0.75, {-1.5, 0}), 0.15) end
  --   return
  -- end
  
  for _, ability in ipairs(self.abilities) do
    if ability.consumeEvent and ability:consumeEvent(event) then return end
  end
end

























function setFormation(form, duration)
  if form then
    self.formation = form
    self.formationGoal = 1
    self.formationTime = duration or 0.1
    if form.assign == "nearest" then
      form.slotMap = bestCyclicAssignment(form.slots)
    end
    if form.haltRing then setRingHalted(true) end
    if form.haltSpin then setSpinHalted(true) end -- hmmm...
  else
    local f = self.formation
    if f and f.slots then
      if f.rephase ~= false then rephaseRing(f) end
      captureExitGaps(f)
    end
    self.formationGoal = 0
    setRingHalted(false)
    setSpinHalted(false)
  end
end

function setRingHalted(halted)
  self.ringHalted = halted
  self.ringSpinner:setHome(halted and 0 or (self.orbitRate * (storage.spinSign or 1)))
end

function setSpinHalted(halted) 
  -- really need to be able to control spinners individually. but that's a Spinner feature probably
  -- and Spinners are due for an upgrade anyway

  self.spinHalted = halted
  for i = 1, self.orbTotal do -- I write this line so often
    self.orbSpinner[i]:setHome(halted and 0 or self.tune.orbSpinBase)
  end
end

function setOrbVisualOverride(state) -- TODO: more robust override system
  self.orbVisualOverride = state
end

function stepFormation(dt)
  animator.resetTransformationGroup("orbs")

  local f = self.formation
  local blend = self.formationBlend
  if not f then


    animator.rotateTransformationGroup("orbs", -(self.armAngleOverride or self.armAngle or 0))
    return
  end


  local rate = dt / math.max(self.formationTime, 0.01)
  self.formationBlend = util.clamp(blend + (self.formationGoal > 0 and rate or -rate), 0, 1)
  blend = self.formationBlend


  if blend == 0 and self.formationGoal == 0 then
    if self.formationExitGap then
      local T = math.max(self.formationTime, 0.01)
      local scale = self.tune.formationHandoff or 0
      for i = 1, self.orbTotal do
        self.orbSpring[i]:kick(0, -(self.formationExitGap[i] or 0) * 1.5 / T * scale)
      end
      self.formationExitGap = nil
    end

    for i = 1, self.orbTotal do self.orbDelta[i], self.orbRho[i], self.orbTwist[i] = 0, 0, 0 end
    self.formation = nil
    animator.rotateTransformationGroup("orbs", -(self.armAngleOverride or self.armAngle or 0))
    return
  end


  local armBlend = (f.frame == "arm") and blend or 0
  animator.rotateTransformationGroup("orbs", -(self.armAngleOverride or self.armAngle or 0) * (1 - armBlend))
  if f.groupOffset then
    animator.translateTransformationGroup("orbs", vec2.mul(f.groupOffset, blend))
  end


  local facing = mcontroller.facingDirection()
  for i = 1, self.orbTotal do -- who up iterating they orbs
    local slot = f.slots[(f.slotMap and f.slotMap[i]) or i]
    local orbitAngle = (self.orbAngle * facing) + 2 * math.pi * ((i - 2) / self.orbTotal)
    self.orbDelta[i] = normalizeAngle((slot.angle or 0) - orbitAngle) * blend
    self.orbRho[i] = (slot.radius or 0) * blend

    if slot.orientation then
      local gap = normalizePeriodic(slot.orientation - self.orbSpinAngle[i] * facing, f.alignPeriod)
      self.orbTwist[i] = gap * blend
    else
      self.orbTwist[i] = 0
    end
  end
end


function makeArcFormation(spaceFactor, radius, groupOffset, opts) -- TODO: jiggle formations
  opts = opts or {}
  local slots = {}
  for i = 1, self.orbTotal do
    slots[i] = {
      angle = 2 * math.pi * spaceFactor * ((i - 2) / self.orbTotal),  -- im so sick of writing this
      radius = radius,
      orientation = opts.orientation
    }
  end
  return {
    frame = "arm", 
    haltRing = true, 
    haltSpin = opts.orientation ~= nil,
    alignPeriod = opts.alignPeriod,
    assign = opts.assign,
    groupOffset = groupOffset, 
    slots = slots
  }
end




function bestCyclicAssignment(slots)
  local q = self.orbTotal
  local facing = mcontroller.facingDirection()
  local orbit = {}
  for i = 1, q do
    orbit[i] = (self.orbAngle * facing) + 2 * math.pi * ((i - 2) / q)
  end

  local bestShift, bestCost = 0, math.huge
  for shift = 0, q - 1 do
    local cost = 0
    for i = 1, q do
      local foo = ((i - 1 + shift) % q) + 1
      cost = cost + math.abs(normalizeAngle((slots[foo].angle or 0) - orbit[i]))
    end
    if cost < bestCost then bestCost, bestShift = cost, shift end
  end

  local arrange = {}
  for i = 1, q do arrange[i] = ((i - 1 + bestShift) % q) + 1 end
  return arrange
end

function rephaseRing(f) -- going to have to redo this for orbs with identity (which is planned)
  local facing = mcontroller.facingDirection()
  local sx, sy = 0, 0
  for i = 1, self.orbTotal do
    local slot = f.slots[(f.slotMap and f.slotMap[i]) or i]
    local a = (slot.angle or 0) - 2 * math.pi * ((i - 2) / self.orbTotal)
    sx = sx + math.cos(a)
    sy = sy + math.sin(a)
  end

  if sx ~= 0 or sy ~= 0 then
    self.orbAngle = math.atan(sy, sx) * facing
  end
end




function captureExitGaps(f) -- need to redo this. god I want real physics
  local facing = mcontroller.facingDirection()
  self.formationExitGap = {}
  for i = 1, self.orbTotal do
    local slot = f.slots[(f.slotMap and f.slotMap[i]) or i]
    local orbitAngle = (self.orbAngle * facing) + 2 * math.pi * ((i - 2) / self.orbTotal)
    self.formationExitGap[i] = normalizeAngle((slot.angle or 0) - orbitAngle)
  end
end





































function createGhosts()
 -- TODO: port ghost behaviour to normal norbs

   local params = copy(self.projectileParameters)
  params.ghost = true
  params.returning = true
  params.ignoreTerrain = true
  params.power = 0
  params.damageTeam = {type = "passive"}
  params.timeToLive = 2
  -- params.processing = "?multiply=FFFFFF88"
  params.processing = "?multiply=E3E3E388" -- read ghost directives from item params

  for i = 1, self.orbTotal do
    if storage.projectileIds[i] == false then
      local pid = world.spawnProjectile(projectileName(i), firePosition(i), 
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


function doOrbReturnAction(orbIndex, fromPortal, returnVelocity)
  playAnimatorSoundSafely("impact") -- todo: "catch" sound
  local orbPos = firePosition(orbIndex)

  if returnVelocity then
    applyImpulse(orbIndex, vec2.sub(returnVelocity, mcontroller.velocity()), nil, self.tune.catchKick)
  else
    -- No return velocity packet, orb returned through other means (reaped, was stowed, edge case)
    -- Synthesize a generic arrival packet.

    local handBase = vec2.add(mcontroller.position(), activeItem.handPosition({0, 0}))
    local toOrb = world.distance(firePosition(orbIndex), handBase)
    if vec2.mag(toOrb) > 0.5 then
      local spinSign = self.ringSpinner.vel >= 0 and 1 or -1
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

  -- for _, ability in ipairs(self.abilities) do
    -- if ability.onOrbReturn then ability:onOrbReturn(orbIndex, fromPortal, returnVelocity)
  -- end
end


function fire(orbIndex)
  local params = copy(self.projectileParameters)
  params.powerMultiplier = activeItem.ownerPowerMultiplier()
  params.ownerAimPosition = activeItem.ownerAimPosition()

  local firePos = firePosition(orbIndex)
  if world.lineCollision(mcontroller.position(), firePos) then return end

  local aimVec = aimVector(firePos)

  local projectileId = world.spawnProjectile(
    projectileName(orbIndex), firePos, 
    activeItem.ownerEntityId(), aimVec, 
    false, params
  )

  if projectileId then
    storage.projectileIds[orbIndex] = projectileId
    storage.projectileFlags[orbIndex] = 1 -- 1 means "from orbit", 2 means "from portal" -- hmm...
    storage.lastFired = orbIndex
    self.cooldownTimer = self.cooldownTime
    animator.playSound("fire") -- playsound SAFELY??? why does chucklefish insist on making everything difficult
    applyImpulse(
      orbIndex, vec2.mul(aimVector(firePos), -self.projectileSpeed), 
      {spring = false, orbSpin = false}, self.tune.throwKick
    )
    -- Since the orb is departing, reset its spin (regardless of whether firing added any)
    self.orbSpinner[orbIndex]:reset()


    -- and then set-specific particle actions?
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
    if not storage.projectileIds[i] then return i end -- magportal wants to check isDiving here
  end
end












































































-- ANIM DYNAMICS


function updateAnim(dt)
  self.animTime = self.animTime + dt

  activeItem.setArmAngle((self.armAngleOverride or self.armAngle) + self.armAngularSpring:step(dt))

  -- Drives the arcane arm mechanism via quantized spring
  -- TODO: do some side-by-side tests to compare smoothness and check the math
  local axial = self.armAxialSpring:step(dt)
  local S = 2
  local d = 2 * math.floor(axial * 8 * S + 0.5)
  animator.resetTransformationGroup("glove")
  animator.translateTransformationGroup("glove", {d / (16 * S), 0})
  updateArmFrame(d, S)

  self.orbAngle = self.orbAngle + self.ringSpinner:step(dt)

  -- animator.resetTransformationGroup("orbs")
  -- animator.rotateTransformationGroup("orbs", -(self.armAngle or 0))
  stepFormation(dt)


  -- Track and trigger hand frame disjunction
  local facing = mcontroller.facingDirection()
  if facing ~= self.lastFacing then resyncHandTracking() end
  self.lastFacing = facing

  -- Track and inject hand frame momentum
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

  -- Operate upon thy orbs
  for i = 1, self.orbTotal do
    local home = storage.projectileIds[i] == false

    -- TODO: jiggle module for azDynamics? 
    -- just a "waverator" (could be useful elsewhere too)? 
    -- or maybe integrate jiggle with the other physics?
    
    local J = self.tune.jiggle
    local jx = math.sin(self.animTime * J.radialFrequency + i * J.radialPhase) * J.radialAmplitude
    local jy = math.cos(self.animTime * J.tangentialFrequency + i * J.tangentialPhase) * J.tangentialAmplitude

    -- self.orbDelta[i] = 0.4 * math.sin(self.animTime * 2 + i)   -- slosh along the ring
    -- self.orbRho[i]   = 0.3 * math.sin(self.animTime * 3 + i)   -- breathe in and out

    animator.resetTransformationGroup("orb"..i)
    self.orbSpinAngle[i] = self.orbSpinAngle[i] + self.orbSpinner[i]:step(dt)

    animator.rotateTransformationGroup("orb"..i, self.orbSpinAngle[i] * facing + self.orbTwist[i], {1.5, 0}) 
    -- TODO: derive the orb offset/radius? -- can't believe I'm still putting the damn offset derivation off
    -- TODO: should orb home pos radius affect ring torque?

    local offset = self.orbSpring[i]:step(dt)
    animator.translateTransformationGroup("orb"..i, {offset[1] + jx + self.orbRho[i], offset[2] + jy})

    animator.rotateTransformationGroup("orb"..i, (self.orbAngle * facing) + 2 * math.pi * ((i - 2) / self.orbTotal) + self.orbDelta[i])

    local shown = home and not self.debugHideRing
    local desired = shown and "orb" or "hidden"
    -- animator.setAnimationState("orb"..i, shown and "orb" or "hidden") -- need a way to test for anim props or otherwise do it safely
    if self.orbVisualOverride then
      animator.setAnimationState("orb"..i, self.orbVisualOverride)
    else
      -- animator.setAnimationState("orb"..i, shown and "orb" or "hidden")
      if not (desired == "orb" and animator.animationState("orb"..i) == "unshield") then
        animator.setAnimationState("orb"..i, desired)
      end
    end
    
    if self.hasOrbEmitters then 
      animator.setParticleEmitterActive("idleparticles"..i, shown)
    end

    if not home then
      world.sendEntityMessage(storage.projectileIds[i], "setHomeOffset", activeItem.handPosition(animator.partPoint("orb"..i, "orbPosition")))
    end
  end

  -- ability anim update
end


-- Directive-cropped sprites recenter themselves.
-- By cropping the arm frame on one side or the other,
-- the arm can be made to shift axially, which otherwise is not possible.
-- Note cost in drawables; at S==2 it's negligible.
function updateArmFrame(d, S) -- delta, Scalar
  local frame = "rotation"

  -- TODO: can't tell if the scaling actually increases smoothness
   if d ~= 0 then
    local size = 43 * S
    local N = math.max(0, -d)
    local M = math.max(0, d)
    local k = ((S - (N + M) % S) % S) / 2  -- symmetric pad for division in theory
    N = N + k
    M = M + k
    frame = string.format(
      "rotation?scalenearest=%d?crop=%d;0;%d;%d?scale=%s", -- arcane incantation
      S, N, size - M, size, 1 / S)
  end

  if frame ~= self.lastArmFrame or self.isFrontHand ~= self.lastArmHand then
    if self.isFrontHand then
      activeItem.setFrontArmFrame(frame)
    else
      activeItem.setBackArmFrame(frame)
    end

    if self.lastArmHand ~= nil and self.lastArmHand ~= self.isFrontHand then
      -- Bracer hand switched front/back, so reset the frame of whatever it used to be
      if self.lastArmHand then activeItem.setFrontArmFrame("rotation")
      else activeItem.setBackArmFrame("rotation") end
    end

    self.lastArmFrame, self.lastArmHand = frame, self.isFrontHand
  end
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
    
    -- We check for ringHalted to avoid degen spinSign (ringSpinner.home is 0 while halted)
    if flags.ring ~= false and not self.ringHalted then
      self.ringSpinner:kick(tanVel * self.tune.ringSpinKick, true)
      storage.spinSign = ((self.ringSpinner.home < 0) == (self.orbitRate < 0)) and 1 or -1
    end

    if flags.orbSpin ~= false then
      self.orbSpinner[orbIndex]:kick(tanVel * self.tune.orbSpinKick, true)
    end

    if flags.spring ~= false then
      self.orbSpring[orbIndex]:kick(
        vec2.dot(vel, radDir) * self.tune.springRad,
        tanVel * facing * self.tune.springTan
      )
    end
  end

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
end

function updateHand()
  local isFrontHand = (activeItem.hand() == "primary") == (mcontroller.facingDirection() < 0)
  animator.setGlobalTag("hand", isFrontHand and "front" or "back")
  activeItem.setOutsideOfHand(isFrontHand)
  self.isFrontHand = isFrontHand -- Used by the arm cropper
end


function resyncHandTracking()
  self.handTracker:resync(vec2.add(mcontroller.position(), activeItem.handPosition({0, 0})))
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



-- HELPERS

function availableOrbCount()
  local available = 0
  for i = 1, self.orbTotal do
    if not storage.projectileIds[i] then
      available = available + 1
    end
  end
  return available
end

function projectileName(orbIndex)
  return self.sequenced and (self.projectileType .. orbIndex) or self.projectileType
end

function allNorbsAreHome() return availableOrbCount() == self.orbTotal end



function normalizeAngle(a)
  return (a + math.pi) % (2 * math.pi) - math.pi
end

-- Nearest representative of [a] in [-period/2, period/2]
function normalizePeriodic(a, period)
  period = period or (2 * math.pi) -- math.tau my dead wife
  return (a + period / 2) % period - period / 2
end



-- UTILITIES

function playAnimatorSoundSafely(soundName, ...)
  if animator.hasSound(soundName) then
    animator.playSound(soundName, ...)
  end
end

function drawDebug()
-- TODO: debug text drawer that just eats variables so I don't need to position them
end


function sendSafely(array, msg, ...)
  uponExtantEntities(array, function(_, v, ...) world.sendEntityMessage(v, msg, ...) end, ...)
end


function uponExtantEntities(array, handler, ...)
  for i, v in ipairs(array) do
    if v and world.entityExists(v) then
      handler(i, v, ...)
    end
  end
end

