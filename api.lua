------------------
-- Mob Core API --
------------------
----- Ver 0.1 ----

----------
-- Math --
----------

local random = math.random
local abs = math.abs
local ceil = math.ceil
local floor = math.floor

local vec_dir = vector.direction
local vec_dist = vector.distance

local function dist_2d(pos1, pos2)
    local a = vector.new(pos1.x, 0, pos1.z)
    local b = vector.new(pos2.x, 0, pos2.z)
    return vec_dist(a, b)
end

--------------
-- Settings --
--------------

local creative = minetest.settings:get_bool("creative_mode")

--------------------
-- Misc Functions --
--------------------

local function is_node_walkable(name)
    local def = minetest.registered_nodes[name]
    return def and def.walkable
end

local function is_node_liquid(name)
    local def = minetest.registered_nodes[name]
    return def and def.drawtype == "liquid"
end

function mob_core.get_name_proper(str)
    if str then
        if str:match(":") then str = str:split(":")[2] end
        return (string.gsub(" " .. str, "%W%l", string.upper):sub(2):gsub("_", " "))
    end
end

function mob_core.find_val(tbl, val)
    for _, v in ipairs(tbl) do if v == val then return true end end
    return false
end

-------------------------
-- Logic-Use Functions --
-------------------------

function mob_core.is_mobkit_mob(object)
    if type(object) == 'userdata' then object = object:get_luaentity() end
    if type(object) == 'table' then
        if (object.logic or object.brainfunc) then
            return true
        else
            return false
        end
    else
        return false
    end
end

function mob_core.is_object_nearby(self, name)
    for _, obj in ipairs(self.nearby_objects) do
        if obj and obj:get_luaentity() and obj:get_luaentity().name == name then
            return true, obj
        end
    end
    return false
end

function mob_core.check_shared_owner(self, object)
    if not mobkit.is_alive(object) then return false end
    if object:is_player() then return false end
    if type(object) == 'userdata' then object = object:get_luaentity() end
    if not self.tamed then return false end
    if self.owner and object.owner then
        if self.owner == object.owner then
            return true
        else
            return false
        end
    end
    return false
end

mob_core.shared_owner = mob_core.check_shared_owner -- Deprecated name support

function mob_core.follow_holding(self, player)
    local item = player:get_wielded_item()
    local t = type(self.follow)
    if t == "string" and item:get_name() == self.follow then
        return true
    elseif t == "table" then
        for no = 1, #self.follow do
            if self.follow[no] == item:get_name() then return true end
        end
    end
    return false
end

-----------------------
-- Mob Item Handling --
-----------------------

function mob_core.register_spawn_egg(mob, col1, col2, inventory_image)
    if col1 and col2 then
        local len1 = string.len(col1)
        local len2 = string.len(col2)
        if len1 == 6 then col1 = col1 .. "d9" end
        if len2 == 6 then col2 = col2 .. "d9" end
        local base =
            "mob_core_spawn_egg_base.png^(mob_core_spawn_egg_base.png^[colorize:#" ..
                col1 .. ")"
        local spots =
            "mob_core_spawn_egg_overlay.png^(mob_core_spawn_egg_overlay.png^[colorize:#" ..
                col2 .. ")"
        inventory_image = base .. "^" .. spots
    end
    minetest.register_craftitem(mob:split(":")[1] .. ":spawn_" ..
                                    mob:split(":")[2], {
        description = "Spawn " .. mob_core.get_name_proper(mob),
        inventory_image = inventory_image,
        stack_max = 99,
        on_place = function(itemstack, _, pointed_thing)
            local mobdef = minetest.registered_entities[mob]
            local spawn_offset = math.abs(mobdef.collisionbox[2])
            local pos = minetest.get_pointed_thing_position(pointed_thing, true)
            pos.y = pos.y + spawn_offset
            minetest.add_entity(pos, mob)
            if not creative then
                itemstack:take_item()
                return itemstack
            end
        end
    })
end

function mob_core.register_set(mob, background, mask)
    local invimg = background
    if mask then
        invimg = "mob_core_spawn_egg_base.png^(" .. invimg ..
                     "^[mask:mob_core_spawn_egg_overlay.png)"
    end
    if not minetest.registered_entities[mob] then return end
    -- register new spawn egg containing mob information
    minetest.register_craftitem(mob .. "_set", {
        description = mob_core.get_name_proper(mob) .. " (Captured)",
        inventory_image = invimg,
        groups = {not_in_creative_inventory = 1},
        stack_max = 1,
        on_place = function(itemstack, placer, pointed_thing)
            local pos = pointed_thing.above
            -- am I clicking on something with existing on_rightclick function?
            local under = minetest.get_node(pointed_thing.under)
            local node = minetest.registered_nodes[under.name]
            if node and node.on_rightclick then
                return node.on_rightclick(pointed_thing.under, under, placer,
                                          itemstack)
            end
            if pos and not minetest.is_protected(pos, placer:get_player_name()) then
                pos.y = pos.y + 1
                local staticdata = itemstack:get_meta():get_string("staticdata")
                minetest.add_entity(pos, mob, staticdata)
                itemstack:take_item()
            end
            return itemstack
        end
    })
end

-----------------------
-- Spatial Functions --
-----------------------

function mob_core.sensor_floor(self, range, water)
    water = water or false
    local pos = self.object:get_pos()
    local node = minetest.get_node(pos)
    local dist = 0
    while (not is_node_walkable(node.name)
    or (water and minetest.registered_nodes[node.name].drawtype ~= "liquid"))
    and abs(dist) <= range do
        pos.y = pos.y - 1
        node = minetest.get_node(pos)
        dist = dist + 1
        if is_node_walkable(node.name)
        or (water and minetest.registered_nodes[node.name].drawtype == "liquid") then
            break
        end
    end
    if is_node_walkable(node.name)
    or (water and minetest.registered_nodes[node.name].drawtype == "liquid") then
        return dist
    elseif dist >= range then
        return range
    end
end

function mob_core.is_moveable(pos, width, height)
    local pos1 = vector.new(pos.x - width, pos.y, pos.z - width)
    local pos2 = vector.new(pos.x + width, pos.y, pos.z + width)
    for x = pos1.x, pos2.x do
        for z = pos1.z, pos2.z do
            local pos3 = vector.new(x, (pos.y + height), z)
            local pos4 = {x = pos3.x, y = pos.y + 1, z = pos3.z}
            local ray = minetest.raycast(pos3, pos4, false, false)
            for pointed_thing in ray do
                if pointed_thing.type == "node" then
                    return false
                end
            end
        end
    end
    return true
end

------------
-- Sounds --
------------

function mob_core.make_sound(self, sound)
    local spec = self.sounds and self.sounds[sound]
    local parameters = {object = self.object}

    if type(spec) == 'table' then
        if #spec > 0 then spec = spec[random(#spec)] end

        local function in_range(value)
            return type(value) == 'table' and value[1] + random() *
                       (value[2] - value[1]) or value
        end

        local pitch = 1.0

        pitch = pitch - (random(-10, 10) * 0.005)

        if self.child and self.sounds.alter_child_pitch then
            parameters.pitch = 2.0
        end

        minetest.sound_play(spec, parameters)

        if not spec.gain then spec.gain = 1.0 end
        if not spec.distance then spec.distance = 16 end

        -- pick random values within a range if they're a table
        parameters.gain = in_range(spec.gain)
        parameters.max_hear_distance = in_range(spec.distance)
        parameters.fade = in_range(spec.fade)
        parameters.pitch = pitch
        return minetest.sound_play(spec.name, parameters)
    end
    return minetest.sound_play(spec, parameters)
