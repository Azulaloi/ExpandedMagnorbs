

-- I have an additional idea: azActions parameter for projectiles that works like an extended actions block
-- can do things like the retro-extrapolated bounce/hit action, the reap-bridge action, particle actions with momentum etc
-- and also distal actions (lengthwise periodic particles etc)
-- and whatever else I can think of (like using indexed variants IE rainbow colors for particles or something, so it can be done through parameters rather than hardcoded)
-- ideally this new block would then resolve the param/script action split issue


azActions = {
  actionProjectileName = "az-exnorb_action"
}

-- TODO: param caching?

function azActions.makeParticleAction(spec, count, overrides)
  if overrides and type(spec) == "table" then
    spec = sb.jsonMerge(spec, overrides)
  end

  local action = {action = "particle", specification = spec}
  if count and count > 1 then
    return {action = "loop", count = count, body = {action}}
  end
  return action
end

-- todo: make this variadic?
function azActions.group(list)
  return {action = "actions", list = list}
end

function azActions.loop(count, body)
  if body.action then body = {body} end
  return {action = "loop", count = count, body = body}
end

function azActions.loopGroup(list, count) 
  return azActions.loop(count, azActions.group(list)) 
end

-- Generic action processor. [position] and [source] are optional. 
-- If [position] is nil and the context is `projectile`, processes locally.
-- Otherwise, processes via spawned actor projectile.
-- Depending on context, [position] and [source] will be inferred if possible.
function azActions.process(actions, position, source)
  if actions.action then actions = {actions} end

  -- NYI
end




-- Processes actions at a given position. Requires access to `world`.
-- [source] is optional, but will pass as nil unless context is `activeItem`.
function azActions.processAt(actions, position, source)
  if actions.action then actions = {actions} end
  
  source = source or (activeItem and activeItem.ownerEntityId())
  -- maybe the action projectile should just do process action rather than do it on reap?
  return world.spawnProjectile( azActions.actionProjectileName, 
    position, source, {0, 0}, false, {actionOnReap = actions})
end




local definitionCache = {}
function azActions.getDef(path) -- I honestly have no idea if this is more efficient or if it's actually worse
  if not definitionCache[path] then
    definitionCache[path] = root.assetJson(path).definition
  end
  return definitionCache[path]
end


-- I'm so annoyed with the ergo for this whole module. I gotta redo it once I've actually got the experience of using it all over the place
-- It'll probably all get redone as I do the anim/fx pass for all the other sets

function azActions.modify(spec, params)
  if type(spec) ~= "table" then
    if params then 
      sb.logWarn("az-exnorbs:azActions.tweak: can't overlay a kind string, provide spec table instead (" ..  tostring(spec) .. ")")
    end
    return spec
  end

  if not params then return spec end
  return sb.jsonMerge(spec, params)
end

-- never thought I'd ever miss duck typing so much
-- todo: cursed lua duck typing?

function azActions.withVelocity(spec, vel, variance)
  return azActions.modify(spec, {initialVelocity = vel, variance = variance and {initialVelocity = variance} or nil})
end

function azActions.withMomentum(spec, vel, mult, variance)
  return azActions.withVelocity(spec, vec2.mul(vel, mult or 1), variance)
end

function azActions.alongAngle(spec, ang, speed, variance)
  if vec2.mag(ang) < 0.05 then return spec end -- TODO: define epsilon elsewhere
  return azActions.withVelocity(spec, vec2.mul(vec2.norm(ang), speed), variance)
end

-- this is so ass
function azActions.mapParticles(actions, fn)
  if actions.action then actions = {actions} end
  local ret = {}
  
  for i, a in ipairs(actions) do
    local b = copy(a)
    if b.action == "particle" then
      b.specification = fn(b.specification) or b.specification
    elseif b.action == "loop" then
      b.body = azActions.mapParticles(b.body, fn)
    elseif b.action == "actions" then
      b.list = azActions.mapParticles(b.list, fn)
    elseif b.action == "option" then
      b.options = azActions.mapParticles(b.options, fn)
    end
    ret[i] = b
  end
  
  return ret
end
