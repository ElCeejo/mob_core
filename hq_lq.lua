------------------------------
-- Mob Core HQ/LQ Functions --
------------------------------
---------- Ver 0.1 -----------

------------
-- Math --
------------

local random = math.random
local pi = math.pi
local abs = math.abs
local ceil = math.ceil
local min = math.min

local function diff(a, b) -- Get difference between 2 angles
    return math.atan2(math.sin(b - a), math.cos(b - a))
end

local function clamp(num, min_, max_)
    if num < min_ then
        num = min_
    elseif num > max_ then
        num = max_
    end

    return num
end

local function lerp(a, b, w)
    if abs(a - b) > pi then
        if a < b then
            return (a + (b - a) * 1) + (pi * 2)
        elseif a > b then
            return (a + (b - a) * 1) - (pi * 2)
        end
    end
    return a + (b - a) * w
end

local vec_dist = vector.distance

local function vec_cross(a, b)
    return {
        x = a.y * b.z - a.z * b.y,
        y = a.z * b.x - a.x * b.z,
        z = a.x * b.y - a.y * b.x
    }
end

--------------
-- Settings --
--------------

local abr = minetest.get_mapgen_setting('active_block_range')
local legacy_jump = minetest.settings:get_bool("legacy_jump")

---------------------
-- Quick Callbacks --
---------------------

-- Current Collisionbox --

function mob_core.get_hitbox(object)
    if type(object) == "table" then object = object.object end
    return object:get_properties().collisionbox
end

local hitbox = mob_core.get_hitbox -- Recommended use for cleaner code

local function dist_2d(pos1, pos2)
    local a = vector.new(pos1.x, 0, pos1.z)
    local b = vector.new(pos2.x, 0, pos2.z)
    return vec_dist(a, b)
end

--------------------
-- Object Control --
--------------------

-- Set Vertical Velocity --

local function set_lift(self, val)
    local vel = self.object:get_velocity()
    vel.y = val
    self.object:set_velocity(vel)
end

-------------
-- Sensors --
-------------

local function index_collisions(self, pos, no_air)
    local width = self.object:get_properties().collisionbox[4] + 1
    local pos1 = vector.subtract(pos, width)
    local pos2 = vector.add(pos, width)
    local collisions = {}
    for x = pos1.x, pos2.x do
        for y = pos1.y, pos2.y do
            for z = pos1.z, pos2.z do
                local npos = vector.new(x, y, z)
                local name = minetest.get_node(npos).name
                if minetest.registered_nodes[name].walkable or
                    (no_air and name == "air") then
                    table.insert(collisions, npos)
                end
            end
        end
    end
    return collisions
end

-- Can Fit --

function mob_core.can_fit(self, pos, no_air)
    local width = hitbox(self)[4] + 1
    local height = self.height * 0.5
    local pos1 = vector.new(pos.x - width, pos.y - height, pos.z - width)
    local pos2 = vector.new(pos.x + width, pos.y + height, pos.z + width)
    for x = pos1.x, pos2.x do
        for y = pos1.y, pos2.y do
            for z = pos1.z, pos2.z do
                local npos = vector.new(x, y, z)
                local name = minetest.get_node(npos).name
                if minetest.registered_nodes[name].walkable or
                    (no_air and name == "air") then return false end
            end
        end
    end
    return true
end

-- Obstacle Avoidance Calculation --

local function find_closest_pos(tbl, pos)
    local iter = 2
    if #tbl < 2 then return end
    local closest = tbl[1]
    while iter < #tbl do
        if vec_dist(pos, closest) < vec_dist(pos, tbl[iter + 1]) then
            iter = iter + 1
        else
            closest = tbl[iter]
            iter = iter + 1
        end
    end
    if iter >= #tbl and closest then return closest end
end

function mob_core.collision_avoidance(self)
    local box = hitbox(self)
    local width = abs(box[3]) + abs(box[6])
    local pos = mobkit.get_stand_pos(self)
    pos.y = pos.y + (self.height * 0.5) -- center of hitbox
    local yaw = self.object:get_yaw()
    local outset = self.obstacle_avoidance_range or width
    local ahead = vector.add(pos, vector.multiply(minetest.yaw_to_dir(yaw),
                                                  width + outset))
    local can_fit = mob_core.can_fit(self, ahead)
    local collisions = index_collisions(self, ahead)
    local obstacle = find_closest_pos(collisions, pos)
    if not can_fit and obstacle then
        local avoidance_path =
            vector.normalize((vector.subtract(pos, obstacle)))
        local magnitude = (width * 2) - vec_dist(pos, obstacle)
        return avoidance_path, magnitude, false
    end
end

-- Find Water Surface --

local function sensor_surface(self, range)
    local pos = self.object:get_pos()
    local node = minetest.get_node(pos)
    local dist = 0
    while node.name == self.isinliquid and dist <= range do
        pos.y = pos.y + 1
        node = minetest.get_node(pos)
        dist = dist + 1
    end
    if node.name ~= self.isinliquid then return dist end
    return range
end

-- Find First Solid Node Above Object --

local function sensor_ceil(self, range)
    local pos = self.object:get_pos()
    local node = minetest.get_node(pos)
    local dist = 0
    while not minetest.registered_nodes[node.name].walkable and dist <= range do
        pos.y = pos.y + 1
        node = minetest.get_node(pos)
        dist = dist + 1
    end
    if minetest.registered_nodes[node.name].walkable then return dist end
    return range
end

-- Find First Solid/Liquid Node Below Object --

local sensor_floor = mob_core.sensor_floor

---------------------
-- Basic Functions --
---------------------

-- Check for Fall --

local function line_of_sight(pos1, pos2) -- from mobs_redo, by Astrobe
    local ray = minetest.raycast(pos1, pos2, true, true)
    local thing = ray:next()
    while thing do
        if thing.type == "node" then
            local name = minetest.get_node(thing.under).name
            if minetest.registered_items[name] and
                (minetest.registered_items[name].walkable or
                    minetest.registered_items[name].groups.liquid) then
                return false
            end
        end

        thing = ray:next()
    end
    return true
end

function mob_core.fall_check(self, pos, height) -- Partially taken from mobs_redo
    if not mobkit.is_alive(self) then return false end
    if height == 0 then return false end
    local yaw = self.object:get_yaw()
    local dir_x = -math.sin(yaw) * (self.collisionbox[4] + 0.5)
    local dir_z = math.cos(yaw) * (self.collisionbox[4] + 0.5)
    pos = pos or self.object:get_pos()
    local ypos = pos.y + self.collisionbox[2]
    if line_of_sight({x = pos.x + dir_x, y = ypos, z = pos.z + dir_z},
                     {x = pos.x + dir_x, y = ypos - height, z = pos.z + dir_z}) then
        return true
    end
    return false
