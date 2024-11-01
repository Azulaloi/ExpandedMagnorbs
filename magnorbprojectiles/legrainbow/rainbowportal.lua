require "/scripts/util.lua"
require "/scripts/vec2.lua"

function init()
    self.projectileType = config.getParameter("projectileType")
    self.projectileParameters = config.getParameter("projectileParameters", {})
    self.projectileParameters.power = config.getParameter("power")
    self.projectileParameters.powerMultiplier = projectile.powerMultiplier()

    self.spawnTime = config.getParameter("spawnRate")
    self.spawnTimer = self.spawnTime

    self.pendingProjectiles = {entity.id()}

    self.projectileIds = {false, false, false, false, false}

    message.setHandler("updateProjectile", function(_, _, aimPosition)
        self.aimPosition = aimPosition

        for i = 1, 5 do

        end

        self.pendingProjectiles = {entity.id()}

        local projectileIds = copy(self.projectileIds)
        return projectileIds
    end)

    message.setHandler("kill", function()
        projectile.die()
    end)

    message.setHandler("disable", function(_,_, entityPosition)
        for i = 1, 5 do
            world.sendEntityMessage(self.projectileIds[i], "collapse", entityPosition)
        end
        projectile.die()
    end)
end

function update(dt)
    self.spawnTimer = math.max(0, self.spawnTimer - dt)
    if self.spawnTimer == 0 then
        local nextOrbIndex = nextOrb()
        if nextOrbIndex then
            createProjectile(nextOrbIndex)
        end

        self.spawnTimer = self.spawnTime
    end

    for i = 1, 5 do
        local id = self.projectileIds[i]
        if id then
            if not world.entityExists(id) then
                self.projectileIds[i] = false

            end
        end
    end
end

function createProjectile(index)
    local aimVec = vec2.withAngle(math.random() * 2 * math.pi)

    local projectileId = world.spawnProjectile(
        self.projectileType .. index,
        mcontroller.position(),
        projectile.sourceEntity(),
        aimVec,
        false,
        self.projectileParameters
    )

    if projectileId then
        --world.sendEntityMessage(p)
        self.projectileIds[index] = projectileId
    end
end


function nextOrb()
    for i = 1, 5 do
        if not self.projectileIds[i] then
            return i
        end
    end
end