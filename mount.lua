------------------------
-- Mob Core Mount API --
------------------------
-------- Ver 1.0 -------

local player_attached = {}
local animate_player = {}

if minetest.get_modpath("default") then
	player_attached = default.player_attached
	animate_player = default.player_set_animation
elseif minetest.get_modpath("mcl_player") then
	player_attached = mcl_player.player_attached
	animate_player = mcl_player.player_set_animation
end

----------------------
-- Helper functions --
----------------------

local function detach(name)
	local player = minetest.get_player_by_name(name)
	if not player then
		return
	end
	local attached_to = player:get_attach()
	if not attached_to then
		return
	end
	local entity = attached_to:get_luaentity()
	if entity.driver and entity.driver == player then
		entity.driver = nil
    end
    mobkit.clear_queue_high(entity)
    entity.status = mobkit.remember(entity,"status","")
	player:set_detach()
	if player_attached ~= nil then
		player_attached[player:get_player_name()] = false
	end
	player:set_eye_offset({x = 0, y = 0, z = 0}, {x = 0, y = 0, z = 0})
	animate_player(player, "stand" , 30)
	player:set_properties({visual_size = {x = 1, y = 1}, pointable = true })
end

function mob_core.force_detach(player)
	minetest.after(0, detach, player:get_player_name())
end

local function reverse_animation(self,anim,output_name)
	if self.animation and self.animation[anim] then
		local frame_x = self.animation[anim].range.x
		local frame_y = self.animation[anim].range.y
		local loop = self.animation[anim].loop
		local speed = self.animation[anim].speed
		self.animation[output_name] = {range={x=frame_x,y=frame_y},speed=-speed,loop=loop}
	end
end

minetest.register_on_leaveplayer(function(player)
	mob_core.force_detach(player)
end)

minetest.register_on_shutdown(function()
	local players = minetest.get_connected_players()
	for i = 1, #players do
		mob_core.force_detach(players[i])
	end
end)

minetest.register_on_dieplayer(function(player)
	mob_core.force_detach(player)
	return true
end)

function mob_core.attach(entity, player)
	entity.player_rotation = entity.player_rotation or {x = 0, y = 0, z = 0}
	entity.driver_attach_at = entity.driver_attach_at or {x = 0, y = 0, z = 0}
	entity.driver_eye_offset = entity.driver_eye_offset or {{x = 0, y = 0, z = 0},{x = 0, y = 0, z = 0}}
	entity.driver_scale = entity.driver_scale or {x = 1, y = 1}
	local rot_view = 0
	if entity.player_rotation.y == 90 then
		rot_view = math.pi/2
	end
	local attach_at = entity.driver_attach_at
    local eye_offset = entity.driver_eye_offset[1] or {x = 0, y = 0, z = 0}
    local eye_offset_3p = entity.driver_eye_offset[2] or {x = 0, y = 0, z = 0}
	entity.driver = player
	player:set_attach(entity.object, "", attach_at, entity.player_rotation)
	if player_attached ~= nil then
		player_attached[player:get_player_name()] = true
	end
	player:set_eye_offset(eye_offset,eye_offset_3p)
	player:set_properties({
		visual_size = {
			x = entity.driver_scale.x,
			y = entity.driver_scale.y
		},
		pointable = false
	})
	minetest.after(0.2, function()
		animate_player(player, "sit" , 30)
	end)
	player:set_look_horizontal(entity.object:get_yaw() - rot_view)
end

function mob_core.detach(player, offset)
	mob_core.force_detach(player)
	animate_player(player, "stand" , 30)
	local pos = player:get_pos()
	pos = {x = pos.x + offset.x, y = pos.y + 0.2 + offset.y, z = pos.z + offset.z}
	minetest.after(0.1, function()
		player:set_pos(pos)
	end)
end

local function go_forward(self,tvel)
    local y = self.object:get_velocity().y
    local yaw = self.object:get_yaw()
    local vel = vector.multiply(minetest.yaw_to_dir(yaw),tvel)
    vel.y = y
    self.object:set_velocity(vel)
end

function mob_core.hq_mount_logic(self,prty)
    local tvel = 0
    local func = function(self)
        if not self.driver then return true end
		local vel = self.object:get_velocity()
		local ctrl = self.driver:get_player_control()
		if ctrl.up then
			tvel = self.max_speed_forward
		elseif ctrl.down and self.isonground then -- move backwards
			if self.max_speed_reverse == 0 and vel == 0 then
				return
			end
			tvel = -self.max_speed_reverse
			reverse_animation(self, "walk", "walk_reverse")
			mobkit.animate(self, "walk_reverse")
		elseif tvel < 0.25 or tvel == 0 then
			tvel = 0
			self.object:set_velocity({x=0,y=vel.y,z=0})
			mobkit.animate(self, "stand")
		end
		 -- jump
		if self.isonground then
			if ctrl.jump then
				vel.y = (self.jump_height)+4
			end
		end
		 --stand
		if tvel ~= 0 and not ctrl.up or ctrl.down then
			tvel = tvel*0.75
		end
        if tvel > 0 then
            mobkit.animate(self,"walk")
        end
		local tyaw = self.driver:get_look_horizontal() or 0
        self.object:set_yaw(tyaw)
        self.object:set_velocity({x=vel.x,y=vel.y,z=vel.y})
        go_forward(self,tvel)
        if ctrl.sneak then
            mobkit.clear_queue_low(self)
            mobkit.clear_queue_high(self)
            mob_core.detach(self.driver, {x = 1, y = 0, z = 1})
        end
	end
	mobkit.queue_high(self,func,prty)
end
