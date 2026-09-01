require "/scripts/az-exnorb/magnability.lua"

MagPortal = Magnability:new()

function MagPortal:init()
  -- TODO: ability cursor management

  storage.portalId = storage.portalId or false
  self.portalActive = false

  self.pendingFires = {}
  self.spacePhase = 0
  -- self.spacePrecess = 3
  self.spaceSpin = azDynamics.Spinner.new(self.portal.spinBase, self.portal.spinRelax)
  self.spaceOrbWorldPos = nil

  self.holdConsumed = false
  self.lastCursor = nil

  self.ringLoopOn = false
  self.whirrTimer = 0
  
  self:checkUpdate(0)
  self.portalActiveLast = self.portalActive

  -- Statics for the scripted animator. 
  -- The space orb is drawn via scriptedAnimator because otherwise it can't go behind the player layer.
  local P = self.portal
  activeItem.setScriptedAnimationParameter("spaceOrbImage", "/magnorbs/legrainbow/orb1.png:orb?multiply=5a3c6eff")
  activeItem.setScriptedAnimationParameter("spaceOrbTune", {
    radius = P.radius, squash = P.squash, depthScale = P.depthScale,
    backDirectives = P.backDirectives, frontLayer = P.frontLayer, backLayer = P.backLayer 
  })
end


function MagPortal:update(dt)
  self:updateWindup(dt)

  for i, t in pairs(self.pendingFires) do
    t = t - dt
    if t <= 0 then
      self.pendingFires[i] = nil
      self:executeConduitFire(i)
    else
      self.pendingFires[i] = t
    end
  end

  local facing = mcontroller.facingDirection()
  local handBase = vec2.add(mcontroller.position(), activeItem.handPosition({0, 0}))
  for i, t in pairs(self.pendingFires) do
    local target = self.spaceOrbWorldPos or handBase
    local delta = world.distance(target, firePosition(i))
    local radDir, tanDir = azDynamics.frame(world.distance(firePosition(i), handBase), 0.3)
    if radDir then
      local remaining = math.max(t, dt)
      rig.orbSpring[i]:setVelocity(
        vec2.dot(delta, radDir) / remaining,
        vec2.dot(delta, tanDir) * facing / remaining
      )
    end
  end

  if self.windup and not self.windup.firing and not rig.input:held("alt") then
    self.holdConsumed = false
    self:releaseWindup()
  end

  self:applyState(dt)
end


function MagPortal:altTap()
  if self.portalActive or storage.portalId then
    self:collapse(storage.portalId)
  elseif availableOrbCount() < rig.orbTotal then
    sendSafely(storage.projectileIds, "triggerReturn") -- recall strays
  end
end

function MagPortal:presentSpaceOrb(handBase, dt)
  local P = self.portal -- seriously gotta rename this block
  if self.portalActive then
    self.spacePhase = self.spacePhase + self.spaceSpin:step(dt)
  end

  local offset = azDynamics.squashedOrbit(P.radius, P.squash, self.spacePhase)
  self.spaceOrbWorldPos = vec2.add(handBase, offset)

  activeItem.setScriptedAnimationParameter("spaceOrbActive", self.portalActive)
  activeItem.setScriptedAnimationParameter("spaceOrbPhase", self.spacePhase)
  activeItem.setScriptedAnimationParameter("spaceOrbCenter", handBase)
end


function MagPortal:updateCursor(state, charge) -- TODO: make mod-local duplicates of these cursors and store them in a const
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

  if c ~= self.lastCursor then
    activeItem.setCursor(c)
    self.lastCursor = c
  end
end

function MagPortal:uninit()
  animator.stopAllSounds("ringWhirr")
end











function MagPortal:consumeEvent(event) -- TODO: rename to consumeInputEvent...
  -- Does life ever feel like a forest of ifs?
  if event.button == "primary" and event.type == "press" and self.portalActive then
    if rig.cooldownTimer == 0 then
      local orbIndex = nextOrb()
      if orbIndex then
        self:beginConduitFire(orbIndex)
        rig.cooldownTimer = rig.cooldownTime
        animator.playSound("fire")
      end
    end
    return true
  end

  if event.button ~= "alt" then return false end
  if event.shift then return true end -- TODO: whatever it was  -- shift-alt hold -> implode windup (if portal active, otherwise reave windup)

  if event.type == "tap" then self:altTap()
  elseif event.type == "holdStart" then self:beginWindup()
  elseif event.type == "holdRelease" then
    if self.holdConsumed then
      self.holdConsumed = false
      self:releaseWindup()
    else
      self:altTap()
    end
  end

  return true