end

function mob_core.random_sound(self, chance) -- Random Sound
    if not chance then chance = 150 end
    if math.random(1, chance) == 1 then mobkit.make_sound(self, "random") end
end

----------------
-- Drop Items --
----------------

function mob_core.item_drop(self) -- Drop Items
    if not self.drops or #self.drops == 0 then return end
    local obj, item, num
    local pos = mobkit.get_stand_pos(self)
    for n = 1, #self.drops do
        if math.random(1, self.drops[n].chance) == 1 then
            num = math.random(self.drops[n].min or 0, self.drops[n].max or 1)
            item = self.drops[n].name
            if self.drops[n].min ~= 0 then
                obj = minetest.add_item(pos, ItemStack(item .. " " .. num))
                if obj then
                    local v = math.random(-1, 1)
                    obj:add_velocity({x = v, y = 1, z = v})
                end
            elseif obj then
                obj:remove()
            end
        end
    end
    self.drops = {}
end

------------------------
--  Damage and Vitals --
------------------------

-- Damage Indication

local function flash_red(self)
    minetest.after(0.0, function()
        self.object:settexturemod("^[colorize:#FF000040")
        core.after(0.2, function()
            if mobkit.is_alive(self) then
                self.object:settexturemod("")
            end
        end)
    end)
end

-- Death

function mob_core.on_die(self)
    local pos = mobkit.get_stand_pos(self)
    if self.driver then mob_core.force_detach(self.driver) end
    if self.owner then self.owner = nil end
    if self.sounds and self.sounds["death"] then
        mob_core.make_sound(self, "death")
    end
    self.object:set_velocity({x = 0, y = 0, z = 0})
    self.object:settexturemod("^[colorize:#FF000040")
    local timer = 1
    local start = true
    local func = function()
        if not mobkit.exists(self) then return true end
        if start then
            if self.animation and self.animation["death"] then
                mobkit.animate(self, "death")
            else
                mobkit.clear_queue_low(self)
                mobkit.lq_fallover(self)
            end
            self.logic = function() end -- brain dead as well
            start = false
        end
        timer = timer - self.dtime
        if timer <= 0 and mobkit.is_queue_empty_low(self) then
            if self.driver then mob_core.force_detach(self.driver) end
            mob_core.item_drop(self)
            minetest.add_particlespawner(
                {
                    amount = 12,
                    time = 0.1,
                    minpos = {
                        x = pos.x - self.collisionbox[4] * 0.75,
                        y = pos.y,
                        z = pos.z - self.collisionbox[4] * 0.75
                    },
                    maxpos = {
                        x = pos.x + self.collisionbox[4] * 0.75,
                        y = pos.y + self.collisionbox[4] * 0.75,
                        z = pos.z + self.collisionbox[4] * 0.75
                    },
                    minvel = {x = -0.2, y = -0.1, z = -0.2},
                    maxvel = {x = 0.2, y = -0.1, z = 0.2},
                    minacc = {x = 0, y = 0.25, z = 0},
                    maxacc = {x = 0, y = 0.45, z = 0},
                    minexptime = 1.5,
                    maxexptime = 2,
                    minsize = 2,
                    maxsize = 3,
                    collisiondetection = true,
                    vertical = false,
                    texture = "mob_core_red_particle.png"
                })
            self.object:remove()
        end
        minetest.after(2, function() -- fail safe
            if not mobkit.exists(self) then return true end
            if self.driver then mob_core.force_detach(self.driver) end
            mob_core.item_drop(self)
            minetest.add_particlespawner(
                {
                    amount = self.collisionbox[4] * 4,
                    time = 0.25,
                    minpos = {
                        x = pos.x - self.collisionbox[4] * 0.5,
                        y = pos.y,
                        z = pos.z - self.collisionbox[4] * 0.5
                    },
                    maxpos = {
                        x = pos.x + self.collisionbox[4] * 0.5,
                        y = pos.y + self.collisionbox[4] * 0.5,
                        z = pos.z + self.collisionbox[4] * 0.5
                    },
                    minacc = {x = -0.25, y = 0.5, z = -0.25},
                    maxacc = {x = 0.25, y = 0.25, z = 0.25},
                    minexptime = 0.75,
                    maxexptime = 1,
                    minsize = 4,
                    maxsize = 4,
                    texture = "mob_core_red_particle.png",
                    glow = 16
                })
            self.object:remove()
        end)
    end
    mobkit.queue_high(self, func, 100)
end

-- Vitals

function mob_core.vitals(self)
    if not mobkit.is_alive(self) then return end
    -- Fall Damage
    if self.fall_damage == nil then self.fall_damage = true end
    if self.fall_damage then
        if not self.isonground and not self.isinliquid and not self.fall_start then
            self.fall_start = mobkit.get_stand_pos(self).y
        end
        if self.fall_start then
            local fall_distance = self.fall_start - mobkit.get_stand_pos(self).y
            if not self.max_fall then self.max_fall = 3 end
            if self.isonground then
                if fall_distance > self.max_fall then
                    flash_red(self)
                    mob_core.make_sound(self, "hurt")
                    mobkit.hurt(self, fall_distance)
                end
                self.fall_start = nil
            end
        end
    end

    if mobkit.timer(self, 1) then
        -- Lava/Fire Damage
        if self.igniter_damage == nil then self.igniter_damage = true end

        if self.igniter_damage then
            local pos = mobkit.get_stand_pos(self)
            local node = minetest.get_node(pos)
            if node and minetest.registered_nodes[node.name].groups.igniter then
                if mobkit.timer(self, 1) then
                    flash_red(self)
                    mob_core.make_sound(self, "hurt")
                    mobkit.hurt(self, self.max_hp / 16)
                end
            end
        end

        -- Drowning
        if self.lung_capacity then
            local colbox = self.object:get_properties().collisionbox
            local headnode = mobkit.nodeatpos(
                                 mobkit.pos_shift(self.object:get_pos(),
                                                  {y = colbox[5]})) -- node at hitbox top
            if headnode and headnode.drawtype == 'liquid' then
                self.oxygen = self.oxygen - self.dtime
            else
                self.oxygen = self.lung_capacity
            end

            if self.oxygen <= 0 then
                if mobkit.timer(self, 2) then
                    flash_red(self)
                    mobkit.hurt(self, self.max_hp / self.lung_capacity)
                end
            end
        end
    end
end

-- Basic Damage

function mob_core.on_punch_basic(self, puncher, tool_capabilities, dir)
    local item = puncher:get_wielded_item()
    if mobkit.is_alive(self) then
        if self.immune_to then
            for i = 1, #self.immune_to do
                if item:get_name() == self.immune_to[i] then
                    return
                end
            end
        end
        if self.protected == true and puncher:get_player_name() ~= self.owner then
            return
        else
            flash_red(self)
            if self.isonground then
                local hvel = vector.multiply(
                                 vector.normalize({x = dir.x, y = 0, z = dir.z}),
                                 4)
                self.object:add_velocity({x = hvel.x, y = 2, z = hvel.z})
            end
            mobkit.hurt(self, tool_capabilities.damage_groups.fleshy or 1)
            if math.random(4) < 2 then
                mob_core.make_sound(self, "hurt")
            end
        end
    end
end

-- Retaliate

