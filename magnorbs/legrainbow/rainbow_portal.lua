-- Attempting to move portal-specific behaviours out into a module
-- Shares context with main script
-- Theoretically, this will become a magnorb ability if I ever develop the dynamic magnorb script

-- This is driving me insane.
-- It's always the damn state machines.

magPortal = {}

function magPortal.init()
  storage.portalId = storage.portalId or false
  self.portalActive = false

  magPortal.pendingFires = {}
  magPortal.spacePhase = 0
  -- magPortal.spacePrecess = 0
  magPortal.spaceSpin = azDynamics.Spinner.new(self.tune.portal.spinBase, self.tune.portal.spinRelax)
  magPortal.spaceOrbWorldPos = nil

  magPortal.holdConsumed = false
  magPortal.lastCursor = nil

  magPortal.checkPortal()
  self.portalActiveLast = self.portalActive

  -- Statics for the scripted animator. 
  -- The space orb is drawn via scriptedAnimator because otherwise it can't go behind the player layer.
  local P = self.tune.portal
  activeItem.setScriptedAnimationParameter("spaceOrbImage", "/magnorbs/legrainbow/orb1.png:orb?multiply=5a3c6eff")
  activeItem.setScriptedAnimationParameter("spaceOrbTune", {
    radius = P.radius, squash = P.squash, depthScale = P.depthScale,
    backDirectives = P.backDirectives, frontLayer = P.frontLayer, backLayer = P.backLayer 
  })
end


function magPortal.altTap()
  if self.portalActive or storage.portalId then
    magPortal.collapse(storage.portalId)
  elseif availableOrbCount() < self.orbTotal then
    sendSafely(storage.projectileIds, "triggerReturn") -- recall strays
  end
end


-- Must run before updateAnim
function magPortal.update(dt)
  magPortal.updateWindup(dt)

  for i, t in pairs(magPortal.pendingFires) do
    t = t - dt
    if t <= 0 then
      magPortal.pendingFires[i] = nil
      magPortal.executeConduitFire(i)
    else
      magPortal.pendingFires[i] = t
    end
  end

  local facing = mcontroller.facingDirection()
  local handBase = vec2.add(mcontroller.position(), activeItem.handPosition({0, 0}))
  for i, t in pairs(magPortal.pendingFires) do
    local target = magPortal.spaceOrbWorldPos or handBase
    local delta = world.distance(target, firePosition(i))
    local radDir, tanDir = azDynamics.frame(world.distance(firePosition(i), handBase), 0.3)
    if radDir then
      local remaining = math.max(t, dt)
      self.orbSpring[i]:setVelocity(
        vec2.dot(delta, radDir) / remaining,
        vec2.dot(delta, tanDir) * facing / remaining
      )
    end
  end

  magPortal.applyState()
end


function magPortal.presentSpaceOrb(handBase, dt)
  local P = self.tune.portal
  if self.portalActive then
    magPortal.spacePhase = magPortal.spacePhase + magPortal.spaceSpin:step(dt)
  end

  local offset = azDynamics.squashedOrbit(P.radius, P.squash, magPortal.spacePhase)
  magPortal.spaceOrbWorldPos = vec2.add(handBase, offset)

  activeItem.setScriptedAnimationParameter("spaceOrbActive", self.portalActive)
  activeItem.setScriptedAnimationParameter("spaceOrbPhase", magPortal.spacePhase)
  activeItem.setScriptedAnimationParameter("spaceOrbCenter", handBase)
end


function magPortal.updateCursor(state, charge) -- TODO: make mod-local duplicates of these cursors and store them in a const
  local defaultCursor = "/cursors/reticle0.cursor"
  local readyCursor = "/cursors/chargeready.cursor"
  local chargeOneCursor = "/cursors/charge1.cursor"
  local chargeTwoCursor = "/cursors/charge2.cursor"

  local c = defaultCursor

  if state == "charging" or state == "firing" then
    c = (charge >= 1 and readyCursor)
      or (charge >= 0.5 and chargeTwoCursor)
      or chargeOneCursor
  end

  if c ~= magPortal.lastCursor then
    activeItem.setCursor(c)
    magPortal.lastCursor = c
  end
end




















-------------------------------------------------------------

-- NEW WACKY STATE MACHINE STUFF

-------------------------------------------------------------


function magPortal.applyState() -- inconsistent phase/state naming
  local state = magPortal.phase()
  local charge = magPortal.getCharge()
  magPortal.updateCursor(state, charge)

  -- local stance

  self.ringSpin:setHome(
    self.orbitRate 
    * (storage.spinSign or 1) 
    * (1 + (self.tune.reave.spinMult - 1) * charge ^ 0.4) -- this is ass. also it needs a cool whirring sound
  )
