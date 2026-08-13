-- Attempting to move portal-specific behaviours out into a module
-- Shares context with main script
-- Theoretically, this will become a magnorb ability if I ever develop the dynamic magnorb script

magPortal = {}

function magPortal.init()
  storage.portalId = storage.portalId or false
  self.portalActive = false

  magPortal.pendingFires = {}
  magPortal.spacePhase = 0
  magPortal.spacePrecess = 0
  magPortal.spaceSpin = azDynamics.Spinner.new(self.tune.portal.spinBase, self.tune.portal.spinRelax)
  magPortal.spaceOrbWorldPos = nil

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
  if (not self.portalActive) and (not storage.portalId) then magPortal.activate()
  else magPortal.collapse(storage.portalId) end
end


function magPortal.beginConduitFire(orbIndex)
  magPortal.pendingFires[orbIndex] = self.tune.portal.flickTime -- todo: make flick/dive name consistent
end

function magPortal.isDiving(orbIndex)
  return magPortal.pendingFires[orbIndex] ~= nil
end

-- Must run before updateAnim
function magPortal.update(dt)
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


function magPortal.activate()
  animator.playSound("shieldOn")
  --animator.playSound("shieldLoop", -1)

  if magPortal.targetValid(activeItem.ownerAimPosition()) then
    animator.playSound("fire")
    magPortal.createPortal()
    magPortal.checkPortal()
  else
    azActions.processAt(
      azActions.makeParticleAction("astraltearsparkle1", 6), 
      activeItem.ownerAimPosition()
    )
    return
  end
end


function magPortal.collapse(portalId)
  if portalId and world.entityExists(portalId) then
    sendSafely(storage.projectileIds, "triggerReturn")
    
    self.portalActiveLast = false
    magPortal.doCollapseAction()

    world.sendEntityMessage(portalId, "collapse")
  end
end


function magPortal.doCollapseAction()
  for i, v in ipairs(storage.projectileFlags) do
    -- any orbs that are marked as having emerged from a portal will divert back to player
    -- because their portal collapsed, so they should be marked as not from a portal
    -- so that the return fx is correct
    if v == 2 then storage.projectileFlags[i] = 1 end
  end

  sendSafely(storage.projectileIds, "setTargetPosition", false)
end


function magPortal.targetValid(aimPos)
  local focusPos = magPortal.focusPosition()
  return --world.magnitude(focusPos, aimPos) <= self.maxCastRange
    --and
  not world.lineTileCollision(mcontroller.position(), focusPos)
      and not world.lineTileCollision(focusPos, aimPos)
end




function magPortal.createPortal()
  local aimPosition = activeItem.ownerAimPosition()
  local fireDirection = world.distance(aimPosition, magPortal.focusPosition())[1] > 0 and 1 or -1
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


function magPortal.focusPosition()
  return vec2.add(
    mcontroller.position(), 
    activeItem.handPosition(animator.partPoint("glove", "focalPoint"))
  )
end
