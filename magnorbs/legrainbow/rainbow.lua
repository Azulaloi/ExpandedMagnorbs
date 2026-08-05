require "/scripts/vec2.lua"
require "/scripts/util.lua"
require "/scripts/status.lua"
require "/scripts/activeitem/stances.lua"

function init()
  activeItem.setCursor("/cursors/reticle0.cursor")

  self.projectileType = config.getParameter("projectileType")
  self.projectileParameters = config.getParameter("projectileParameters")
  self.projectileParameters.power = self.projectileParameters.power * root.evalFunction("weaponDamageLevelMultiplier", config.getParameter("level", 1))
  self.cooldownTime = config.getParameter("cooldownTime", 0)
  self.cooldownTimer = self.cooldownTime
  self.orbTotal = config.getParameter("orbTotal")
  self.level = config.getParameter("level")
  self.shieldEnergyCost = config.getParameter("shieldEnergyCost", 50)

  initStances()
  storage.projectiles = storage.projectiles or {}
  storage.projectileIds = storage.projectileIds or {false, false, false, false, false}
  checkProjectiles()
  storage.projectileOutLast = storage.projectileOutLast or {false, false, false, false, false}

  storage.portalId = storage.portalId or false
  self.portalActive = false
  checkPortal()
  self.portalActiveLast = self.portalActive

  self.orbitRate = config.getParameter("orbitRate", 1) * -2 * math.pi

  animator.resetTransformationGroup("orbs")
  for i = 1, self.orbTotal do
    local home = storage.projectileIds[i] == false

    animator.setAnimationState("orb"..i, home and "orb" or "hidden")
    animator.setParticleEmitterActive("idleparticles"..i, home)
  end
  setOrbPosition(1)

  setStance("idle")
  updateHand()
end

function update(dt, fireMode, shiftHeld)
  self.cooldownTimer = math.max(0, self.cooldownTimer)

  updateStance(dt)
  checkProjectiles()
  checkPortal()

  if fireMode == "alt" and self.lastFireMode ~= "alt" and not status.resourceLocked("energy") then
    if (not self.portalActive) and (not storage.portalId) then activatePortal()
    else collapsePortal(storage.portalId) end
  end

  if fireMode == "primary" and self.lastFireMode ~= "primary" and (self.cooldownTimer == 0) then
    local nextOrbIndex = nextOrb()
    if nextOrbIndex then fire(nextOrbIndex, self.portalActive, storage.portalId) end
  end
  self.lastFireMode = fireMode

  animator.resetTransformationGroup("orbs")
  animator.rotateTransformationGroup("orbs", -self.armAngle or 0)
  for i = 1, self.orbTotal do
    local home = storage.projectileIds[i] == false

    animator.rotateTransformationGroup("orb"..i, self.orbitRate * dt)
    animator.setAnimationState("orb"..i, home and "orb" or "hidden")
    animator.setParticleEmitterActive("idleparticles"..i, home)
  end

  updateAim()
  updateHand()
  drawDebug()
end

function uninit()
  --local id = storage.portalIds[1]
  --if id then
  --    if world.entityExists(id) then
  --       world.sendEntityMessage(id, "kill")
  --    end
  --end

  --sendSafely({storage.portalId}, world.sendEntityMessage, "kill")

  activeItem.setItemShieldPolys()
  activeItem.setItemDamageSources()
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

function updateHand()
  local isFrontHand = (activeItem.hand() == "primary") == (mcontroller.facingDirection() < 0)
  animator.setGlobalTag("hand", isFrontHand and "front" or "back")
  activeItem.setOutsideOfHand(isFrontHand)
end

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
  end
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

function checkProjectiles()
  for i, projectileId in ipairs(storage.projectileIds) do
    if projectileId and not world.entityExists(projectileId) then
      storage.projectileIds[i] = false
      if storage.projectileOutLast[i] then
        local fromPortal = storage.projectileOutLast[i] == 2
        -- this method doesn't account for orbs that divert to the player bc portal collapsed

        doOrbReturnAction(i, fromPortal)
        storage.projectileOutLast[i] = false
      end
    end
  end
end

function doOrbReturnAction(orbIndex, fromPortal)
  animator.playSound("impact")
  local params = copy(root.projectileConfig("legrain_action"))
  local col = fromPortal and {0,0,0} or config.getParameter("rainColors")[orbIndex]
  params.parametersOrbReturn.actionOnReap[1].list[1].body[1].specification.color = col
  doParticleAction(firePosition(orbIndex), {actionOnReap = params.parametersOrbReturn.actionOnReap}, 1)
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

function setOrbPosition(spaceFactor, distance)
  for i = 1, self.orbTotal do
    animator.resetTransformationGroup("orb"..i)
    animator.translateTransformationGroup("orb"..i, {distance or 0, 0})
    animator.rotateTransformationGroup("orb"..i, 2 * math.pi * spaceFactor * ((i - 2) / self.orbTotal))
  end
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