end

function MagPortal:animUpdate(dt)
  self:presentSpaceOrb(rig.handBase, dt)
    -- magPortal.presentBolts(handBase, dt) -- TODO: rainbolts!
end




-------------------------------------------------------------

-- NEW WACKY STATE MACHINE STUFF

-------------------------------------------------------------


function MagPortal:applyState(dt) -- inconsistent phase/state naming
  local state = self:phase()
  local charge = self:getCharge()
  self:updateCursor(state, charge)
  self:applyRingLoop(dt)

  -- local stance

  rig.ringSpinner:setHome(
    rig.orbitRate 
    * (storage.spinSign or 1) 
    * (1 + (self.reave.spinMult - 1) * charge ^ 0.4) -- this is ass
  )
end

function MagPortal:beginWindup()
  if not self:mayBeginWindup() then
    self.holdConsumed = true
    -- animator.playSound("impact") -- TODO: make a thing of sounds
    return
  end

  self.holdConsumed = true
  self.windup = {
    time = rig.tune.input.holdThreshold, -- TODO: fix this weird crossref param... 
    mode = storage.portalId and "detonate" or "open",
    firing = false
  }

  rig.input:setBridge("alt")

  -- animator.playSound("shieldOn") -- TODO: real sound
  -- sendSafely(storage.projectileIds, "triggerReturn")

  self.windup.cues = azCues.Sequence.new({
    {t = (self.reave.maxCharge - rig.tune.input.holdThreshold) * 0.5, fn = function() 
      -- animator.playSound("whirlReady") 
    end},
    {t = self.reave.maxCharge - rig.tune.input.holdThreshold, fn = function()
        animator.playSound("whirlReady")
      end}
  })

  if not allNorbsAreHome() then
    sendSafely(storage.projectileIds, "triggerReturn") -- TODO: "burst return" (return with fx and instant vel change like psynorbs)
  end
end


function MagPortal:updateWindup(dt)
  local w = self.windup
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



function MagPortal:releaseWindup()
  rig.input:setBridge(nil)
  local w = self.windup
  if not w or w.firing then return end

  local target = self:resolveTarget(w.mode)
  local ok = (
    self:getCharge() >= 1
    and target ~= nil  
    and status.overConsumeResource("energy", self.reave.castEnergy) -- all these portal and reave blocks should be in like, "cfg" or something
    and allNorbsAreHome()
  )
  
  -- if w.mode == "detonate" then
  --   ok = ok and storage.portalId and world.entityExists(storage.portalId)
  -- end
  if not ok then self:fizzle() return end

  w.firing = true
  w.power = self:getCharge() -- fix calling this twice
  w.target = target
  

  -- animator.playSound()


  w.cues = azCues.Sequence.new({
    {t = 0, fn = function() 
      self:doReaveFireAction(w) -- okay maybe I need to think more about the hook naming convention thing 
    end},
    {t = self.reave.fireBeat, fn = function()

      if w.mode == "open" then 
        self:resolveOpen(w) 
        self:doReaveFormationBurstAction(w)
      else 
        self:resolveDetonate(w)
        self:doReaveDetonationBurstAction(w) 
      end

      self.windup = nil
    end}
  })
end

function MagPortal:fizzle()
  rig.input:setBridge(nil)
  self.windup = nil
  -- magPortal.setState("idle")
  -- magPortal.restoreRing()
  -- animator.playSound("impact") -- TODO: actual sound
  for i = 1, rig.orbTotal do
    if storage.projectileIds[i] == false then
      rig.orbSpring[i]:kick(
        -self.reave.fizzleKick, 
        (i % 2 == 0) and self.reave.fizzleKick or -self.reave.fizzleKick
      )
    end
  end
end





























-- THE GIANT GAPS ARE SO I CAN SEE THE SECTIONS ON MY VSCODE MINIMAP THING