end


function magPortal.beginWindup()
  if not magPortal.mayBeginWindup() then
    magPortal.holdConsumed = true
    animator.playSound("impact") -- TODO: make a thing of sounds
    return
  end

  magPortal.holdConsumed = true
  magPortal.windup = {
    time = self.tune.input.holdThreshold,
    mode = storage.portalId and "detonate" or "open",
    firing = false
  }

  animator.playSound("shieldOn") -- TODO: real sound
  -- sendSafely(storage.projectileIds, "triggerReturn")

  magPortal.windup.cues = azCues.Sequence.new({
    {t = (self.tune.reave.maxCharge - self.tune.input.holdThreshold) * 0.5, fn = function() animator.playSound("impact") end},
    {t = self.tune.reave.maxCharge - self.tune.input.holdThreshold, fn = function() animator.playSound("impact") end}
  })
end


function magPortal.updateWindup(dt)
  local w = magPortal.windup
  if not w then return end
  w.cues:step(dt)

  if w.firing then return end
  w.time = w.time + dt

  -- if not status.overConsumeResource("energy", self.tune.reave.energyPerSecond * dt) then
  --   magPortal.fizzle()
  --   return
  -- end

  -- local charge = math.min(w.time / self.tune.reave.maxCharge, 1)

  -- self.ringSpin:setHome(
  --   self.orbitRate 
  --   * (storage.spinSign or 1) 
  --   * (1 + (self.tune.reave.spinMult - 1) * magPortal.getCharge() ^ 0.4) -- 
  -- )

  --chargeDirectives here
end


function magPortal.releaseWindup()
  local w = magPortal.windup
  if not w or w.firing then return end

  local target = magPortal.resolveTarget(w.mode)
  local ok = (
    magPortal.getCharge() >= 1
    and target ~= nil  
    and status.overConsumeResource("energy", self.tune.reave.castEnergy)
  )
  
  -- if w.mode == "detonate" then
  --   ok = ok and storage.portalId and world.entityExists(storage.portalId)
  -- end
  if not ok then magPortal.fizzle() return end

  w.firing = true
  w.power = magPortal.getCharge()
  w.target = target
  

  -- animator.playSound()


  w.cues = azCues.Sequence.new({
    {t = 0, fn = function() 
      magPortal.doReaveFireAction(w) 
    end},
    {t = self.tune.reave.fireBeat, fn = function()

      if w.mode == "open" then 
        magPortal.resolveOpen(w) 
        magPortal.doReaveFormationBurstAction(w)
      else 
        magPortal.resolveDetonate(w)
        magPortal.doReaveDetonationBurstAction(w) 
      end

      magPortal.windup = nil
    end}
  })
end


function magPortal.fizzle()
  magPortal.windup = nil
  -- magPortal.setState("idle")
  -- magPortal.restoreRing()
  animator.playSound("impact") -- TODO: actual sound
  for i = 1, self.orbTotal do
    if storage.projectileIds[i] == false then
      self.orbSpring[i]:kick(
        -self.tune.reave.fizzleKick, 
        (i % 2 == 0) and self.tune.reave.fizzleKick or -self.tune.reave.fizzleKick
      )
    end
  end
end






















-- THE GIANT GAPS ARE SO I CAN SEE THE SECTIONS ON MY VSCODE MINIMAP THING

-------------------------------------------------------------

-- TRIGGERS AND ACTIONS AND STUFF LIKE THAT KINDA

-------------------------------------------------------------


-- Trigger orbIndex to dive for conduit fire.
function magPortal.beginConduitFire(orbIndex)
  magPortal.pendingFires[orbIndex] = self.tune.portal.flickTime -- todo: make flick/dive name consistent
end


-- Fire a norb through the portal. Called after dive period ends.
function magPortal.executeConduitFire(orbIndex)
  local portalUp = storage.portalId and world.entityExists(storage.portalId)

  local params = copy(self.projectileParameters)
  params.powerMultiplier = activeItem.ownerPowerMultiplier()
  params.ownerAimPosition = activeItem.ownerAimPosition()
  params.fromPortal = portalUp
  params.fromPortalId = portalUp and storage.portalId or nil

  local pos = portalUp and world.entityPosition(storage.portalId) or firePosition(orbIndex)
  local dir = aimVector(pos)

  local projectileId = world.spawnProjectile(
    self.projectileType .. orbIndex, pos, activeItem.ownerEntityId(), dir, false, params
  )
  if projectileId then
    storage.projectileIds[orbIndex] = projectileId
    storage.projectileFlags[orbIndex] = portalUp and 2 or 1
    storage.lastFired = orbIndex
    applyImpulse(orbIndex, vec2.mul(dir, -self.projectileSpeed), {spring = false, orbSpin = false}, self.tune.throwKick)
    self.orbSpin[orbIndex]:reset()
  end

  self.orbSpring[orbIndex]:reset()
  magPortal.spaceSpin:kick(self.tune.portal.transitKick, false)
