require "/scripts/util.lua"
require "/scripts/vec2.lua"

function init()
    self.projectileType = config.getParameter("projectileType")
    self.projectileParameters = config.getParameter("projectileParameters", {})
    self.projectileParameters.power = config.getParameter("power")
    self.projectileParameters.powerMultiplier = projectile.powerMultiplier()

    message.setHandler("kill", function()
        projectile.die()
    end)

    message.setHandler("collapse", function(_, _)
        projectile.die()
    end)

    message.setHandler("fire", function(_, _, aimPosition, orbIndex) 
        -- do some FX? decay by some amount per shot?
    end)
end

function update(dt)
	world.debugText("TTL:  " .. projectile.timeToLive(), vec2.add(mcontroller.position(), {4, 2}), "green")
end