-------------------------------------------------------------

-- TRIGGERS AND ACTIONS AND STUFF LIKE THAT KINDA

-------------------------------------------------------------


-- Trigger orbIndex to dive for conduit fire.
function MagPortal:beginConduitFire(orbIndex)  -- TODO: rename to transit fire maybe?
  rig.orbLocks[orbIndex] = true
  self.pendingFires[orbIndex] = self.portal.flickTime -- todo: make flick/dive name consistent
end


-- Fire a norb through the portal. Called after dive period ends.
function MagPortal:executeConduitFire(orbIndex)
  local portalUp = storage.portalId and world.entityExists(storage.portalId)

  local params = copy(rig.projectileParameters)
  params.powerMultiplier = activeItem.ownerPowerMultiplier()
  params.ownerAimPosition = activeItem.ownerAimPosition()
  params.fromPortal = portalUp
  params.fromPortalId = portalUp and storage.portalId or nil

  local pos = portalUp and world.entityPosition(storage.portalId) or firePosition(orbIndex)
  local dir = aimVector(pos)

  local projectileId = world.spawnProjectile(
    projectileName(orbIndex), pos, activeItem.ownerEntityId(), dir, false, params
  )
  if projectileId then
    storage.projectileIds[orbIndex] = projectileId
    storage.projectileFlags[orbIndex] = portalUp and ORB_FROM_PORTAL or ORB_FROM_ORBIT
    storage.lastFired = orbIndex
    applyImpulse(orbIndex, vec2.mul(dir, -rig.projectileSpeed), {spring = false, orbSpin = false}, rig.tune.throwKick)
    rig.orbSpinner[orbIndex]:reset()
  end

  rig.orbSpring[orbIndex]:reset()
  self.spaceSpin:kick(self.portal.transitKick, false)
  rig.orbLocks[orbIndex] = false

  -- intentional omitted onOrbFired
end


-- Collapse the portal.
function MagPortal:collapse(portalId)
  if portalId and world.entityExists(portalId) then
    sendSafely(storage.projectileIds, "triggerReturn")
    
    self.portalActiveLast = false
    self:doCollapseAction()

    world.sendEntityMessage(portalId, "collapse")
    storage.portalId = false
    self.portalActive = false
  end
end


-- This should probably be, like, FX. Also, I should smooth the flow of action/fx execution. Like, some are cued, some are chained, etc. Should be more consistent.
function MagPortal:doCollapseAction()
  for i, v in ipairs(storage.projectileFlags) do
    -- any orbs that are marked as having emerged from a portal will divert back to player
    -- because their portal collapsed, so they should be marked as not from a portal
    -- so that the return fx is correct
    if v == ORB_FROM_PORTAL then storage.projectileFlags[i] = ORB_FROM_ORBIT end
  end

  sendSafely(storage.projectileIds, "setTargetPosition", false)
end


function MagPortal:resolveOpen(w)
  local portal = world.spawnProjectile("rainbowportal", w.target, activeItem.ownerEntityId(), {0,0}, false, {timeToLive = self.portal.timeToLive})
  if portal then storage.portalId = portal end
  self:checkUpdate(0)
  self.spaceSpin:kick(self.portal.transitKick, false)
end


function MagPortal:resolveDetonate(w)
  self:collapse(storage.portalId)

end


-- Effects at bracer on reave
function MagPortal:doReaveFireAction(w)
  animator.playSound("fire")

  for i = 1, rig.orbTotal do
    if storage.projectileIds[i] == false then
      rig.orbSpring[i]:kick(-2.0, 0) -- radial kick
    end
  end
  rig.armAxialSpring:kick(-4.0) -- arm recoil
end


-- Effects at portal target location on reave strike (very small delay between bracer effect and target effect)
function MagPortal:doReaveFormationBurstAction(w)
  azActions.processAt(azActions.loopGroup({
    azActions.makeParticleAction("astraltearsparkle1"),
    azActions.makeParticleAction("astraltearsparkle2") -- don't ship using vanilla particles
  }, 4), w.target)

  -- local prePortalBurst = world.spawnProjectile( -- PLACEHOLDER...
  --   "roar", --"roar" "ngravityexplosion"
  --   w.target, 
  --   activeItem.ownerEntityId(), 
  --   {0,0}, 
  --   false, {})