end


-- Collapse the portal.
function magPortal.collapse(portalId)
  if portalId and world.entityExists(portalId) then
    sendSafely(storage.projectileIds, "triggerReturn")
    
    self.portalActiveLast = false
    magPortal.doCollapseAction()

    world.sendEntityMessage(portalId, "collapse")
    storage.portalId = false
    self.portalActive = false
  end
end


-- This should probably be, like, FX. Also, I should smooth the flow of action/fx execution. Like, some are cued, some are chained, etc. Should be more consistent.
function magPortal.doCollapseAction()
  for i, v in ipairs(storage.projectileFlags) do
    -- any orbs that are marked as having emerged from a portal will divert back to player
    -- because their portal collapsed, so they should be marked as not from a portal
    -- so that the return fx is correct
    if v == 2 then storage.projectileFlags[i] = 1 end
  end

  sendSafely(storage.projectileIds, "setTargetPosition", false)
end


function magPortal.resolveOpen(w)
  local portal = world.spawnProjectile("rainbowportal", w.target, activeItem.ownerEntityId(), {0,0}, false, {timeToLive = self.tune.portal.timeToLive})
  if portal then storage.portalId = portal end
  magPortal.checkPortal()
  magPortal.spaceSpin:kick(self.tune.portal.transitKick, false)
end


function magPortal.resolveDetonate(w)
  magPortal.collapse(storage.portalId)

end


-- Effects at bracer on reave
function magPortal.doReaveFireAction(w)
  animator.playSound("fire")

  for i = 1, self.orbTotal do
    if storage.projectileIds[i] == false then
      self.orbSpring[i]:kick(-2.0, 0) -- radial kick
    end
  end
  self.armAxialSpring:kick(-4.0) -- arm recoil
end


-- Effects at portal target location on reave strike (very small delay between bracer effect and target effect)
function magPortal.doReaveFormationBurstAction(w)
  azActions.processAt(azActions.loopGroup({
    azActions.makeParticleAction("astraltearsparkle1"),
    azActions.makeParticleAction("astraltearsparkle2") -- don't ship using vanilla particles
  }, 4), w.target)

  local prePortalBurst = world.spawnProjectile( -- PLACEHOLDER...
    "roar", --"roar" "ngravityexplosion"
    w.target, 
    activeItem.ownerEntityId(), 
    {0,0}, 
    false, {})
end


function magPortal.doReaveDetonationBurstAction(w)
  -- Since it's the item triggering the detonation, should the item create the explosion?
  -- It's probably just easier this way.
end































-------------------------------------------------------------

-- HELPERS

-------------------------------------------------------------

function magPortal.portalTarget() -- TODO: offset from hit by portal radius
  local focusPos = vec2.add(mcontroller.position(), activeItem.handPosition({0,0}))
  local aim = activeItem.ownerAimPosition()
  local hit = world.lineCollision(focusPos, aim)
  if not hit then return aim else return hit end
end


function magPortal.resolveTarget(mode)
  if mode == "detonate" then
    if storage.portalId and world.entityExists(storage.portalId) then
      -- Return detonation position
      return world.entityPosition(storage.portalId)
    end
    -- Fallback for detonate with no portal
    return nil
  end
  -- Probably firing, return aim target
  return magPortal.portalTarget()
end


function magPortal.phase()
  if magPortal.windup then return magPortal.windup.firing and "firing" or "charging" end
  return "idle"
end


function magPortal.mayBeginWindup()
  return magPortal.phase() == "idle" and status.resource("energy") >= self.tune.reave.castEnergy
end


function magPortal.getCharge()
  local windup = magPortal.windup
  if not windup then return 0 end
  if windup.power then return windup.power end
  local hold, max = self.tune.input.holdThreshold, self.tune.reave.maxCharge
  return util.clamp((windup.time - hold) / math.max(max - hold, 0.001), 0, 1)
end


function magPortal.checkPortal()
  if storage.portalId and not world.entityExists(storage.portalId) then
    self.portalActive = false
    storage.portalId = false
    if self.portalActiveLast then
      -- portal collapsed non-manually
      magPortal.doCollapseAction()
    end

  elseif storage.portalId and world.entityExists(storage.portalId) then
    self.portalActive = true
  end

  self.portalActiveLast = self.portalActive
end


function magPortal.isDiving(orbIndex)
  return magPortal.pendingFires[orbIndex] ~= nil
end
