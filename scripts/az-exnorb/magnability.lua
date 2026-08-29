Magnability = {}

function Magnability:new(cfg)
  local foo = cfg or {}
  setmetatable(foo, {__index = self})
  return foo
end

function Magnability:init() end
function Magnability:consumeEvent(event) return false end
function Magnability:update(dt) end
function Magnability:animUpdate(dt) end
function Magnability:uninit() end