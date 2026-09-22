-- Simple time-driven cue queue

-- TODO: graft cues and stances and everything else into an unholy amalgam that can do anything
-- very good idea. very wise!
-- (at the very least make it less weird to use in combination with stance sequences)
-- but really a whole keyframe animation system should be possible, right? I think?
-- cues are more versatile and general (only depending on time) but a robust animation system
-- would want arbitrary cue-like features built into the anim chart

azCues = {}

local Sequence = {}
Sequence.__index = Sequence
azCues.Sequence = Sequence

function Sequence.new(cues)
  local s = setmetatable({
    cues = cues, time = 0, index = 1
  }, Sequence)
  
  table.sort(s.cues, function(a, b) return a.t < b.t end)
  return s
end

function Sequence:step(dt)
  self.time = self.time + dt

  -- As long as there are more cues, and the cue keyframe 
  while (self.index <= #self.cues) and (self.cues[self.index].t <= self.time) do
    self.cues[self.index].fn(self) -- Execute cue
    self.index = self.index + 1 -- Iterate
  end
  
  return self:done()
end

function Sequence:done()
  return self.index > #self.cues
end

function Sequence:cancel() -- maybe "reset" makes more sense
  self.index = #self.cues + 1
end

