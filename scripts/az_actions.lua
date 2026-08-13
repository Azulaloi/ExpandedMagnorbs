
azActions = {
  actionProjectileName = "az-exnorb_action"
}

-- TODO: param caching
-- TODO: utils for like, "spawn particles with some velocity", or "spawn particle with this index variant"

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