end


function MagPortal:doReaveDetonationBurstAction(w)
  -- Since it's the item triggering the detonation, should the item create the explosion?
  -- It's probably just easier this way.
end


















function MagPortal:ringExcess()
  local base = math.abs(rig.orbitRate)
  local span = base * (self.reave.spinMult - 1)
  return util.clamp((math.abs(rig.ringSpinner.vel) - base) / math.max(span, 0.001), 0, 1)
end

function MagPortal:applyRingLoop(dt)
  local excess = self:ringExcess()

  if not self.ringLoopOn and excess > 0.05 then
    animator.playSound("ringWhirr", -1)
    self.ringLoopOn = true
    self.whirrTimer = 0
  elseif self.ringLoopOn and excess < 0.02 then
    animator.stopAllSounds("ringWhirr")
    self.ringLoopOn = false
  end

  if not self.ringLoopOn then return end

  local step = self.reave.whirrAdjust
  self.whirrTimer = self.whirrTimer - dt
  if self.whirrTimer <= 0 then
    animator.setSoundPitch("ringWhirr", 0.7 + 0.9 * excess, step)
    animator.setSoundVolume("ringWhirr", 0.2 + 0.8 * excess, step)
    self.whirrTimer = step
  end
end




























-------------------------------------------------------------

-- HELPERS

-------------------------------------------------------------

function MagPortal:portalTarget() -- TODO: offset from hit by portal radius
  local focusPos = vec2.add(mcontroller.position(), activeItem.handPosition({0,0}))
  local aim = activeItem.ownerAimPosition()
  local hit = world.lineCollision(focusPos, aim)
  if not hit then return aim else return hit end
end


function MagPortal:resolveTarget(mode)
  if mode == "detonate" then
    if storage.portalId and world.entityExists(storage.portalId) then
      -- Return detonation position
      return world.entityPosition(storage.portalId)
    end
    -- Fallback for detonate with no portal
    return nil
  end
  -- Probably firing, return aim target
  return self:portalTarget()
end


function MagPortal:phase()
  if self.windup then return self.windup.firing and "firing" or "charging" end
  return "idle"
end


function MagPortal:mayBeginWindup()
  return self:phase() == "idle" and status.resource("energy") >= self.reave.castEnergy
end


function MagPortal:getCharge()
  local windup = self.windup
  if not windup then return 0 end
  if windup.power then return windup.power end
  local hold, max = rig.tune.input.holdThreshold, self.reave.maxCharge
  return util.clamp((windup.time - hold) / math.max(max - hold, 0.001), 0, 1)
end


function MagPortal:checkUpdate(dt)
  if storage.portalId and not world.entityExists(storage.portalId) then
    self.portalActive = false
    storage.portalId = false
    if self.portalActiveLast then
      -- portal collapsed non-manually
      self:doCollapseAction()
    end

  elseif storage.portalId and world.entityExists(storage.portalId) then
    self.portalActive = true
  end

  self.portalActiveLast = self.portalActive
end


function MagPortal:isDiving(orbIndex) -- fossil function outmoded by isDiving -- was I delirious when I wrote that?
  return self.pendingFires[orbIndex] ~= nil
end



-- TODO: init param blocks with defaults like before
    -- reave = {
    --   maxCharge = 1.25,
    --   spinMult = 24.0,
    --   fizzleKick = 2.0,
    --   castEnergy = 50,
    --   fireBeat = 0.12,
    --   whirrAdjust = 0.1
    -- }
    -- portal = {
    --   radius = 2.5,
    --   squash = -0.15,
    --   -- precessRate = 3.0,
    --   spinBase = 2.5,
    --   spinRelax = 1.5,
    --   depthScale = 0.2, -- Shrink effect at "far" arc
    --   backDirectives = "?brightness=-45", -- Darkening effect of "far" arc
    --   frontLayer = "Player+1", -- Layer for near arc
    --   backLayer = "Player-1", -- Layer for far arc
    --   flickTime = 0.065, -- Time for an orb fired with portal up to "flick" into the space orb, after which it emerges from portal
    --   transitKick = 2.0,
    --   timeToLive = 24
    -- },