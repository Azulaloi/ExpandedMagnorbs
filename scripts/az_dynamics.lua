require "/scripts/vec2.lua"
require "/scripts/util.lua"




-- Class objects using metatables cannot be transferred via routes that convert them to JSON.
-- This is because Lua metatables do not survive JSONification, and so all functions will be stripped.
-- Examples of methods that strip metatables: 
-- `storage`, entity messages, scripted animation parameters,
-- `copy()`, and `sb.jsonMerge()`. 


-- These objects are pure, operating only on themselves, and only when called externally.


-- TODO: add proper inertia + friction model? might be good for making different sets handle differently


-- TODO: I bet I could make an even more generalized constraint system
-- if it could swap contexts (projectile, activeItem, tech, etc), I could do really dynamic effects, even the whirl reave woul be simple?
-- need to see what I can generalize from novablitz


azDynamics = {}


---------------------------------------------------


local Spinner = {}
Spinner.__index = Spinner
azDynamics.Spinner = Spinner

function Spinner.new(rate, relax)
  return setmetatable({vel = rate, home = rate, relax = relax}, Spinner)
end

-- Ticks the spinner by [dt], returning the new angle.
function Spinner:step(dt) -- TODO: either change this to step, or the spring steps to update
  self.vel = self.vel + (self.home - self.vel) * math.min(1, self.relax * dt)
  return self.vel * dt
end

function Spinner:kick(kick, mayFlip)
  self.vel = self.vel + kick

  -- TODO: resistance tuning
  -- TODO: flip resistance tuning/toggling
  -- TODO: flip hysteresis

  if mayFlip 
    and (self.vel < 0) ~= (self.home < 0) 
    and math.abs(self.vel) > math.abs(self.home) 
    then self.home = -self.home
  end
end

function Spinner:setHome(home)
  self.home = home
end

function Spinner:reset()
  self.vel = self.home
end

----------------------------------------

local Spring1D = {}
Spring1D.__index = Spring1D
azDynamics.Spring1D = Spring1D

function Spring1D.new(k, damp, clamp)
  return setmetatable({pos = 0, vel = 0, k = k, damp = damp, clamp = clamp}, Spring1D)
end

function Spring1D:step(dt)
  self.vel = self.vel + (-self.k * self.pos - self.damp * self.vel) * dt
  self.pos = self.pos + self.vel * dt
  if self.clamp then self.pos = util.clamp(self.pos, self.clamp[1], self.clamp[2]) end
  return self.pos
end

function Spring1D:kick(dv)
  self.vel = self.vel + dv
end

function Spring1D:reset(pos, vel)
  self.pos = pos or 0
  self.vel = vel or 0
end


local Spring2D = {}
Spring2D.__index = Spring2D
azDynamics.Spring2D = Spring2D

function Spring2D.new(k, damp)
  return setmetatable({pos = {0, 0}, vel = {0, 0}, k = k, damp = damp}, Spring2D)
end

function Spring2D:step(dt)
  for axis = 1, 2 do
    self.vel[axis] = self.vel[axis] + (-self.k * self.pos[axis] - self.damp * self.vel[axis]) * dt
    self.pos[axis] = self.pos[axis] + self.vel[axis] * dt
  end

  return self.pos
end

function Spring2D:kick(dx, dy)
  self.vel[1] = self.vel[1] + dx
  self.vel[2] = self.vel[2] + dy
end

-- Force override velocity state.
function Spring2D:setVelocity(vx, vy)
  self.vel[1] = vx
  self.vel[2] = vy
end

function Spring2D:reset(pos)
  self.pos = pos and {pos[1], pos[2]} or {0, 0}
  self.vel = {0, 0}
end

-----------------------------------------

local MomentumFrame = {}
MomentumFrame.__index = MomentumFrame
azDynamics.MomentumFrame = MomentumFrame


-- <TuningParameters> = {strength, threshold, warmingInterval}


function MomentumFrame.new(tuningParameters)
  local newFrame = setmetatable({tune = tuningParameters}, MomentumFrame)
  newFrame:resync({0, 0})
  return newFrame
end

function MomentumFrame:resync(pos)
  self.lastBase, self.lastVel = pos, {0, 0}
  self.warmup = self.tune.warmingInterval
end

function MomentumFrame:sample(pos, dt)
  local vel = vec2.div(vec2.sub(pos, self.lastBase or pos), dt)
  local deltaVel = vec2.sub(vel, self.lastVel or vel)
  self.lastBase, self.lastVel = pos, vel

  if self.warmup > 0 then
    self.warmup = self.warmup - dt
    return nil
  end

  if vec2.mag(deltaVel) / dt <= self.tune.threshold then
    return nil
  end

  return vec2.mul(deltaVel, -self.tune.strength)
end

------------------------------------


function azDynamics.frame(delta, minimumMagnitude)
  if vec2.mag(delta) < (minimumMagnitude or 0.5) then 
    return nil 
  end
  local radDir = vec2.norm(delta)
  return radDir, vec2.rotate(radDir, math.pi / 2)
end



function azDynamics.squashedOrbit(radius, squash, phase)
  local p = vec2.rotate({radius, 0}, phase)
  local depth = p[2] / radius
  p[2] = p[2] * squash
  return p, depth
end



-- function newSpinner(rate, relax)
--   return {vel = rate, home = rate, relax = relax}
-- end


-- function spinnerUpdate(s, dt)
--   -- TODO: more tuning control (friction, damping, clamps)

--   s.vel = s.vel + (s.home - s.vel) * math.min(1, s.relax * dt)
--   return s.vel * dt
-- end


-- function spinnerKick(s, kick, mayFlip)
--   s.vel = s.vel + kick

--   -- TODO: hysteresis for flip (must exceed X countervel before flipping)
--   if mayFlip and (s.vel < 0) ~= (s.home < 0) and math.abs(s.vel) > math.abs(s.home) then
--     s.home = -s.home
--   end
-- end


