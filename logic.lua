--------------------
-- Mob Core Logic --
--------------------
------ Ver 0.1 -----

-- Defend Owner --

minetest.register_on_mods_loaded(function()
    for name, def in pairs(minetest.registered_entities) do
        if minetest.registered_entities[name].get_staticdata == mobkit.statfunc then
            local old_punch = def.on_punch
            if not old_punch then
                old_punch = function() end
            end
            local on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir)
                old_punch(self, puncher, time_from_last_punch, tool_capabilities, dir)
                local pos = self.object:get_pos()
                if not pos then
                    return
                end
                local objects = minetest.get_objects_inside_radius(pos, 32)
                for _, object in ipairs(objects) do
                    if object:get_luaentity()
                    and mob_core.is_mobkit_mob(object) then
                        local entity = object:get_luaentity()
                        if object ~= self.object
                        and entity.defend_owner
                        and entity.owner
                        and entity.owner == puncher:get_player_name() then
                            entity.owner_target = self.object
                        end
                    end
                end
            end
            def.on_punch = on_punch
            minetest.register_entity(":"..name, def)
        end
	end
end)

-------------
-- Runaway --
-------------

function mob_core.logic_runaway_player(self, prty) -- Runaway from player
    local player = mobkit.get_nearby_player(self)
    if player and vector.distance(self.object:get_pos(), player:get_pos()) < self.view_range then
        if player:get_player_name() ~= self.owner then
            mobkit.hq_runfrom(self,prty,player)
            return
        end
    end
end

function mob_core.logic_runaway_mob(self, prty, tbl) -- Runaway from specified mobs
    tbl = tbl or self.runaway_from
    if tbl then
        for i = 1, #tbl do
            local runaway_mob = mobkit.get_closest_entity(self, tbl[i])
            if runaway_mob and vector.distance(self.object:get_pos(), runaway_mob:get_pos()) < self.view_range then
                mobkit.hq_runfrom(self, prty, runaway_mob)
                return
            end
        end
    end
end

------------
-- Attack --
------------

function mob_core.logic_attack_player(self, prty, player) -- Attack player
    player = player or mobkit.get_nearby_player(self)
    if player
    and vector.distance(self.object:get_pos(), player:get_pos()) < self.view_range
    and mobkit.is_alive(player) then
        mob_core.hq_hunt(self,prty,player)
        return
    end
    return
end

function mob_core.logic_attack_mob(self, prty, target) -- Attack specified mobs
	if not mobkit.exists(target) then return true end
	if target
	and vector.distance(self.object:get_pos(), target:get_pos()) < self.view_range
	and mobkit.is_alive(target) then
		if not mob_core.shared_owner(self, target) then
			mob_core.hq_hunt(self, prty, target)
			return
		end
	end
end

function mob_core.logic_attack_mobs(self, prty, tbl) -- Attack specified mobs
    tbl = tbl or self.targets
    if tbl then
        for i = 1, #tbl do
            local target = mobkit.get_closest_entity(self, tbl[i])
            if target
            and vector.distance(self.object:get_pos(), target:get_pos()) < self.view_range
            and mobkit.is_alive(target) then
                if (self.tamed == true and target:get_luaentity().owner ~= self.owner)
                or not self.tamed then
                    mob_core.hq_hunt(self,prty,target)
                    return
                end
            end
        end
    end
end

function mob_core.logic_aqua_attack_player(self, prty, player) -- Attack player
    player = player or mobkit.get_nearby_player(self)
    if player
    and vector.distance(self.object:get_pos(), player:get_pos()) < self.view_range
    and mobkit.is_alive(player)
    and mobkit.is_in_deep(player) then
        mob_core.hq_aqua_attack(self,prty,player,self.max_speed)
        return
    end
end

function mob_core.logic_aqua_attack_mob(self, prty, target) -- Attack specified mobs
	if not mobkit.exists(target) then return true end
	if target
	and vector.distance(self.object:get_pos(), target:get_pos()) < self.view_range
	and mobkit.is_alive(target) then
		if not mob_core.shared_owner(self, target) then
			mob_core.hq_aqua_attack(self, prty, target, 1)
			return
		end
	end
end

function mob_core.logic_aqua_attack_mobs(self, prty, tbl) -- Attack specified mobs
    tbl = tbl or self.targets
    if tbl then
        for i = 1, #tbl do
            local target = mobkit.get_closest_entity(self, tbl[i])
            if target
            and vector.distance(self.object:get_pos(), target:get_pos()) < self.view_range
            and mobkit.is_alive(target)
            and mobkit.is_in_deep(target) then
                if (self.tamed == true and target:get_luaentity().owner ~= self.owner)
                or not self.tamed then
                    mob_core.hq_aqua_attack(self,prty,target,self.max_speed)
                    return
                end
            end
        end
    end
end

--------------
-- Run From --
--------------

function mob_core.logic_aerial_takeoff_flee_mobs(self, prty, lift_force) -- Attack specified mobs
    if self.runaway_from then
        for i = 1, #self.runaway_from do
            local runfrom = mobkit.get_closest_entity(self, self.runaway_from[i])
            if runfrom and runfrom.owner ~= self.owner then
                return
            end
            if runfrom and vector.distance(self.object:get_pos(), runfrom:get_pos()) < 8 then
                mob_core.hq_takeoff(self, prty, lift_force)
                return
            end
        end
    end
end

function mob_core.logic_aerial_takeoff_flee_player(self, prty, lift_force) -- Attack specified mobs
    local player = mobkit.get_nearby_player(self)
    if player and vector.distance(self.object:get_pos(), player:get_pos()) < 8 then
        mob_core.hq_takeoff(self, prty, lift_force)
        return
    end
end

------------------------
-- Randomly drop item --
------------------------

function mob_core.random_drop(self, interval, chance, item)
    self.drop_timer = (self.drop_timer or 0) + 1
    if self.drop_timer >= interval then
        self.droptimer = 0
        if math.random(1, chance) == 1 then
            local pos = self.object:get_pos()
            minetest.add_item(pos, item)
            minetest.sound_play("default_place_node_hard", {
                pos = pos,
                gain = 1.0,
                max_hear_distance = 5,
            })
        end
    end
end