end

------------------------
-- API Object Control --
------------------------

function mob_core.knockback(self, target)
    if not self.knockback then return end
    local pos = mobkit.get_stand_pos(self)
    local pos2 = target:get_pos()
    if not pos2 then return end
    local kb = self.knockback
    if kb - hitbox(target)[4] > 1 then
        kb = kb - hitbox(target)[4]
    else
        kb = 1
    end
    local dir = vector.direction({x = pos.x, y = 0, z = pos.z},
                                 {x = pos2.x, y = 0, z = pos2.z})
    local vel = vector.multiply(dir, kb)
    vel.y = kb * 0.2
    target:add_velocity(vel)
end

-- Punch Timer --

function mob_core.punch_timer(self, new_val)
    if new_val and new_val > 0 then self.punch_timer = new_val end
    if self.punch_timer > 0 then
        self.punch_timer = self.punch_timer - self.dtime
    else
        self.punch_timer = 0
    end
    self.punch_timer = mobkit.remember(self, "punch_timer", self.punch_timer)
end

------------------
-- LQ Functions --
------------------

function mob_core.lq_dumb_punch(self, target, anim)
    anim = anim or "punch"
    local length = 0.1
    if self.animation[anim] then
        length = (self.animation[anim].range.y - self.animation[anim].range.x) /
                     self.animation[anim].speed
    end
    local func = function(self)
        if not mobkit.exists(target) then return true end
        local pos = self.object:get_pos()
        local yaw = self.object:get_yaw()
        local tpos = target:get_pos()
        local tyaw = minetest.dir_to_yaw(vector.direction(pos, tpos))
        if abs(tyaw - yaw) > 0.1 then mobkit.turn2yaw(self, tyaw, 4) end
        mobkit.animate(self, anim or "punch")
        target:punch(self.object, 1.0, {
            full_punch_interval = 0.1,
            damage_groups = {fleshy = self.damage}
        }, nil)
        mob_core.punch_timer(self, self.punch_cooldown)
        mob_core.knockback(self, target)
        self.custom_punch_target = target
        if self.custom_punch and self.custom_punch_target then
            self.custom_punch(self)
        end
        length = length - self.dtime
        if length <= 0 then return true end
    end
    mobkit.queue_low(self, func)
end

