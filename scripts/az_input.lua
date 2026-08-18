-- Input event composer for active items

azInput = {}

local Grammar = {}
Grammar.__index = Grammar
azInput.Grammar = Grammar

function Grammar.new(tune)
  return setmetatable({
    tune = tune,
    button = nil, -- Currently held button
    time = 0, -- Time current button has been held
    shift = false, -- Was shift true at initial press
    holdStarted = false,
    lastTapButton = nil,
    lastTapAge = math.huge -- big number... huge...
  }, Grammar)
end

function Grammar:step(fireMode, shiftHeld, dt) -- this should really be `update()` but step is consistent
  local events = {}
  local button = (fireMode ~= "none") and fireMode or nil
  self.lastTapAge = self.lastTapAge + dt -- TODO: look for way to grab epoch instead?

  if button ~= self.button then
    if self.button then self:_release(events) end
    if button then
      self.button = button
      self.time = 0
      self.shift = shiftHeld
      self.holdStarted = false
      events[#events + 1] = {
        type = "press", button = button, shift = self.shift
      }
    end
  elseif self.button then
    self.time = self.time + dt
    if not self.holdStarted and (self.time >= self.tune.holdThreshold) then
      self.holdStarted = true
      -- sb.logInfo("hold start")
      events[#events + 1] = {
        type = "holdStart", button = self.button, shift = self.shift
      }
    end
  end

  return events
end

function Grammar:_release(events) -- make this local?
  local button = self.button
  local shift = self.shift

  if self.holdStarted then
    events[#events + 1] = {
      type = "holdRelease", 
      button = button, 
      shift = shift,
      duration = self.time
    }

  else
    events[#events + 1] = {
      type = "tap", button = button, shift = shift
    }

    if self.lastTapButton == button and self.lastTapAge <= self.tune.doubleTapWindow then
      events[#events + 1] = {
        type = "doubleTap", button = button, shift = shift
      }

      self.lastTapButton = nil
    else
      self.lastTapButton = button
      self.lastTapAge = 0
    end
  end

  self.button = nil
  self.holdStarted = false
end

function Grammar:held(button)
  return self.button == button
end

function Grammar:heldTime(button)
  if self.button == button then
    return self.time
  end

  return nil
end