function mob_core.on_punch_retaliate(self, puncher, water, group)
    if mobkit.is_alive(self) then
        local pos = self.object:get_pos()
        if (not water) or (water and self.semiaquatic) then
            mob_core.hq_hunt(self, 10, puncher)
            if group then
                local objs = minetest.get_objects_inside_radius(pos,
                                                                self.view_range)
                for n = 1, #objs do
                    local luaent = objs[n]:get_luaentity()
                    if luaent and luaent.name == self.name and luaent.owner ==
                        self.owner and mobkit.is_alive(luaent) then
                        mob_core.hq_hunt(luaent, 10, puncher)
                    end
                end
            end
        elseif water and self.isinliquid then
            mob_core.hq_aqua_attack(self, 10, puncher, 1)
            if group then
                local objs = minetest.get_objects_inside_radius(pos,
                                                                self.view_range)
                for n = 1, #objs do
                    local luaent = objs[n]:get_luaentity()
                    if luaent and luaent.name == self.name and luaent.owner ==
                        self.owner and mobkit.is_alive(luaent) then
                        mob_core.hq_aqua_attack(luaent, 10, puncher, 1)
                    end
                end
            end
        end
    end
end

-- Runaway

function mob_core.on_punch_runaway(self, puncher, water, group)
    if mobkit.is_alive(self) then
        local pos = self.object:get_pos()
        if (not water) or (water and not self.isinliquid) then
            mobkit.hq_runfrom(self, 10, puncher)
            if group then
                local objs = minetest.get_objects_inside_radius(pos,
                                                                self.view_range)
                for n = 1, #objs do
                    local luaent = objs[n]:get_luaentity()
                    if luaent and luaent.name == self.name and luaent.owner ==
                        self.owner and mobkit.is_alive(luaent) then
                        mobkit.hq_runfrom(self, 10, puncher)
                    end
                end
            end
        elseif water and self.isinliquid then
            mob_core.hq_swimfrom(self, 10, puncher, 1)
            if group then
                local objs = minetest.get_objects_inside_radius(pos,
                                                                self.view_range)
                for n = 1, #objs do
                    local luaent = objs[n]:get_luaentity()
                    if luaent and luaent.name == self.name and luaent.owner ==
                        self.owner and mobkit.is_alive(luaent) then
                        mob_core.hq_swimfrom(luaent, 10, puncher, 1)
                    end
                end
            end
        end
    end
end

-- Default On Punch
-- This function should only be used for reference.

function mob_core.on_punch(self, puncher, time_from_last_punch,
                           tool_capabilities, dir)
    mob_core.on_punch_basic(self, puncher, time_from_last_punch,
                            tool_capabilities, dir)
end

-----------------
-- On Activate --
-----------------

local function set_gender(self)
    self.gender = mobkit.recall(self, "gender") or nil
    if not self.gender then
        if math.random(1, 2) == 1 then
            self.gender = mobkit.remember(self, "gender", "female")
        else
            self.gender = mobkit.remember(self, "gender", "male")
        end
    end
end

function mob_core.activate_nametag(self)
    if not self.nametag then return end
    self.object:set_properties({
        nametag = self.nametag,
        nametag_color = "#FFFFFF"
    })
end

