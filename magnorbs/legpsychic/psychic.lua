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

  self.focusActive = false
  self.chargeActive = false

  initStances()
  storage.projectiles = storage.projectiles or {}
  storage.projectileIds = storage.projectileIds or {false}
  checkProjectiles()
  storage.projectileOutLast = storage.projectileOutLast or {false}

  self.orbitRate = config.getParameter("orbitRate", 1) * -2 * math.pi

  animator.resetTransformationGroup("orbs")
  for i = 1, self.orbTotal do
    animator.setAnimationState("orb"..i, storage.projectileIds[i] == false and "orb" or "hidden")
  end
  setOrbPosition(1)

  setStance("idle")
  updateHand()


end

function update(dt, fireMode, shiftHeld)
  self.cooldownTimer = math.max(0, self.cooldownTimer)

  updateStance(dt)
  checkProjectiles()

  if fireMode == "alt" and not status.resourceLocked("energy") then
    if self.lastFireMode ~= "alt" and not self.focusActive then 
      activateFocus() 
    end
  else
    self.focusActive = false
  end

  if fireMode == "alt" and not status.resourceLocked("energy") and shiftHeld and self.focusActive then
    self.chargeActive = true
  else 
    self.chargeActive = false
  end


  if fireMode == "primary" and self.lastFireMode ~= "primary" and (self.cooldownTimer == 0) then
    local nextOrbIndex = nextOrb()
    if nextOrbIndex then 
      fire(nextOrbIndex) 
    end

    --elseif self.lastFireMode == "alt" and self.focusActive then

  end
  self.lastFireMode = fireMode

  animator.resetTransformationGroup("orbs")
  animator.rotateTransformationGroup("orbs", -self.armAngle or 0)
  for i = 1, self.orbTotal do
    animator.rotateTransformationGroup("orb"..i, self.orbitRate * dt)
    animator.setAnimationState("orb"..i, storage.projectileIds[i] == false and "orb" or "hidden")
  end

  updateProjectiles()

  updateAim()
  updateHand()
  
  if self.focusActive then
    activeItem.setArmAngle(20)
  end

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

function fire(orbIndex)
  local params = copy(self.projectileParameters)
  params.powerMultiplier = activeItem.ownerPowerMultiplier()
  params.ownerAimPosition = activeItem.ownerAimPosition()
  
  local pos = firePosition(orbIndex)
  if world.lineCollision(mcontroller.position(), pos) then return end

  local dir = aimVector(firePosition(orbIndex))

  local projectileId = world.spawnProjectile(
    self.projectileType, pos, activeItem.ownerEntityId(), dir, false, params
  )
  if projectileId then
    storage.projectileIds[orbIndex] = projectileId
    storage.projectileOutLast[orbIndex] = true
    self.cooldownTimer = self.cooldownTime
    animator.playSound("fire")
  end
end

function checkProjectiles()
  for i, projectileId in ipairs(storage.projectileIds) do
    if projectileId and not world.entityExists(projectileId) then
      storage.projectileIds[i] = false
      if storage.projectileOutLast[i] then
        doOrbReturnAction(i)
        storage.projectileOutLast[i] = false
      end
    end
  end
end

function doOrbReturnAction(orbIndex)
  -- animator.playSound("impact")
  -- local params = copy(root.projectileConfig("legrain_action"))
  -- local col = fromPortal and {0,0,0} or config.getParameter("rainColors")[orbIndex]
  -- params.parametersOrbReturn.actionOnReap[1].list[1].body[1].specification.color = col
  -- doParticleAction(firePosition(orbIndex), {actionOnReap = params.parametersOrbReturn.actionOnReap}, 1)
end

function updateProjectiles()
  sendSafely(storage.projectileIds, "updateProjectile", activeItem.ownerAimPosition(), self.focusActive, self.chargeActive)
end

function activateFocus()
  self.focusActive = true
end

function deactivateFocus()

end

-- ANIM

function focusPosition()
  return vec2.add(mcontroller.position(), activeItem.handPosition(animator.partPoint("glove", "focalPoint")))
end

function updateHand()
  local isFrontHand = (activeItem.hand() == "primary") == (mcontroller.facingDirection() < 0)
  animator.setGlobalTag("hand", isFrontHand and "front" or "back")
  activeItem.setOutsideOfHand(isFrontHand)
end

-- BOILER

function firePosition(orbIndex)
  return vec2.add(mcontroller.position(), activeItem.handPosition(animator.partPoint("orb"..orbIndex, "orbPosition")))
end

function aimVector(firePos)
  return vec2.norm(world.distance(activeItem.ownerAimPosition(), firePos))
end

function targetValid(aimPos)
  local focusPos = focusPosition()
  return --world.magnitude(focusPos, aimPos) <= self.maxCastRange
    --and
  not world.lineTileCollision(mcontroller.position(), focusPos)
      and not world.lineTileCollision(focusPos, aimPos)
end

function setOrbPosition(spaceFactor, distance)
  for i = 1, self.orbTotal do
    animator.resetTransformationGroup("orb"..i)
    animator.translateTransformationGroup("orb"..i, {distance or 0, 0})
    animator.rotateTransformationGroup("orb"..i, 2 * math.pi * spaceFactor * ((i - 2) / self.orbTotal))
  end
end

-- UTIL

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

function drawDebug()
  local pos = mcontroller.position()
  world.debugText("focus:  " .. (self.focusActive and "true" or "false"), vec2.add(pos, {4, 2}), "green")
  world.debugText("focus:  " .. (self.chargeActive and "true" or "false"), vec2.add(pos, {4, 1.5}), "green")

end