function mob_core.lq_follow_path(self, path, speed_factor, anim)
    anim = anim or "walk"
    local timer = #path
    local func = function(self)
        if #path <= 1 then
            return true
        end
        local speed = speed_factor or 1
        local path_iter = 1
        local width = ceil(hitbox(self)[4])
        if #path >= width then
            path_iter = width
        end
        local pos = mobkit.get_stand_pos(self)
        local tpos = path[path_iter]
        local dir = vector.direction(pos, tpos)
        local total_dist = vec_dist(pos, path[#path])

        if total_dist <= width + 0.5 then
            return true
        end

        if not self.isonground then
            speed = speed * 0.5
        end

        if vec_dist(pos, tpos) <= width + 0.5
        or (path[path_iter + 1]
        and vec_dist(pos, path[path_iter + 1]) <= width + 0.5) then
            table.remove(path, 1)
            timer = timer - 1
        end

        local turn_rate = self.turn_rate or 8

        if vector.distance(pos, tpos) < width + 2 then
            turn_rate = turn_rate + 2
        end

        timer = timer - self.dtime

        if timer <= 0 then return true end

        mobkit.turn2yaw(self, minetest.dir_to_yaw(dir), turn_rate)
        mobkit.go_forward_horizontal(self, self.max_speed * speed)
        mobkit.animate(self, anim)
    end
    mobkit.queue_low(self, func)
end

------------
-- Aerial --
------------

function mob_core.tilt_to_yaw(self, tyaw, rate)
    self._tyaw = tyaw
    tyaw = tyaw or 0 -- temp
    rate = rate or 6
    local rot = self.object:get_rotation()
    local yaw = self.object:get_yaw()
    yaw = yaw + pi
    tyaw = (tyaw + pi) % (pi * 2)

    local step = min(self.dtime * rate, abs(tyaw - yaw) % (pi * 2))

    local dir = abs(tyaw - yaw) > pi and -1 or 1
    dir = tyaw > yaw and dir * 1 or dir * -1

    local nyaw = (yaw + step * dir) % (pi * 2)

    local nroll =
        vec_cross(minetest.yaw_to_dir(yaw), minetest.yaw_to_dir(tyaw)).y

    local roll = lerp(rot.z, nroll, 0.1)

    self.object:set_rotation({x = rot.x, y = nyaw - pi, z = roll})

    if nyaw == tyaw then
        return true, nyaw - pi
    else
        return false, nyaw - pi
    end
end

function mob_core.hq_takeoff_and_fly_continuously(self, prty, lift_force)
    lift_force = lift_force or 1
    local stage = 1
    local center = self.object:get_pos()
    local func = function(self)
        local pos = mobkit.get_stand_pos(self)
        local tyaw = minetest.dir_to_yaw(vector.direction(pos, center)) -- Mob will spiral around takeoff point
        local steer_to, turn_intensity = mob_core.collision_avoidance(self)
        local dist_to_ground = sensor_floor(self, self.view_range, true)
        if dist_to_ground < (self.floor_avoidance_range or 16) then
            local lift = (self.max_speed * 0.5) * lift_force
            if steer_to then
                tyaw = minetest.dir_to_yaw(steer_to)
                turn_intensity = abs(turn_intensity * 3.33)
            else
                turn_intensity = 0
            end
            local rot = self.object:get_rotation()
            self.object:set_rotation({
                x = lerp(rot.x, (lift * (math.pi * 0.01)), 0.2),
                y = rot.y,
                z = rot.z
            })
            mob_core.tilt_to_yaw(self, tyaw, (self.turn_rate or 4) + turn_intensity)
            set_lift(self, rot.x * 10)
            local accel = self.object:get_acceleration()
            accel.y = accel.y + lift
            self.object:set_acceleration(accel)
            mobkit.animate(self, "fly")
            mobkit.go_forward_horizontal(self, self.max_speed)
        else
            mob_core.hq_aerial_roam(self, prty, 1)
            return true
        end
    end
    mobkit.queue_high(self, func, prty)
end

mob_core.hq_takeoff = mob_core.hq_takeoff_and_fly_continuously

function mob_core.hq_takeoff_and_soar(self, prty, lift_force)
    lift_force = lift_force or 1
    local stage = 1
    local center = self.object:get_pos()
    local func = function(self)
        local pos = mobkit.get_stand_pos(self)
        local tyaw = minetest.dir_to_yaw(vector.direction(pos, center)) -- Mob will spiral around takeoff point
        local steer_to, turn_intensity = mob_core.collision_avoidance(self)
        local dist_to_ground = sensor_floor(self, self.view_range, true)
        if dist_to_ground < (self.floor_avoidance_range or 16) then
            local lift = (self.max_speed * 0.5) * lift_force
            if steer_to then
                tyaw = minetest.dir_to_yaw(steer_to)
                turn_intensity = abs(turn_intensity * 3.33)
            else
                turn_intensity = 0
            end
            local rot = self.object:get_rotation()
            self.object:set_rotation({
                x = lerp(rot.x, (lift * (math.pi * 0.01)), 0.2),
                y = rot.y,
                z = rot.z
            })
            mob_core.tilt_to_yaw(self, tyaw, (self.turn_rate or 4) + turn_intensity)
            set_lift(self, rot.x * 10)
            local accel = self.object:get_acceleration()
            accel.y = accel.y + lift
            self.object:set_acceleration(accel)
            mobkit.animate(self, "fly")
            mobkit.go_forward_horizontal(self, self.max_speed)
        else
            mob_core.hq_fly_and_soar(self, prty)
            return true
        end
    end
    mobkit.queue_high(self, func, prty)
end

-- Roam --

function mob_core.hq_fly_continuously(self, prty, speed_factor)
    speed_factor = speed_factor or 1
    local tyaw = 0
    local lift = 0
    local center = self.object:get_pos()
    local init = false
    local func = function(self)
        if not init then
            mobkit.animate(self, 'fly')
            init = true
        end
        local pos = mobkit.get_stand_pos(self)
        local rot = self.object:get_rotation()
        local steer_to, turn_intensity = mob_core.collision_avoidance(self)
        local ceiling = sensor_ceil(self, self.view_range) or self.view_range
        local floor = sensor_floor(self, self.view_range, true) or
                          self.view_range
        local max_lift = (self.max_speed / 2) * speed_factor

        if mobkit.timer(self, 1) then
            if vec_dist(pos, center) > abr * 16 * 0.5 then
                tyaw = minetest.dir_to_yaw(
                           vector.direction(pos, {
                        x = center.x + random() * 10 - 5,
                        y = center.y,
                        z = center.z + random() * 10 - 5
                    }))
            else
                if random(10) >= 9 then
                    tyaw = tyaw + random() * pi - pi * 0.5
                end
            end
        end

        if steer_to then tyaw = minetest.dir_to_yaw(steer_to) end

        if mobkit.timer(self, 6) then
            if floor > self.height + 1 and ceiling > self.height + 1 then
                lift = random(-max_lift, max_lift)
            end
        end

        if ceiling <= math.abs(self.view_range / 4) then lift = -max_lift end

        if floor <= (self.floor_avoidance_range or math.ceil(hitbox(self)[4]) * 2) or self.isinliquid then
            lift = max_lift
        end

        self.object:set_acceleration({x = 0, y = 0, z = 0})

        if not turn_intensity then
            turn_intensity = 0
        else
            turn_intensity = abs(turn_intensity * 3.33)
        end
        -- Set pitch
        self.object:set_rotation({
            x = lerp(rot.x, (lift * (math.pi * 0.01)), 0.2),
            y = rot.y,
            z = rot.z
        })
        -- Set yaw/roll
        mob_core.tilt_to_yaw(self, tyaw, (self.turn_rate or 4) + turn_intensity)
        -- Set velocity
        set_lift(self, rot.x * 10)
        local accel = self.object:get_acceleration()
        accel.y = accel.y + lift
        self.object:set_acceleration(accel)
        if lift > 0 then
            mobkit.animate(self, "fly")
        else
            mobkit.animate(self, "soar")
        end
        mobkit.go_forward_horizontal(self, self.max_speed * speed_factor)
    end
    mobkit.queue_high(self, func, prty)
end

mob_core.hq_aerial_roam = mob_core.hq_fly_continuously

function mob_core.hq_fly_and_soar(self, prty, speed_factor)
    speed_factor = speed_factor or 1
    local tyaw = 0
    local lift = 0
    local center = self.object:get_pos()
    local func = function(self)
        local pos = mobkit.get_stand_pos(self)
        local yaw = self.object:get_yaw()
        local rot = self.object:get_rotation()
        local steer_to, turn_intensity = mob_core.collision_avoidance(self)
        local ceiling = sensor_ceil(self, self.view_range) or self.view_range
        local floor = sensor_floor(self, self.view_range, true) or
                          self.view_range
        local max_lift = (self.max_speed) * speed_factor
        -- Check distance from center every second
        if mobkit.timer(self, 1) then
            if vec_dist(pos, center) > abr * 16 * 0.5 then
                local dir = vector.direction(pos, {
                    x = center.x + random() * 10 - 5,
                    y = center.y,
                    z = center.z + random() * 10 - 5
                })
                tyaw = minetest.dir_to_yaw(dir)
                lift = clamp(dir.y, -max_lift, max_lift)
            else
                if abs(tyaw - yaw) < 0.2 then
                    tyaw = tyaw + random() * pi - pi * 0.5
                    if floor > self.height + 1 and ceiling > self.height + 1 then
                        lift = random(-max_lift, max_lift)
                    end
                end
            end
        end
        -- Steer from obstacles
        if steer_to then tyaw = minetest.dir_to_yaw(steer_to) end
        -- Avoid ground
        if floor <= (self.floor_avoidance_range or math.ceil(hitbox(self)[4]) * 2) then lift = max_lift end
        -- Avoid ceilings
        if ceiling <= math.abs(self.view_range / 4) then lift = -max_lift end
        -- If there is no obstacle, turn at 1 rad/s
        if not turn_intensity or turn_intensity < 1 then
            turn_intensity = 1
        end
        -- Set pitch
        self.object:set_rotation({
            x = lerp(rot.x, (lift * (math.pi * 0.01)), 0.2),
            y = rot.y,
            z = rot.z
        })
        -- Set yaw/roll
        mob_core.tilt_to_yaw(self, tyaw, turn_intensity)
        -- Set velocity
        set_lift(self, rot.x * 10)
        local accel = self.object:get_acceleration()
        accel.y = accel.y + lift
        self.object:set_acceleration(accel)
        if lift > 0 then
            mobkit.animate(self, "fly")
        else
            mobkit.animate(self, "soar")
        end
        mobkit.go_forward_horizontal(self, self.max_speed * speed_factor)
    end
    mobkit.queue_high(self, func, prty)
end

-- Land --

function mob_core.hq_land_and_roam(self, prty, pos2)
    local init = false
    local func = function(self)
        if not init then
            mobkit.animate(self, 'fly')
            init = true
        end
        local rot = self.object:get_rotation()
        local floor = sensor_floor(self, self.view_range, true)

        self.object:set_acceleration{x = 0, y = 0, z = 0}

        local pitch = rot.x + ((-self.max_speed / 2) - rot.x) * 0.05

        self.object:set_rotation({x = pitch * 0.31, y = rot.y, z = rot.z})
        if pos2 then
            local pos = self.object:get_pos()
            if vec_dist(pos, pos2) > self.height + 1 then
                mob_core.tilt_to_yaw(self, minetest.dir_to_yaw(
                                         vector.direction(pos, pos2)))
                set_lift(self, -self.max_speed / 2)
                mobkit.go_forward_horizontal(self, self.max_speed)
            end
            if floor <= self.height + 1 then
                mobkit.animate(self, "land")
                mobkit.hq_roam(self, prty + 1)
                return true
            end
        else
            if floor > self.height + 1 then
                mobkit.turn2yaw(self,
                                minetest.dir_to_yaw(self.object:get_velocity()))
                set_lift(self, -self.max_speed / 2)
            end
            if floor <= self.height + 1 then
                self.object:set_rotation(
                    {x = 0, y = self.object:get_yaw(), z = 0})
                mobkit.animate(self, "land")
                mobkit.hq_roam(self, prty + 1)
                return true
            end
        end
    end
    mobkit.queue_high(self, func, prty)
end

mob_core.hq_land = mob_core.hq_land_and_roam

-- Follow Holding --

function mob_core.hq_aerial_follow_holding(self, prty, player) -- Follow Player
    local tyaw = 0
    local lift = 0
    local init = false
    if not player then return end
    if not mob_core.follow_holding(self, player) then return end
    local func = function(self)
        if mobkit.is_queue_empty_low(self) then
            if mob_core.follow_holding(self, player) then
                if not init then
                    mobkit.animate(self, "fast" or "fly")
                end
                self.status = mobkit.remember(self, "status", "following")
                local pos = mobkit.get_stand_pos(self)
                local tpos = player:get_pos()

                local steer_to, turn_intensity =
                    mob_core.collision_avoidance(self)
                local ceiling = sensor_ceil(self, self.view_range)
                local floor = sensor_floor(self, self.view_range, true)

                local dir = vector.direction(pos, tpos)

                lift = dir.y

                if floor and floor <= (self.floor_avoidance_range or math.ceil(hitbox(self)[4]) * 2) then
                    if lift < 1 then lift = lift + 0.2 end
                end
                if ceiling and ceiling <= math.abs(self.view_range / 4) then
                    if lift > -1 then lift = lift - 0.2 end
                end

                tyaw = minetest.dir_to_yaw(dir)

                if steer_to then
                    tyaw = minetest.dir_to_yaw(steer_to)
                end

                if lift < 0 then
                    self.object:set_acceleration({x = 0, y = 0.1, z = 0})
                else
                    self.object:set_acceleration({x = 0, y = 0, z = 0})
                end

                if not turn_intensity or turn_intensity < 1 then
                    turn_intensity = 1
                end

                mobkit.turn2yaw(self, tyaw,
                                (self.turn_rate or 2) * turn_intensity)
                set_lift(self, lift)
                mobkit.go_forward_horizontal(self, self.max_speed)
            end
        end
        if (self.status == "following" and
            not mob_core.follow_holding(self, player)) then
            self.status = mobkit.remember(self, "status", "")
            return true
        end
    end
    mobkit.queue_high(self, func, prty)
end

-------------
-- Aquatic --
-------------

local function aqua_radar_dumb(pos, yaw, range, reverse) -- Ported from mobkit
    range = range or 4
    local function okpos(p)
        local node = mobkit.nodeatpos(p)
        if node then
            if node.drawtype == 'liquid' then
                local nodeu = mobkit.nodeatpos(mobkit.pos_shift(p, {y = 1}))
                local noded = mobkit.nodeatpos(mobkit.pos_shift(p, {y = -1}))
                if (nodeu and nodeu.drawtype == 'liquid') or
                    (noded and noded.drawtype == 'liquid') then
                    return true
                else
                    return false
                end
            else
                local h = mobkit.get_terrain_height(p)
                if h then
                    local node2 = mobkit.nodeatpos(
                                      {x = p.x, y = h + 1.99, z = p.z})
                    if node2 and node2.drawtype == 'liquid' then
                        return true, h
                    end
                else
                    return false
                end
            end
        else
            return false
        end
    end
    local fpos = mobkit.pos_translate2d(pos, yaw, range)
    local ok, h = okpos(fpos)
    if not ok then
        local ffrom, fto, fstep
        if reverse then
            ffrom, fto, fstep = 3, 1, -1
        else
            ffrom, fto, fstep = 1, 3, 1
        end
        for i = ffrom, fto, fstep do
            ok, h = okpos(mobkit.pos_translate2d(pos, yaw + i, range))
            if ok then return yaw + i, h end
            ok, h = okpos(mobkit.pos_translate2d(pos, yaw - i, range))
            if ok then return yaw - i, h end
        end
        return yaw + pi, h
    else
        return yaw, h
    end
end

function mob_core.hq_aqua_roam(self, prty, speed_factor)
    local tyaw = 0
    local lift = 0
    local reset_timer = 6
    local center = self.object:get_pos()
    local init = false
    local func = function(self)
        if not self.isinliquid then return true end
        if not init or self._anim ~= "swim" then
            mobkit.animate(self, "swim")
            init = true
        end
        local pos = self.object:get_pos()
        local steer_to, turn_intensity = mob_core.collision_avoidance(self)
        local surface = sensor_surface(self, self.view_range)
        local floor = sensor_floor(self, self.view_range)

        if floor <= (self.floor_avoidance_range or math.ceil(hitbox(self)[4]) * 2) then
            if lift < 1 then lift = lift + 0.2 end
        end

        if surface <= self.surface_avoidance_range then
            if lift > -1 then lift = lift - 0.2 end
        end

        if mobkit.timer(self, 1) then
            if vec_dist(pos, center) > abr * 16 * 0.5 then
                tyaw = minetest.dir_to_yaw(
                           vector.direction(pos, {
                        x = center.x + random() * 10 - 5,
                        y = center.y,
                        z = center.z + random() * 10 - 5
                    }))
            else
                if random(10) >= 9 then
                    tyaw = tyaw + random() * pi - pi * 0.5
                end
            end
            if floor > self.height then
                if math.abs(lift) > 0.5 then lift = 0.1 end
            end
        end

        if reset_timer <= 0 then center = self.object:get_pos() end

        if steer_to then
            tyaw = minetest.dir_to_yaw(steer_to)
            reset_timer = reset_timer - self.dtime
        else
            reset_timer = 6
        end

        if mobkit.timer(self, random(3, 6)) then -- Ocassionally go down
            if floor > (self.floor_avoidance_range or math.ceil(hitbox(self)[4]) * 2) and surface >
                self.surface_avoidance_range then
                if math.random(1, 2) == 1 then
                    lift = -0.5
                else
                    lift = 0.5
                end
            end
        end

        if lift < 0 then
            self.object:set_acceleration({x = 0, y = 0.1, z = 0})
        else
            self.object:set_acceleration({x = 0, y = 0, z = 0})
        end

        if not turn_intensity or turn_intensity < 1 then
            turn_intensity = 1
        end

        mobkit.turn2yaw(self, tyaw, (self.turn_rate or 2) * turn_intensity)
        set_lift(self, lift)
        mobkit.go_forward_horizontal(self, self.max_speed * speed_factor)
    end
    mobkit.queue_high(self, func, prty)
end

function mob_core.hq_swim_and_idle(self, prty, speed_factor)
    local next_pos = self.object:get_pos()
    local func = function(self)
        if not self.isinliquid then return true end
        local pos = self.object:get_pos()

        if mobkit.timer(self, random(3, 4)) then
            next_pos = {
                x = pos.x + random() * 10 - 5,
                y = pos.y + random(-5, 5),
                z = pos.z + random() * 10 - 5
            }
        end

        if minetest.get_node(next_pos).name ~= self.isinliquid then
            next_pos = {
                x = pos.x + random() * 10 - 5,
                y = pos.y + random(-5, 5),
                z = pos.z + random() * 10 - 5
            }
        end

        if mobkit.is_queue_empty_low(self) then
            if vector.distance(pos, next_pos) > hitbox(self)[4] then
                local dir = vector.direction(pos, next_pos)
                local tyaw = minetest.dir_to_yaw(dir)
                local steer_to, turn_intensity =
                    mob_core.collision_avoidance(self)
                if steer_to then
                    tyaw = minetest.dir_to_yaw(steer_to)
                else
                    turn_intensity = 1
                end
                mobkit.turn2yaw(self, tyaw,
                                (self.turn_rate or 2) * turn_intensity)
                set_lift(self, dir.y * self.max_speed)
                mobkit.go_forward_horizontal(self, self.max_speed * speed_factor)
                mobkit.animate(self, "swim")
            else
                mobkit.lq_idle(self, random(1, 2), "swim_idle")
            end
        end
    end
    mobkit.queue_high(self, func, prty)
end

-- Aquatic Attack --

function mob_core.hq_aqua_attack(self, prty, target)
    local tyaw = 0
    local lift = 0
    local init = false
    local func = function(self)
        if not self.isinliquid or not mobkit.is_alive(target) or
            not mob_core.can_fit(self, target:get_pos(), true) then
            return true
        end
        if not init then
            mobkit.animate(self, "swim")
            init = true
        end
        local pos = self.object:get_pos()
        local tpos = target:get_pos()
        local yaw = self.object:get_yaw()
        local steer_to, turn_intensity = mob_core.collision_avoidance(self)
        local surface = sensor_surface(self, self.view_range)
        local floor = sensor_floor(self, self.view_range)

        local dir = vector.direction(pos, tpos)

        lift = dir.y

        if floor <= (self.floor_avoidance_range or math.ceil(hitbox(self)[4]) * 2) then
            if lift < 1 then lift = lift + 0.2 end
        end

        if surface <= self.surface_avoidance_range then
            if lift > -1 then lift = lift - 0.2 end
        end

        tyaw = minetest.dir_to_yaw(dir)

        if steer_to then tyaw = minetest.dir_to_yaw(steer_to) end

        if lift < 0 then
            self.object:set_acceleration({x = 0, y = 0.1, z = 0})
        else
            self.object:set_acceleration({x = 0, y = 0, z = 0})
        end

        local target_side = abs(target:get_properties().collisionbox[4])

        if vec_dist(pos, tpos) < self.reach + target_side then
            target:punch(self.object, 1.0, {
                full_punch_interval = 0.1,
                damage_groups = {fleshy = self.damage}
            }, nil)
            mobkit.animate(self, "punch_swim" or "punch")
            mob_core.knockback(self, target)
            self.custom_punch_target = target
            if self.custom_punch and self.custom_punch_target then
                self.custom_punch(self)
            end
            mobkit.hq_aqua_turn(self, prty, yaw - pi, self.max_speed)
            return true
        end

        if not turn_intensity or turn_intensity < 1 then
            turn_intensity = 1
        end

        mobkit.turn2yaw(self, tyaw, (self.turn_rate or 2) * turn_intensity)
        set_lift(self, lift)
        mobkit.go_forward_horizontal(self, self.max_speed)
    end
    mobkit.queue_high(self, func, prty)
end

-- Swim from/Runaway --

function mob_core.hq_swimfrom(self, prty, target, speed)
    local init = false
    local timer = 6
    local func = function(self)
        if not mobkit.is_alive(target) then return true end
        if not self.isinliquid then return true end
        if not init then
            timer = timer - self.dtime
            if timer <= 0 or vec_dist(self.object:get_pos(), target:get_pos()) <
                8 then
                mobkit.make_sound(self, 'scared')
                init = true
            end
            return
        end
        local pos = mobkit.get_stand_pos(self)
        local chase_pos = target:get_pos()
        local dir = vector.direction(pos, chase_pos)
        local yaw = minetest.dir_to_yaw(dir) - (pi / 2)
        local dist = vec_dist(pos, chase_pos)
        if (dist / 1.5) < self.view_range then
            local swimto, height = aqua_radar_dumb(pos, yaw, 3)
            if height and height > pos.y then
                local vel = self.object:get_velocity()
                vel.y = vel.y + 0.1
                self.object:set_velocity(vel)
            end
            mobkit.hq_aqua_turn(self, prty + 1, swimto, speed)
        else
            return true
        end
        timer = timer - 1
    end
    mobkit.queue_high(self, func, prty)
end

-- Aquatic Follow --

function mob_core.hq_aqua_follow_holding(self, prty, player) -- Follow Player
    local tyaw = 0
    local lift = 0
    local init = false
    if not player then return end
    if not mob_core.follow_holding(self, player) then return end
    local func = function(self)
        if mobkit.is_queue_empty_low(self) then
            if mob_core.follow_holding(self, player) then
                if not init then
                    mobkit.animate(self, "fast" or "swim")
                end
                local pos = mobkit.get_stand_pos(self)
                local tpos = player:get_pos()

                self.status = mobkit.remember(self, "status", "following")
                local steer_to, turn_intensity =
                    mob_core.collision_avoidance(self)
                local surface = sensor_surface(self, self.view_range)
                local floor = sensor_floor(self, self.view_range)

                local dir = vector.direction(pos, tpos)

                lift = dir.y

                if floor <= (self.floor_avoidance_range or math.ceil(hitbox(self)[4]) * 2) then
                    if lift < 1 then lift = lift + 0.2 end
                end

                if surface <= self.surface_avoidance_range then
                    if lift > -1 then lift = lift - 0.2 end
                end

                tyaw = minetest.dir_to_yaw(dir)

                if steer_to then
                    tyaw = minetest.dir_to_yaw(steer_to)
                end

                if lift < 0 then
                    self.object:set_acceleration({x = 0, y = 0.1, z = 0})
                else
                    self.object:set_acceleration({x = 0, y = 0, z = 0})
                end

                if not turn_intensity or turn_intensity < 1 then
                    turn_intensity = 1
                end

                mobkit.turn2yaw(self, tyaw,
                                (self.turn_rate or 2) * turn_intensity)
                set_lift(self, lift)
                mobkit.go_forward_horizontal(self, self.max_speed)
            end
        end
        if (self.status == "following" and
            not mob_core.follow_holding(self, player)) then
            self.status = mobkit.remember(self, "status", "")
            return true
        end
    end
    mobkit.queue_high(self, func, prty)
end

-----------
-- Basic --
-----------

function mob_core.hq_follow_holding(self, prty, player, stop_threshold) -- Follow Player
    if not player then return end
    if not mob_core.follow_holding(self, player) then return end
    stop_threshold = stop_threshold or 2.5
    local func = function(self)
        if mobkit.is_queue_empty_low(self) then
            if mob_core.follow_holding(self, player) then
                local pos = mobkit.get_stand_pos(self)
                local tpos = player:get_pos()
                if vec_dist(pos, tpos) <= self.collisionbox[4] + stop_threshold then
                    mobkit.lq_idle(self, 0.1, "stand")
                else
                    if self.animation["run"] then
                        mobkit.animate(self, "run")
                    else
                        mobkit.animate(self, "walk")
                    end
                    self.status = mobkit.remember(self, "status", "following")
                    mobkit.clear_queue_low(self)
                    mob_core.goto_next_waypoint(self, tpos)
                end
            end
        end
        if (self.status == "following" and
            not mob_core.follow_holding(self, player)) then
            self.status = mobkit.remember(self, "status", "")
            mobkit.lq_idle(self, 1, "stand")
            return true
        end
    end
    mobkit.queue_high(self, func, prty)
end

-------------------------------
-- Modified Mobkit Functions --
-------------------------------

-- Is Neighbor Node Reachable -- Modified to add variable to ignore liquidflag

local function is_object_at_pos(self, pos)
    local objects = minetest.get_objects_inside_radius(pos, 0.5)
    if #objects < 1 then return false end
    for i = 1, #objects do
        if objects[i] ~= self.object and not (objects[i]:get_luaentity() and
            objects[i]:get_luaentity().collide_with_objects) then
            return true
        end
    end
    return false
end

local function moveable(self, pos)
    local width = mob_core.get_hitbox(self)[4]
    local height = self.height
    local pos1 = vector.new(pos.x - width, pos.y, pos.z - width)
    local pos2 = vector.new(pos.x + width, pos.y + height, pos.z + width)
    for x = pos1.x, pos2.x do
        for y = pos1.y, pos2.y do
            for z = pos1.z, pos2.z do
                local p2 = vector.new(x, y, z)
                local node = minetest.get_node(p2)
                local def = minetest.registered_nodes[node.name]
                if def and def.walkable and mobkit.get_node_height(p2) > 0 then
                    local p3 = vector.new(p2.x, p2.y + 1, p2.z)
                    local node2 = minetest.get_node(p3)
                    local def2 = minetest.registered_nodes[node2.name]
                    if def2 and def2.walkable and mobkit.get_node_height(p3) > 0 then
                        return false
                    end
                elseif is_object_at_pos(self, p2) then
                    return false
                end
            end
        end
    end
    return true
end

local neighbors = {
    {x = 1, z = 0}, {x = 1, z = 1}, {x = 0, z = 1}, {x = -1, z = 1},
    {x = -1, z = 0}, {x = -1, z = -1}, {x = 0, z = -1}, {x = 1, z = -1}
}

function mob_core.is_neighbor_node_reachable(self, neighbor)
    local fall = self.max_fall or self.jump_height
    local offset = neighbors[neighbor]
    local pos = mobkit.get_stand_pos(self)
    local tpos = mobkit.get_node_pos(mobkit.pos_shift(pos, offset))
    local recursteps = ceil(fall) + 1
    local height, liquidflag = mobkit.get_terrain_height(tpos, recursteps)
    if height and abs(height - pos.y) <= fall then
        tpos.y = height
        height = height - pos.y
        if neighbor % 2 == 0 then
            local n2 = neighbor - 1
            offset = neighbors[n2]
            local t2 = mobkit.get_node_pos(mobkit.pos_shift(pos, offset))
            local h2 = mobkit.get_terrain_height(t2, recursteps)
            if h2 and h2 - pos.y > 0.02 then return end
            n2 = (neighbor + 1) % 8
            offset = neighbors[n2]
            t2 = mobkit.get_node_pos(mobkit.pos_shift(pos, offset))
            h2 = mobkit.get_terrain_height(t2, recursteps)
            if h2 and h2 - pos.y > 0.02 then return end
        end
        if tpos.y + self.height - pos.y > 1 then
            local snpos = mobkit.get_node_pos(pos)
            local pos1 = {x = pos.x, y = snpos.y + 1, z = pos.z}
            local pos2 = {x = tpos.x, y = tpos.y + self.height, z = tpos.z}
            local nodes = mobkit.get_nodes_in_area(pos1, pos2, true)
            for p, node in pairs(nodes) do
                if snpos.x == p.x and snpos.z == p.z then
                    if node.name == 'ignore' or node.walkable then
                        return
                    end
                else
                    if node.name == 'ignore' or
                        (node.walkable and mobkit.get_node_height(p) > tpos.y +
                            0.001) then return end
                end
            end
        end
        if self.ignore_liquidflag then liquidflag = false end
        return height, tpos, liquidflag
    else
        if self.ignore_liquidflag and not mob_core.fall_check(self, pos, fall) then
            return 0.1, tpos, false
        end
        return
    end
end

-- Get next Waypoint -- Modified to make use of mob_core.is_neighbor_node_reachable()

function mob_core.get_next_waypoint(self, tpos)
    local pos = mobkit.get_stand_pos(self)
    local dir = vector.direction(pos, tpos)
    local neighbor = mobkit.dir2neighbor(dir)
    local function update_pos_history(self, pos)
        table.insert(self.pos_history, 1, pos)
        if #self.pos_history > 2 then
            table.remove(self.pos_history, #self.pos_history)
        end
    end
    local nogopos = self.pos_history[2]
    local height, pos2, liquidflag = mob_core.is_neighbor_node_reachable(self,
                                                                         neighbor)
    if height and not liquidflag and
        not (nogopos and mobkit.isnear2d(pos2, nogopos, 0.1)) then
        local heightl = mob_core.is_neighbor_node_reachable(self,
                                                            mobkit.neighbor_shift(
                                                                neighbor, -1))
        if heightl and abs(heightl - height) < 0.001 then
            local heightr = mob_core.is_neighbor_node_reachable(self,
                                                                mobkit.neighbor_shift(
                                                                    neighbor, 1))
            if heightr and abs(heightr - height) < 0.001 then
                dir.y = 0
                local dirn = vector.normalize(dir)
                local npos = mobkit.get_node_pos(
                                 mobkit.pos_shift(pos, neighbors[neighbor]))
                local factor =
                    abs(dirn.x) > abs(dirn.z) and abs(npos.x - pos.x) or
                        abs(npos.z - pos.z)
                pos2 = mobkit.pos_shift(pos, {
                    x = dirn.x * factor,
                    z = dirn.z * factor
                })
            end
        end
        update_pos_history(self, pos2)
        return height, pos2
    else
        for i = 1, 3 do
            local height, pos2, liq = mob_core.is_neighbor_node_reachable(self,
                                                                          mobkit.neighbor_shift(
                                                                              neighbor,
                                                                              -i *
                                                                                  self.path_dir))
            if height and not liq and
                not (nogopos and mobkit.isnear2d(pos2, nogopos, 0.1)) then
                update_pos_history(self, pos2)
                return height, pos2
            end
            height, pos2, liq = mob_core.is_neighbor_node_reachable(self,
                                                                    mobkit.neighbor_shift(
                                                                        neighbor,
                                                                        i *
                                                                            self.path_dir))
            if height and not liq and
                not (nogopos and mobkit.isnear2d(pos2, nogopos, 0.1)) then
                update_pos_history(self, pos2)
                return height, pos2
            end
        end
        height, pos2, liquidflag = mob_core.is_neighbor_node_reachable(self,
                                                                       mobkit.neighbor_shift(
                                                                           neighbor,
                                                                           4))
        if height and not liquidflag and
            not (nogopos and mobkit.isnear2d(pos2, nogopos, 0.1)) then
            update_pos_history(self, pos2)
            return height, pos2
        end
    end
    table.remove(self.pos_history, 2)
    self.path_dir = self.path_dir * -1
end

------------------------
-- Built-in behaviors --
------------------------

function mob_core.goto_next_waypoint(self, tpos, speed_factor)
    speed_factor = speed_factor or 1
    local _, pos2 = mob_core.get_next_waypoint(self, tpos)
    if pos2 then
        local yaw = self.object:get_yaw()
        local tyaw = minetest.dir_to_yaw(
                         vector.direction(self.object:get_pos(), pos2))
        mob_core.lq_dumbwalk(self, pos2, speed_factor)
        return true
    end
end

-- Dumbstep -- Modified to use new jump mechanic

function mob_core.lq_dumbwalk(self, tpos, speed_factor, anim)
    anim = anim or "walk"
    local timer = 2
    local func = function(self)
        local speed = speed_factor or 1
        local pos = mobkit.get_stand_pos(self)
        local dir = vector.direction(pos, tpos)
        local dist = vec_dist(pos, tpos)

        if dist <= 0.75 then
            return true
        end

        if not self.isonground then
            speed = speed * 0.5
        end

        local turn_rate = self.turn_rate or 8

        if dist < 2.5 then
            turn_rate = turn_rate + 2
        end

        timer = timer - self.dtime

        if timer <= 0 then return true end

        mobkit.turn2yaw(self, minetest.dir_to_yaw(dir), turn_rate)
        mobkit.go_forward_horizontal(self, self.max_speed * speed)
        mobkit.animate(self, anim)
    end
    mobkit.queue_low(self, func)
end

--[[function mob_core.lq_dumbwalk(self, dest, speed_factor, anim)
    local timer = 3 -- failsafe
    local width = mob_core.get_hitbox(self)[4]
    speed_factor = speed_factor or 1
    anim = anim or "walk"
    local func = function(self)
        mobkit.animate(self, anim)
        timer = timer - self.dtime
        if timer < 0 then return true end
        local s_fctr = speed_factor
        local pos = mobkit.get_stand_pos(self)
        local dir = vector.direction({x = pos.x, y = 0, z = pos.z},
                                     {x = dest.x, y = 0, z = dest.z})
        local y = self.object:get_velocity().y

        local yaw = self.object:get_yaw()
        local tyaw = minetest.dir_to_yaw(dir)

        if not self.isonground then s_fctr = 0.2 end

        local yaw_diff = diff(yaw, tyaw)

        if abs(yaw_diff) > 0.1 then
            mobkit.turn2yaw(self, tyaw, (self.turn_rate or 6) + abs(clamp(yaw_diff, -1, 1)))
        end

        if mobkit.isnear2d(pos, dest, clamp(width * 0.3125, 0.25, 1.5))
        and abs(dest.y - pos.y) < 1 then
            if (not self.isonground and not self.isinliquid) or
                abs(dest.y - pos.y) > 0.1 then
                self.object:set_velocity({x = 0, y = y, z = 0})
            end
            return true
        end

        if self.isonground
        or self.isinliquid then
            mobkit.go_forward_horizontal(self, self.max_speed * speed_factor)
        end
    end
    mobkit.queue_low(self, func)
end]]

function mob_core.dumbstep(self, tpos, speed_factor, idle_duration)
    mobkit.lq_turn2pos(self, tpos)
    mob_core.lq_dumbwalk(self, tpos, speed_factor)
    idle_duration = idle_duration or 6
    mobkit.lq_idle(self, random(ceil(idle_duration * 0.5), idle_duration))
end

-- Roam -- not finished

function mob_core.hq_roam(self, prty)
    local func = function(self)
        local fall = self.max_fall or self.jump_height
        self.status = mobkit.remember(self, "status", "")
        local pos = mobkit.get_stand_pos(self)
        if mobkit.is_queue_empty_low(self) and
            (self.isonground or not mob_core.fall_check(self, pos, fall)) then
            local neighbor = random(8)
            local _, tpos, liquidflag = mob_core.is_neighbor_node_reachable(
                                            self, neighbor)
            if tpos and not mob_core.fall_check(self, tpos, fall) and
                not liquidflag then
                mob_core.dumbstep(self, tpos, 0.3, random(4, 8))
            end
        end
    end
    mobkit.queue_high(self, func, prty)
end

------------------------------
-- Recoded Mobkit Functions --
------------------------------

-- Run From --

function mob_core.hq_runfrom(self, prty, tgtobj)
    local init = false
    local timer = 6
    local func = function(self)
        if not mobkit.is_alive(tgtobj) then return true end
        if not init then
            timer = timer - self.dtime
            if timer <= 0 or vec_dist(self.object:get_pos(), tgtobj:get_pos()) <
                8 then
                mobkit.make_sound(self, 'scared')
                init = true
            end
        end
        mobkit.animate(self, "run")
        self.status = mobkit.remember(self, "status", "fleeing")
        if mobkit.is_queue_empty_low(self) and self.isonground then
            local pos = mobkit.get_stand_pos(self)
            local opos = tgtobj:get_pos()
            if vec_dist(pos, opos) < self.view_range * 1.1 then
                local tpos = {
                    x = 2 * pos.x - opos.x,
                    y = opos.y,
                    z = 2 * pos.z - opos.z
                }
                mob_core.goto_next_waypoint(self, tpos)
            else
                mobkit.lq_idle(self, 1)
                self.object:set_velocity({x = 0, y = 0, z = 0})
                return true
            end
        end
    end
    mobkit.queue_high(self, func, prty)
end

-- Liquid Recovery -- Recoded to be smoother and more reliably find land

function mob_core.hq_liquid_recovery(self, prty, anim)
    local tpos
    local init = false
    anim = anim or "walk"
    local func = function(self)
        if not init then
            mobkit.animate(self, anim)
            init = true
        end
        if self.isonground and not self.isinliquid then
            mobkit.lq_idle(self, 0.1, "stand")
            return true
        end
        local pos = mobkit.get_stand_pos(self)
        if not tpos then
            local pos1 = vector.new(pos.x - self.view_range, pos.y - 1,
                                    pos.z - self.view_range)
            local pos2 = vector.new(pos.x + self.view_range, pos.y,
                                    pos.z + self.view_range)
            local walkable_nodes = minetest.find_nodes_in_area_under_air(pos1,
                                                                         pos2,
                                                                         mob_core.walkable_nodes)
            tpos = find_closest_pos(walkable_nodes, pos)
        end
        if tpos then
            local dist = vec_dist(pos, tpos)
            mobkit.drive_to_pos(self, tpos, self.max_speed * 0.75, 1,
                                self.collisionbox[4] * 1.25)
            if dist < self.collisionbox[4] * 1.75 then
                mobkit.clear_queue_low(self)
                mobkit.lq_turn2pos(self, tpos)
                local vel = self.object:get_velocity()
                vel.y = self.jump_height
                self.object:set_velocity(vel)
                minetest.after(0.3, function(self, vel)
                    if self.object:get_luaentity() then
                        self.object:set_acceleration(
                            {x = vel.x * 2, y = 0, z = vel.z * 2})
                    end
                end, self, vel)
                return true
            end
        end
    end
    mobkit.queue_high(self, func, prty)
end

-- Hunt -- Recoded to use various Mob Core functions

function mob_core.hq_hunt(self, prty, target)
    local scan_pos = target:get_pos()
    scan_pos.y = scan_pos.y + 1
    if not line_of_sight(self.object:get_pos(), scan_pos) then return true end
    local func = function(self)
        if not mobkit.is_alive(target) then
            mobkit.clear_queue_high(self)
            return true
        end
        local pos = mobkit.get_stand_pos(self)
        local tpos = target:get_pos()
        mob_core.punch_timer(self)
        if mobkit.is_queue_empty_low(self) then
            self.status = mobkit.remember(self, "status", "hunting")
            local dist = vec_dist(pos, tpos)
            local yaw = self.object:get_yaw()
            local tyaw = minetest.dir_to_yaw(vector.direction(pos, tpos))
            if abs(tyaw - yaw) > 0.1 then
                mobkit.lq_turn2pos(self, tpos)
            end
            if dist > self.view_range then
                self.status = mobkit.remember(self, "status", "")
                return true
            end
            local target_side = abs(target:get_properties().collisionbox[4])
            mob_core.goto_next_waypoint(self, tpos)
            if vec_dist(pos, tpos) < self.reach + target_side then
                self.status = mobkit.remember(self, "status", "")
                mob_core.lq_dumb_punch(self, target, "stand")
            end
        end
    end
    mobkit.queue_high(self, func, prty)
end

------------------------
-- Built-in Behaviors --
------------------------

function mob_core.fly_to_next_waypoint(self, pos2, speed_factor)
    speed_factor = speed_factor or 0.75

    local lift
    local tyaw

    mobkit.animate(self, "fly")

    local pos = mobkit.get_stand_pos(self)

    local steer_to, turn_intensity = mob_core.collision_avoidance(self)

    local ceiling = sensor_ceil(self, self.view_range)

    -- Basic Movement
    if self.isonground or self.isinliquid then return end

    lift = 0

    tyaw = minetest.dir_to_yaw(vector.direction(pos, pos2))

    if ceiling <= self.height * 2 then
        if lift > -1 then lift = lift - 0.2 end
    end

    if steer_to then tyaw = minetest.dir_to_yaw(steer_to) end

    local dir = vector.direction(pos, pos2)
    if dir.y > 0 then
        lift = dir.y * self.max_speed
    else
        lift = dir.y * self.max_speed
    end

    local dist = vec_dist(pos, pos2)
    if dist < self.collisionbox[4] then return true end

    if not turn_intensity or turn_intensity < 1 then turn_intensity = 1 end

    mob_core.tilt_to_yaw(self, tyaw, (self.turn_rate or 6) * turn_intensity)
    set_lift(self, lift)
    mobkit.go_forward_horizontal(self, self.max_speed * speed_factor)
end

function mob_core.swim_to_next_waypoint(self, pos2, speed_factor)
    speed_factor = speed_factor or 0.75

    local lift
    local tyaw

    mobkit.animate(self, "swim")

    local pos = mobkit.get_stand_pos(self)

    local steer_to, turn_intensity = mob_core.collision_avoidance(self)

    local ceiling = sensor_ceil(self, self.view_range)

    -- Basic Movement
    if self.isonground or not self.isinliquid then return end

    lift = 0

    tyaw = minetest.dir_to_yaw(vector.direction(pos, pos2))

    if ceiling <= self.height * 2 then
        if lift > -1 then lift = lift - 0.2 end
    end

    if steer_to then tyaw = minetest.dir_to_yaw(steer_to) end

    local dir = vector.direction(pos, pos2)
    if dir.y > 0 then
        lift = dir.y * self.max_speed
    else
        lift = dir.y * self.max_speed
    end

    local dist = vec_dist(pos, pos2)
    if dist < self.collisionbox[4] then return true end

    if not turn_intensity or turn_intensity < 1 then turn_intensity = 1 end

    mobkit.turn2yaw(self, tyaw, (self.turn_rate or 2) * turn_intensity)
    set_lift(self, lift)
    mobkit.go_forward_horizontal(self, self.max_speed * speed_factor)
end