function mob_core.set_textures(self)
    if not self.texture_no then
        if self.gender == "male" and self.male_textures then
            if #self.male_textures > 1 then
                self.texture_no = random(#self.male_textures)
            else
                self.texture_no = 1
            end
        end
        if self.gender == "female" and self.female_textures then
            if #self.female_textures > 1 then
                self.texture_no = random(#self.female_textures)
            else
                self.texture_no = 1
            end
        end
    end
    if self.textures and self.texture_no then
        local texture_no = self.texture_no
        local props = {}
        if self.gender == "female" then
            if self.female_textures then
                props.textures = {self.female_textures[texture_no]}
            else
                props.textures = {self.textures[texture_no]}
            end
        elseif self.gender == "male" then
            if self.male_textures then
                props.textures = {self.male_textures[texture_no]}
            else
                props.textures = {self.textures[texture_no]}
            end
        end
        if self.child and self.child_textures then
            if self.gender == "female" then
                if self.child_female_textures then
                    if texture_no > #self.child_female_textures then
                        texture_no = 1
                    end
                    props.textures = {self.child_female_textures[texture_no]}
                else
                    if texture_no > #self.child_textures then
                        texture_no = 1
                    end
                    props.textures = {self.child_textures[texture_no]}
                end
            elseif self.gender == "male" then
                if self.child_male_textures then
                    if texture_no > #self.child_male_textures then
                        texture_no = 1
                    end
                    props.textures = {self.child_male_textures[texture_no]}
                else
                    if texture_no > #self.child_textures then
                        texture_no = 1
                    end
                    props.textures = {self.child_textures[texture_no]}
                end
            end
        end
        self.object:set_properties(props)
    end
end

function mob_core.on_activate(self, staticdata, dtime_s) -- On Activate
    local init_props = {}
    if not self.textures then
        if self.female_textures then
            init_props.textures = {self.female_textures[1]}
        elseif self.male_textures then
            init_props.textures = {self.male_textures[1]}
        end
        self.object:set_properties(init_props)
    end
    if not self.textures then self.textures = {} end
    mobkit.actfunc(self, staticdata, dtime_s)
    self.tamed = mobkit.recall(self, "tamed") or false
    self.owner = mobkit.recall(self, "owner") or nil
    self.protected = mobkit.recall(self, "protected") or false
    self.food = mobkit.recall(self, "food") or 0
    self.punch_timer = 0
    self.growth_stage = mobkit.recall(self, "growth_stage") or 4
    self.growth_timer = mobkit.recall(self, "growth_timer") or 1801
    self.child = mobkit.recall(self, "child") or false
    self.status = mobkit.recall(self, "status") or ""
    self.nametag = mobkit.recall(self, "nametag") or ""
    self._tyaw = self.object:get_yaw()
    set_gender(self)
    mob_core.activate_nametag(self)
    mob_core.set_textures(self)
    if self.protected then self.timeout = nil end
    if self.growth_stage == 1 and self.scale_stage1 then
        mob_core.set_scale(self, self.scale_stage1)
    elseif self.growth_stage == 2 and self.scale_stage2 then
        mob_core.set_scale(self, self.scale_stage2)
    elseif self.growth_stage == 3 and self.scale_stage3 then
        mob_core.set_scale(self, self.scale_stage3)
    elseif self.growth_stage == 4 then
        mob_core.set_scale(self, 1)
    end
    local neighbor_offset = math.ceil(mob_core.get_hitbox(self)[4])
    self._neighbors = {
        {x = neighbor_offset, z = 0},
        {x = neighbor_offset, z = neighbor_offset},
        {x = 0, z = neighbor_offset},
        {x = -neighbor_offset, z = neighbor_offset},
        {x = -neighbor_offset, z = 0},
        {x = -neighbor_offset, z = -neighbor_offset},
        {x = 0, z = -neighbor_offset},
        {x = neighbor_offset, z = -neighbor_offset}
    }
end

-----------------------
-- Utility Functions --
-----------------------

-- Set Scale --

function mob_core.set_scale(self, scale)
    self.base_size = self.visual_size or {x = 1, y = 1, z = 1}
    self.base_colbox = self.collisionbox or {-0.5, -0.5, -0.5, 0.5, 0.5, 0.5}

    self.object:set_properties({
        visual_size = {
            x = self.base_size.x * scale,
            y = self.base_size.y * scale
        },
        collisionbox = {
            self.base_colbox[1] * scale, self.base_colbox[2] * scale,
            self.base_colbox[3] * scale, self.base_colbox[4] * scale,
            self.base_colbox[5] * scale, self.base_colbox[6] * scale
        }
    })
end

-- Set Owner --

function mob_core.set_owner(self, name)
    self.tamed = mobkit.remember(self, "tamed", true)
    self.owner = mobkit.remember(self, "owner", name)
end

--------------
-- Spawning --
--------------

-- Spawn Child Mob --

function mob_core.spawn_child(pos, mob)
    local obj = minetest.add_entity(pos, mob)
    local luaent = obj:get_luaentity()
    luaent.child = mobkit.remember(luaent, "child", true)
    luaent.growth_timer = mobkit.remember(luaent, "growth_timer", 1)
    luaent.growth_stage = mobkit.remember(luaent, "growth_stage", 1)
    mob_core.set_scale(luaent, luaent.scale_stage1 or 0.25)
    mob_core.set_textures(luaent)
    return obj
end

-- Spawning --

function mob_core.get_biome_name(pos)
    if not pos then return end
    return minetest.get_biome_name(minetest.get_biome_data(pos).biome)
end

local find_node_height = 32

local block_protected_spawn = minetest.settings:get_bool("block_protected_spawn") or true
local mob_limit = tonumber(minetest.settings:get("mob_limit")) or 6

function mob_core.spawn(name, nodes, min_light, max_light, min_height,
                        max_height, min_rad, max_rad, group, optional)
    group = group or 1
    local total_mobs = {}
    local mob_spawned = false
    local spawned_pos = nil
    if minetest.registered_entities[name] then
        for _, player in ipairs(minetest.get_connected_players()) do
            local spawn_mob = true
            local mobs_amount = 0
            for _, entity in pairs(minetest.luaentities) do
                if entity.name == name then
                    local ent_pos = entity.object:get_pos()
                    if ent_pos
                    and vec_dist(player:get_pos(), ent_pos) <= 1024 then
                        mobs_amount = mobs_amount + 1
                    end
                end
            end

            if mobs_amount >= mob_limit then spawn_mob = false end

            local int = {-1, 1}
            local pos = vector.floor(vector.add(player:get_pos(), 0.5))

            local x0, z0

            -- this is used to determine the axis buffer from the player
            local axis = math.random(0, 1)

            -- cast towards the direction
            if axis == 0 then -- x
                x0 = pos.x + math.random(min_rad, max_rad) * int[random(1, 2)]
                z0 = pos.z + math.random(-max_rad, max_rad)
            else -- z
                z0 = pos.z + math.random(min_rad, max_rad) * int[random(1, 2)]
                x0 = pos.x + math.random(-max_rad, max_rad)
            end

            local pos1 = vector.new(x0 - 5, pos.y - find_node_height, z0 - 5)
            local pos2 = vector.new(x0 + 5, pos.y + find_node_height, z0 + 5)
            local vm = minetest.get_voxel_manip()
            local emin, emax = vm:read_from_map(pos1, pos2)
            local area = VoxelArea:new{MinEdge = emin, MaxEdge = emax}
            local data = vm:get_data()

            local spawner = {}

            for z = pos1.z, pos2.z do
                for y = pos1.y, pos2.y do
                    for x = pos1.x, pos2.x do
                        local vi = area:index(x, y, z)
                        local vi_pos = area:position(vi)
                        local vi_name = minetest.get_name_from_content_id(data[vi])
                        if is_node_walkable(minetest.get_name_from_content_id(data[vi])) then
                            local _vi = area:index(x, y + 1, z)
                            if data[_vi] == minetest.get_content_id("air") then
                                table.insert(spawner, area:position(_vi))
                            end
                        end
                    end
                end
            end

            if table.getn(spawner) > 0 then

                local mob_pos = spawner[1]

                if block_protected_spawn and minetest.is_protected(mob_pos, "") then
                    spawn_mob = false
                end

                if optional then
                    if optional.biomes then
                        if not mob_core.find_val(optional.biomes, mob_core.get_biome_name(pos)) then
                            spawn_mob = false
                        end
                    end
                end

                if mob_pos.y > max_height or mob_pos.y < min_height then
                    spawn_mob = false
                end

                local light = minetest.get_node_light(mob_pos)
                if not light or light > max_light or light < min_light then
                    spawn_mob = false
                end


                if spawn_mob then

                    mob_spawned = true

                    spawned_pos = mob_pos
    
                    local obj = minetest.add_entity(mob_pos, name)
    
                    table.insert(total_mobs, obj)
    
                    if group then
    
                        local attempts = 0
    
                        while attempts < group do
                            local mobdef = minetest.registered_entities[name]
                            local side = mobdef.collisionbox[4]
                            local group_pos =
                                vector.new(mob_pos.x +
                                               (random(-group, group) * side),
                                           mob_pos.y, mob_pos.z +
                                               (random(-group, group) * side))
                            local spawn_pos =
                                minetest.find_nodes_in_area_under_air(
                                    vector.new(group_pos.x, group_pos.y - 8,
                                               group_pos.z),
                                    vector.new(group_pos.x, group_pos.y + 8,
                                               group_pos.z), nodes)
                            if spawn_pos[1] then
                                local obj_i =
                                    minetest.add_entity(
                                        vector.new(spawn_pos[1].x, spawn_pos[1].y +
                                                       math.abs(
                                                           mobdef.collisionbox[2]),
                                                   spawn_pos[1].z), name)
                                table.insert(total_mobs, obj_i)
                            end
                            attempts = attempts + 1
                        end
                    end
                    if mob_core.registered_on_spawns[name] then
                        mob_core.registered_spawns[name].last_pos = spawned_pos
                        mob_core.registered_spawns[name].mobs = total_mobs
                        local on_spawn = mob_core.registered_on_spawns[name]
                        on_spawn.func(unpack(on_spawn.args))
                    end
                end
            end
        end
        return mob_spawned, spawned_pos, total_mobs
    end
end

function mob_core.force_spawn(pos, mob)
    minetest.forceload_block(pos, false)
    minetest.after(4, function()
        local ent = minetest.add_entity(pos, mob)
        minetest.after(0.01, function()
            local loop = true
            local objects = minetest.get_objects_inside_radius(pos, 0.5)
            for i = 1, #objects do
                local object = objects[i]
                if object
                and object:get_luaentity()
                and object:get_luaentity().name == mob then
                    loop = false
                end
            end
            minetest.after(1, function()
                minetest.forceload_free_block(pos)
            end)
            if loop then
                mob_core.force_spawn(pos, mob)
            end 
        end)
    end)
end

function mob_core.spawn_at_pos(pos, name, nodes, group, optional)
    group = group or 1
    if minetest.registered_entities[name] then
        local spawn_mob = true
        local mobs_amount = 0
        for _, entity in pairs(minetest.luaentities) do
            if entity.name == name then
                local ent_pos = entity.object:get_pos()
                if ent_pos
                and vec_dist(pos, ent_pos) <= 1024 then
                    mobs_amount = mobs_amount + 1
                end
            end
        end

        if mobs_amount >= mob_limit then spawn_mob = false end

        local int = {-1, 1}

        local pos1 = vector.new(pos.x - 5, pos.y - 5, pos.z - 5)
        local pos2 = vector.new(pos.x + 5, pos.y + 5, pos.z + 5)

        local spawner = minetest.find_nodes_in_area_under_air(pos1, pos2, mob_core.walkable_nodes)

        if table.getn(spawner) > 0 then

            local mob_pos = spawner[1]

            mob_pos.y = mob_pos.y + 1

            if block_protected_spawn and minetest.is_protected(mob_pos, "") then
                spawn_mob = false
            end

            if optional then
                if optional.biomes then
                    spawn_mob = false
                    local biome = mob_core.get_biome_name(mob_pos)
                    for i = 1, #optional.biomes do
                        if optional.biomes[i]:match("^" .. biome) then
                            spawn_mob = true
                        end
                    end
                end
            end

            if spawn_mob then

                mob_core.force_spawn(mob_pos, name)

                if group then

                    local attempts = 0

                    while attempts < group do
                        local mobdef = minetest.registered_entities[name]
                        local side = mobdef.collisionbox[4]
                        local group_pos =
                            vector.new(mob_pos.x +
                                           (random(-group, group) * side),
                                       mob_pos.y, mob_pos.z +
                                           (random(-group, group) * side))
                        local spawn_pos =
                            minetest.find_nodes_in_area_under_air(
                                vector.new(group_pos.x, group_pos.y - 8,
                                           group_pos.z),
                                vector.new(group_pos.x, group_pos.y + 8,
                                           group_pos.z), mob_core.walkable_nodes)
                        if spawn_pos[1] then
                            mob_core.force_spawn(
                                vector.new(spawn_pos[1].x, spawn_pos[1].y +
                                               math.abs(
                                                   mobdef.collisionbox[2]),
                                           spawn_pos[1].z), name)
                        end
                        attempts = attempts + 1
                    end
                end
            end
        end
    end
end

mob_core.registered_on_spawns = {}

mob_core.registered_spawns = {}

function mob_core.register_spawn(def, interval, chance)
    local spawn_timer = 0
    mob_core.registered_spawns[def.name] = {func = nil, last_pos = {}, def = def}
    mob_core.registered_spawns[def.name].func =
        minetest.register_globalstep(function(dtime)
            spawn_timer = spawn_timer + dtime
            if spawn_timer > interval then
                if random(1, chance) == 1 then
                    local spawned, last_pos, mobs =
                        mob_core.spawn(def.name, def.nodes or
                                           {"group:soil", "group:stone"},
                                       def.min_light or 0, def.max_light or 15,
                                       def.min_height or -31000,
                                       def.max_height or 31000,
                                       def.min_rad or 24, def.max_rad or 256,
                                       def.group or 1, def.optional or nil)
                end
                spawn_timer = 0
            end
        end)
end

function mob_core.register_on_spawn(name, func, ...)
    mob_core.registered_on_spawns[name] = {args = {...}, func = func}
end

-------------
-- On Step --
-------------

-- Push on entity collision --

function mob_core.collision_detection(self)
    if not mobkit.is_alive(self) then return end
    local pos = self.object:get_pos()
    local hitbox = mob_core.get_hitbox(self)
    local width = -hitbox[1] + hitbox[4] + 0.5
    local objects = minetest.get_objects_inside_radius(pos, width)
    if #objects < 2 then return end
    local is_in_bed = function(object)
        if not minetest.get_modpath("beds") then return false end
        if not beds.player
        or not object:is_player()
        or (object:is_player()
        and not beds.player[object:get_player_name()]) then
            return false
        end
        return true
    end
    local col_no = 0
    for i = 1, #objects do
        local object = objects[i]
        if (object and object ~= self.object) and
            (not object:get_attach() or object:get_attach() ~= self.object) and
            (not self.object:get_attach() or self.object:get_attach() ~= object) and
            (((object:get_luaentity() and object:get_luaentity().logic)) or
                (object:is_player() and not is_in_bed(object))) then
            col_no = col_no + 1
            if col_no >= 5 then break end
            local pos2 = object:get_pos()
            local dir = vec_dir(pos, pos2)
            dir.y = 0
            if dir.x == 0 and dir.z == 0 then
                dir = vector.new(random(-1, 1) * random(), 0,
                                 random(-1, 1) * random())
            end
            local velocity = vector.multiply(dir, 1.1)
            local vel1 = vector.multiply(velocity, -1)
            local vel2 = velocity
            self.object:add_velocity(vel1)
            object:add_velocity(vel2)
        end
    end
end

-- 4 Stage Growth --

function mob_core.growth(self, interval)
    if not mobkit.is_alive(self) then return end
    if self.growth_stage == 4 then return end
    if not self.base_hp then
        self.base_hp = mobkit.remember(self, "base_hp", self.max_hp)
    end
    local pos = self.object:get_pos()
    local reach = minetest.registered_entities[self.name].reach
    local speed = minetest.registered_entities[self.name].max_speed
    interval = interval or 400
    if not self.scale_stage1 then
        self.scale_stage1 = 0.25
        self.scale_stage2 = 0.5
        self.scale_stage3 = 0.75
    end
    if self.growth_stage < 4 then self.growth_timer = self.growth_timer + 1 end
    if self.growth_timer > interval then
        self.growth_timer = 1
        self.max_speed = speed / 4
        if reach then self.reach = reach / 4 end
        if self.growth_stage == 1 then
            self.growth_stage = mobkit.remember(self, "growth_stage", 2)
            self.object:set_pos({
                x = pos.x,
                y = pos.y + math.abs(self.collisionbox[2]),
                z = pos.z
            })
            mob_core.set_scale(self, self.scale_stage2)
            self.max_speed = speed / 2
            if reach then self.reach = reach / 2 end
        elseif self.growth_stage == 2 then
            self.growth_stage = mobkit.remember(self, "growth_stage", 3)
            self.object:set_pos({
                x = pos.x,
                y = pos.y + math.abs(self.collisionbox[2]),
                z = pos.z
            })
            mob_core.set_scale(self, self.scale_stage3)
            self.child = mobkit.remember(self, "child", false)
            mob_core.set_textures(self)
            self.max_speed = speed / 1.5
            if reach then self.reach = reach / 1.5 end
        elseif self.growth_stage == 3 then
            self.growth_stage = mobkit.remember(self, "growth_stage", 4)
            self.object:set_pos({
                x = pos.x,
                y = pos.y + math.abs(self.collisionbox[2]),
                z = pos.z
            })
            mob_core.set_scale(self, 1)
            self.max_speed = speed
            if reach then self.reach = reach end
        end
    end
    if self.growth_stage == 1 and self.hp > self.max_hp / 4 then
        self.hp = self.max_hp / 4
    end
    if self.growth_stage == 2 and self.hp > self.max_hp / 2 then
        self.hp = self.max_hp / 2
    end
    if self.growth_stage == 3 and self.hp > self.max_hp / 1.5 then
        self.hp = self.max_hp / 1.5
    end
    self.growth_timer = mobkit.remember(self, "growth_timer", self.growth_timer)
end

-- Step Function --

function mob_core.on_step(self, dtime, moveresult)
    mobkit.stepfunc(self, dtime, moveresult)
    if self.owner_target
    and not mobkit.exists(self.owner_target) then
        self.owner_target = nil
    end
    if self.push_on_collide then
        mob_core.collision_detection(self)
    end
end

--------------------------
-- Rightclick Functions --
--------------------------

-- Mount --

function mob_core.mount(self, clicker)
    if not self.driver and self.child == false then
        mobkit.clear_queue_high(self)
        self.status = mobkit.remember(self, "status", "ridden")
        mob_core.attach(self, clicker)
        return false
    else
        return true
    end
end

-- Capture Mob --

function mob_core.capture_mob(self, clicker, capture_tool, capture_chance, wear, force_take)
    if not clicker:is_player() or not clicker:get_inventory() then
        return false
    end
    local mobname = self.name
    local catcher = clicker:get_player_name()
    local tool = clicker:get_wielded_item()
    if tool:get_name() ~= capture_tool then return false end
    if self.tamed == false then
        minetest.chat_send_player(catcher, "Mob is not tamed.")
        return false
    end
    if self.owner ~= catcher and force_take == false then
        minetest.chat_send_player(catcher, "Mob is owned by @1" .. self.owner)
        return false
    end
    if clicker:get_inventory():room_for_item("main", mobname) then
        local chance = 0
        if tool:get_name() == capture_tool then
            if capture_tool == "" then
                chance = capture_chance
            else
                chance = capture_chance
                tool:add_wear(wear)
                clicker:set_wielded_item(tool)
            end
        end
        if chance and chance > 0 and random(1, 100) <= chance then
            local new_stack = ItemStack(mobname .. "_set")
            new_stack:get_meta():set_string("staticdata", self:get_staticdata())
            local inv = clicker:get_inventory()
            if inv:room_for_item("main", new_stack) then
                inv:add_item("main", new_stack)
            else
                minetest.add_item(clicker:get_pos(), new_stack)
            end
            self.object:remove()
            return new_stack
        elseif chance and chance ~= 0 then
            return false
        elseif not chance then
            return false
        end
    end

    return true
end

-- Feed/Tame/Breed --

function mob_core.feed_tame(self, clicker, feed_count, tame, breed)
    local item = clicker:get_wielded_item()
    local pos = self.object:get_pos()
    local mob_name = mob_core.get_name_proper(self.name)
    if mob_core.follow_holding(self, clicker) then
        if creative == false then
            item:take_item()
            clicker:set_wielded_item(item)
        end
        mobkit.heal(self, self.max_hp / feed_count)
        if self.hp >= self.max_hp then self.hp = self.max_hp end
        self.food = mobkit.remember(self, "food", self.food + 1)
        if self.food >= feed_count then
            self.food = mobkit.remember(self, "food", 0)
            if tame and not self.tamed then
                mob_core.set_owner(self, clicker:get_player_name())
                minetest.chat_send_player(clicker:get_player_name(),
                                          mob_name .. " has been tamed!")
                mobkit.clear_queue_high(self)
                minetest.add_particlespawner(
                    {
                        amount = 16,
                        time = 0.25,
                        minpos = {
                            x = pos.x - self.collisionbox[4],
                            y = pos.y - self.collisionbox[4],
                            z = pos.z - self.collisionbox[4]
                        },
                        maxpos = {
                            x = pos.x + self.collisionbox[4],
                            y = pos.y + self.collisionbox[4],
                            z = pos.z + self.collisionbox[4]
                        },
                        minacc = {x = 0, y = 0.25, z = 0},
                        maxacc = {x = 0, y = -0.25, z = 0},
                        minexptime = 0.75,
                        maxexptime = 1,
                        minsize = 4,
                        maxsize = 4,
                        texture = "mob_core_green_particle.png",
                        glow = 16
                    })
            end
            if breed then
                if self.child then return false end
                if self.breed_mode then return false end
                if self.breed_timer == 0 and self.breed_mode == false then
                    self.breed_mode = true
                    minetest.add_particlespawner(
                        {
                            amount = 16,
                            time = 0.25,
                            minpos = {
                                x = pos.x - self.collisionbox[4],
                                y = pos.y - self.collisionbox[4],
                                z = pos.z - self.collisionbox[4]
                            },
                            maxpos = {
                                x = pos.x + self.collisionbox[4],
                                y = pos.y + self.collisionbox[4],
                                z = pos.z + self.collisionbox[4]
                            },
                            minacc = {x = 0, y = 0.25, z = 0},
                            maxacc = {x = 0, y = -0.25, z = 0},
                            minexptime = 0.75,
                            maxexptime = 1,
                            minsize = 4,
                            maxsize = 4,
                            texture = "heart.png",
                            glow = 16
                        })
                end
            end
        end
    end
    return false
end

-- Protection --

function mob_core.protect(self, clicker, force_protect)
    local name = clicker:get_player_name()
    local item = clicker:get_wielded_item()
    local mob_name = mob_core.get_name_proper(self.name)
    if item:get_name() ~= "mob_core:protection_gem" then return false end
    if self.tamed == false and not force_protect then
        minetest.chat_send_player(name, mob_name .. " is not tamed")
        return true
    end
    if self.protected == true then
        minetest.chat_send_player(name, mob_name .. " is already protected")
        return true
    end
    if not creative then
        item:take_item()
        clicker:set_wielded_item(item)
    end
    self.protected = true
    mobkit.remember(self, "protected", self.protected)
    self.timeout = nil
    local pos = self.object:get_pos()
    pos.y = pos.y + self.collisionbox[2] + 1 / 1
    minetest.add_particlespawner({
        amount = 16,
        time = 0.25,
        minpos = {
            x = pos.x - self.collisionbox[4],
            y = pos.y - self.collisionbox[4],
            z = pos.z - self.collisionbox[4]
        },
        maxpos = {
            x = pos.x + self.collisionbox[4],
            y = pos.y + self.collisionbox[4],
            z = pos.z + self.collisionbox[4]
        },
        minacc = {x = 0, y = 0.25, z = 0},
        maxacc = {x = 0, y = -0.25, z = 0},
        minexptime = 0.75,
        maxexptime = 1,
        minsize = 4,
        maxsize = 4,
        texture = "mob_core_green_particle.png",
        glow = 16
    })
    return true
end

-- Nameing --

local nametag_obj = {}
local nametag_item = {}

function mob_core.nametag(self, clicker, force_name)
    if not force_name and clicker:get_player_name() ~= self.owner then return end
    local item = clicker:get_wielded_item()
    if item:get_name() == "mob_core:nametag" then

        local name = clicker:get_player_name()

        nametag_obj[name] = self
        nametag_item[name] = item

        local tag = self.nametag or ""

        minetest.show_formspec(name, "mob_core_nametag",
                               "size[8,4]" .. "field[0.5,1;7.5,0;name;" ..
                                   minetest.formspec_escape("Enter name:") ..
                                   ";" .. tag .. "]" ..
                                   "button_exit[2.5,3.5;3,1;mob_rename;" ..
                                   minetest.formspec_escape("Rename") .. "]")
    end
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
    if formname == "mob_core_nametag" and fields.name then

        local name = player:get_player_name()

        if not nametag_obj[name] or not nametag_obj[name].object then
            return
        end

        local item = player:get_wielded_item()

        if item:get_name() ~= "mob_core:nametag" then return end

        if string.len(fields.name) > 64 then
            fields.name = string.sub(fields.name, 1, 64)
        end

        nametag_obj[name].nametag = mobkit.remember(nametag_obj[name],
                                                    "nametag", fields.name)

        mob_core.activate_nametag(nametag_obj[name])

        if fields.name ~= "" and not creative then
            nametag_item[name]:take_item()
            player:set_wielded_item(nametag_item[name])
        end

        nametag_obj[name] = nil
        nametag_item[name] = nil
    end
end)

-----------------
-- Pathfinding --
-----------------

-- Lightweight Pathfinder

local function can_fit(pos, width, single_plane)
    local pos1 = vector.new(pos.x - width, pos.y, pos.z - width)
    local pos2 = vector.new(pos.x + width, pos.y, pos.z + width)
    for x = pos1.x, pos2.x do
        for y = pos1.y, pos2.y do
            for z = pos1.z, pos2.z do
                local p2 = vector.new(x, y, z)
                local node = minetest.get_node(p2)
                if is_node_walkable(node.name) then
                    local p3 = vector.new(p2.x, p2.y + 1, p2.z)
                    local node2 = minetest.get_node(p3)
                    if minetest.registered_nodes[node2.name].walkable then
                        return false
                    end
                    if single_plane then return false end
                end
            end
        end
    end
    return true
end

local function move_from_wall(pos, width)
    local pos1 = vector.new(pos.x - width, pos.y, pos.z - width)
    local pos2 = vector.new(pos.x + width, pos.y, pos.z + width)
    for x = pos1.x, pos2.x do
        for y = pos1.y, pos2.y do
            for z = pos1.z, pos2.z do
                local p2 = vector.new(x, y, z)
                if can_fit(p2, width) and vec_dist(pos, p2) < width then
                    return p2
                end
            end
        end
    end
    return pos
end

function mob_core.find_path_lite(pos, tpos, width)

    local raw

    if not minetest.registered_nodes[minetest.get_node(
        vector.new(pos.x, pos.y - 1, pos.z)).name].walkable then
        local min = vector.subtract(pos, width + 1)
        local max = vector.add(pos, width + 1)

        local index_table = minetest.find_nodes_in_area_under_air(min, max,
                                                                  mob_core.walkable_nodes)
        for _, i_pos in pairs(index_table) do
            if minetest.registered_nodes[minetest.get_node(i_pos).name].walkable then
                pos = vector.new(i_pos.x, i_pos.y + 1, i_pos.z)
                break
            end
        end
    end

    if not minetest.registered_nodes[minetest.get_node(
        vector.new(tpos.x, tpos.y - 1, tpos.z)).name].walkable then
        local min = vector.subtract(tpos, width)
        local max = vector.add(tpos, width)

        local index_table = minetest.find_nodes_in_area_under_air(min, max,
                                                                  mob_core.walkable_nodes)
        for _, i_pos in pairs(index_table) do
            if minetest.registered_nodes[minetest.get_node(i_pos).name].walkable then
                tpos = vector.new(i_pos.x, i_pos.y + 1, i_pos.z)
                break
            end
        end
    end

    local path = minetest.find_path(pos, tpos, 32, 2, 2, "A*_noprefetch")

    if not path then return end

    table.remove(path, 1)

    for i = #path, 1, -1 do
        if not path then return end
        if vec_dist(pos, path[i]) <= width + 1 then
            for _i = 3, #path do path[_i - 1] = path[_i] end
        end

        if not can_fit(path[i], width + 1) then
            local clear = move_from_wall(path[i], width + 1)
            if clear and can_fit(clear, width) then path[i] = clear end
        end

        if minetest.get_node(path[i]).name == "default:snow" then
            path[i] = vector.new(path[i].x, path[i].y + 1, path[i].z)
        end

        raw = path
        if #path > 3 then

            if vec_dist(pos, path[i]) < width then
                table.remove(path, i)
            end

            local pos1 = path[i - 2]
            local pos2 = path[i]
            -- Handle Diagonals
            if pos1 and pos2 and pos1.x ~= pos2.x and pos1.z ~= pos2.z then
                if minetest.line_of_sight(pos1, pos2) then
                    if can_fit(pos, width) then
                        table.remove(path, i - 1)
                    end
                end
            end
            -- Reduce Straight Lines
            if pos1 and pos2 and pos1.x == pos2.x and pos1.z ~= pos2.z and
                pos1.y == pos2.y then
                if minetest.line_of_sight(pos1, pos2) then
                    if can_fit(pos, width) then
                        table.remove(path, i - 1)
                    end
                end
            elseif pos1 and pos2 and pos1.x ~= pos2.x and pos1.z == pos2.z and
                pos1.y == pos2.y then
                if minetest.line_of_sight(pos1, pos2) then
                    if can_fit(pos, width) then
                        table.remove(path, i - 1)
                    end
                end
            end
        end
    end

    return path, raw
end

-- A* Pathfinder with object scale and 3d movement support --

local moveable = mob_core.is_moveable

local function get_ground_level(pos2, max_height)
    local node = minetest.get_node(pos2)
    local node_under = minetest.get_node({
        x = pos2.x,
        y = pos2.y - 1,
        z = pos2.z
    })
    local height = 0
    local walkable = is_node_walkable(node_under.name) and not is_node_walkable(node.name)
    if walkable then
        return pos2
    elseif not walkable then
        if not is_node_walkable(node_under.name) then
            while not is_node_walkable(node_under.name)
            and height < max_height do
                pos2.y = pos2.y - 1
                node_under = minetest.get_node({
                    x = pos2.x,
                    y = pos2.y - 1,
                    z = pos2.z
                })
                height = height + 1
            end
        else
            while is_node_walkable(node.name)
            and height < max_height do
                pos2.y = pos2.y + 1
                node = minetest.get_node(pos2)
                height = height + 1
            end
        end
        return pos2
    end
end

-- Get Distance

local function get_distance(start_pos, end_pos)
    local distX = abs(start_pos.x - end_pos.x)
    local distZ = abs(start_pos.z - end_pos.z)

    if distX > distZ then
        return 14 * distZ + 10 * (distX - distZ)
    else
        return 14 * distX + 10 * (distZ - distX)
    end
end

local function get_distance_to_neighbor(start_pos, end_pos)
    local distX = abs(start_pos.x - end_pos.x)
    local distY = abs(start_pos.y - end_pos.y)
    local distZ = abs(start_pos.z - end_pos.z)

    if distX > distZ then
        return (14 * distZ + 10 * (distX - distZ)) * (distY + 1)
    else
        return (14 * distX + 10 * (distZ - distX)) * (distY + 1)
    end
end

-- Check if pos is above ground

local function is_on_ground(pos)
    local ground = {
        x = pos.x,
        y = pos.y - 1,
        z = pos.z
    }
    if is_node_walkable(minetest.get_node(ground).name) then
        return true
    end
    return false
end

-- Find a path from start to goal

function mob_core.find_path(start, goal, obj_width, obj_height, max_open, climb, fly, swim)
    climb = climb or false
    fly = fly or false
    swim = swim or false

    local path_neighbors = {
        {x = 1, y = 0, z = 0},
        {x = 1, y = 0, z = 1},
        {x = 0, y = 0, z = 1},
        {x = -1, y = 0, z = 1},
        {x = -1, y = 0, z = 0},
        {x = -1, y = 0, z = -1},
        {x = 0, y = 0, z = -1},
        {x = 1, y = 0, z = -1}
    }

    if climb then
        table.insert(path_neighbors, {x = 0, y = 1, z = 0})
    end

    if fly
    or swim then
        path_neighbors = {
            -- Central
            {x = 1, y = 0, z = 0},
            {x = 0, y = 0, z = 1},
            {x = -1, y = 0, z = 0},
            {x = 0, y = 0, z = -1},
            -- Up
            {x = 1, y = 1, z = 0},
            {x = 0, y = 1, z = 1},
            {x = -1, y = 1, z = 0},
            {x = 0, y = 1, z = -1},
            -- Down
            {x = 1, y = 1, z = 0},
            {x = 0, y = 1, z = 1},
            {x = -1, y = 1, z = 0},
            {x = 0, y = 1, z = -1},
            -- Directly Up or Down
            {x = 0, y = 1, z = 0},
            {x = 0, y = -1, z = 0}
        }
    end

    local function get_neighbors(pos, width, height, tbl, open, closed)
        local result = {}
        for i = 1, #tbl do
            local neighbor = vector.add(pos, tbl[i])
            if neighbor.y == pos.y
            and not fly
            and not swim then
                neighbor = get_ground_level(neighbor, 1)
            end
            local line_of_sight = minetest.line_of_sight({x = pos.x, y = neighbor.y, z = pos.z}, neighbor)
            if swim then
                line_of_sight = true
            end
            if (parent_pos
            and dist_2d(pos, neighbor) == dist_2d(parent_pos, neighbor))
            or open[minetest.hash_node_position(neighbor)]
            or closed[minetest.hash_node_position(neighbor)] then
                line_of_sight = false
            end
            if line_of_sight
            and moveable(neighbor, width, height)
            and ((is_on_ground(neighbor)
            or (fly or swim))
            or (neighbor.x == pos.x
            and neighbor.z == pos.z
            and climb))
            and (not swim
            or is_node_liquid(minetest.get_node(neighbor).name)) then
                table.insert(result, neighbor)
            end
        end
        return result
    end

    local function find_path(start, goal)

        start = {
            x = floor(start.x + 0.5),
            y = floor(start.y + 0.5),
            z = floor(start.z + 0.5)
        }
    
        goal = {
            x = floor(goal.x + 0.5),
            y = floor(goal.y + 0.5),
            z = floor(goal.z + 0.5)
        }

        if goal.x == start.x
        and goal.z == start.z then -- No path can be found
            return nil
        end
    
        local openSet = {}
    
        local closedSet = {}
    
        local start_index = minetest.hash_node_position(start)
    
        openSet[start_index] = {
            pos = start,
            parent = nil,
            gScore = 0,
            fScore = get_distance(start, goal)
        }
    
        local count = 1
    
        while count > 0 do
            -- Initialize ID and data
            local current_id
            local current
    
            -- Get an initial id in open set
            for i, v in pairs(openSet) do
                current_id = i
                current = v
                break
            end
    
            -- Find lowest f cost
            for i, v in pairs(openSet) do
                if v.fScore < current.fScore then
                    current_id = i
                    current = v
                end
            end
    
            -- Add lowest fScore to closedSet and remove from openSet
            openSet[current_id] = nil
            closedSet[current_id] = current
    
            -- Reconstruct path if end is reached
            if (is_on_ground(goal)
            and current_id == minetest.hash_node_position(goal))
            or (not is_on_ground(goal)
            and goal.x == current.pos.x
            and goal.z == current.pos.z) then
                local path = {}
                local fail_safe = 0
                for k, v in pairs(closedSet) do
                    fail_safe = fail_safe + 1
                end
                repeat
                    if not closedSet[current_id] then return end
                    table.insert(path, closedSet[current_id].pos)
                    current_id = closedSet[current_id].parent
                until current_id == start_index or #path >= fail_safe
                table.insert(path, closedSet[current_id].pos)
                local reverse_path = {}
                repeat table.insert(reverse_path, table.remove(path)) until #path == 0
                return reverse_path
            end
    
            count = count - 1
    
            local adjacent = get_neighbors(current.pos, obj_width, obj_height, path_neighbors, openSet, closedSet)
    
            -- Go through neighboring nodes
            for i = 1, #adjacent do
                local neighbor = {
                    pos = adjacent[i],
                    parent = current_id,
                    gScore = 0,
                    fScore = 0
                }
                temp_gScore = current.gScore + get_distance_to_neighbor(current.pos, neighbor.pos)
                local new_gScore = 0
                if openSet[minetest.hash_node_position(neighbor.pos)] then
                    new_gScore = openSet[minetest.hash_node_position(neighbor.pos)].gScore
                end
                if (temp_gScore < new_gScore
                or not openSet[minetest.hash_node_position(neighbor.pos)])
                and not closedSet[minetest.hash_node_position(neighbor.pos)] then
                    if not openSet[minetest.hash_node_position(neighbor.pos)] then
                        count = count + 1
                    end
                    local hCost = get_distance_to_neighbor(neighbor.pos, goal)
                    neighbor.gScore = temp_gScore
                    neighbor.fScore = temp_gScore + hCost
                    openSet[minetest.hash_node_position(neighbor.pos)] = neighbor
                end
            end
            if count > (max_open or 100) then return end
        end
        return nil
    end
    return find_path(start, goal)
end

---------------------------
-- Overwritten Functions --
---------------------------

local old_turn2yaw = mobkit.turn2yaw

function mobkit.turn2yaw(self, tyaw, rate)
    old_turn2yaw(self, tyaw, rate)
    self._tyaw = tyaw
end

-- Force Tame Command --

minetest.register_chatcommand("force_tame", {
    params = "",
    description = "tame pointed mobkit mob",
    privs = {server = true, creative = true},
    func = function(name)
        local player = minetest.get_player_by_name(name)
        if not player then return false end
        local dir = player:get_look_dir()
        local pos = player:get_pos()
        pos.y = pos.y + player:get_properties().eye_height or 1.625
        local dest = vector.add(pos, vector.multiply(dir, 40))
        local ray = minetest.raycast(pos, dest, true, false)
        for pointed_thing in ray do
            if pointed_thing.type == "object" then
                local pointedobject = pointed_thing.ref
                if pointedobject:get_luaentity() then
                    pointedobject = pointedobject:get_luaentity()
                    local mob_name =
                        mob_core.get_name_proper(pointedobject.name)
                    if not pointedobject.tamed then
                        if not pointedobject.logic or pointedobject.brainfunc then
                            minetest.chat_send_player(name,
                                                      "This command only works on mobkit mobs")
                            return
                        end
                        mob_core.set_owner(pointedobject, name)
                        minetest.chat_send_player(name, mob_name ..
                                                      " has been tamed!")
                        mobkit.clear_queue_high(pointedobject)
                        pos = pointedobject.object:get_pos()
                        minetest.add_particlespawner(
                            {
                                amount = 16,
                                time = 0.25,
                                minpos = {
                                    x = pos.x - pointedobject.collisionbox[4],
                                    y = pos.y - pointedobject.collisionbox[4],
                                    z = pos.z - pointedobject.collisionbox[4]
                                },
                                maxpos = {
                                    x = pos.x + pointedobject.collisionbox[4],
                                    y = pos.y + pointedobject.collisionbox[4],
                                    z = pos.z + pointedobject.collisionbox[4]
                                },
                                minacc = {x = 0, y = 0.25, z = 0},
                                maxacc = {x = 0, y = -0.25, z = 0},
                                minexptime = 0.75,
                                maxexptime = 1,
                                minsize = 4,
                                maxsize = 4,
                                texture = "mob_core_green_particle.png",
                                glow = 16
                            })
                        return
                    else
                        if not pointedobject.logic or pointedobject.brainfunc then
                            minetest.chat_send_player(name,
                                                      "This command only works on mobkit mobs")
                            return
                        end
                        mob_core.set_owner(pointedobject, name)
                        minetest.chat_send_player(name, mob_name ..
                                                      " has been tamed!")
                        mobkit.clear_queue_high(pointedobject)
                        pos = pointedobject.object:get_pos()
                        minetest.add_particlespawner(
                            {
                                amount = 16,
                                time = 0.25,
                                minpos = {
                                    x = pos.x - pointedobject.collisionbox[4],
                                    y = pos.y - pointedobject.collisionbox[4],
                                    z = pos.z - pointedobject.collisionbox[4]
                                },
                                maxpos = {
                                    x = pos.x + pointedobject.collisionbox[4],
                                    y = pos.y + pointedobject.collisionbox[4],
                                    z = pos.z + pointedobject.collisionbox[4]
                                },
                                minacc = {x = 0, y = 0.25, z = 0},
                                maxacc = {x = 0, y = -0.25, z = 0},
                                minexptime = 0.75,
                                maxexptime = 1,
                                minsize = 4,
                                maxsize = 4,
                                texture = "mob_core_green_particle.png",
                                glow = 16
                            })
                        return
                    end
                end
            else
                minetest.chat_send_player(name, "You must be pointing at a mob.")
                return
            end
        end
    end
})