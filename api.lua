------------------
-- Mob Core API --
------------------
----- Ver 0.1 ----

---------------------
-- Local Variables --
---------------------

local abs = math.abs
local floor = math.floor
local random = math.random
local min = math.min

local creative = minetest.settings:get_bool("creative_mode")

mob_core.walkable_nodes = {}

minetest.register_on_mods_loaded(function()
    for name in pairs(minetest.registered_nodes) do
        if name ~= "air" and name ~= "ignore" then
            if minetest.registered_nodes[name].walkable then
                table.insert(mob_core.walkable_nodes, name)
            end
        end
    end
end)

----------------------
-- Helper Functions --
----------------------

local function all_first_to_upper(str)
	str = string.gsub(" "..str, "%W%l", string.upper):sub(2)
    return str
end

local function underscore_to_space(str)
    return (str:gsub("_", " "))
end

function mob_core.get_name_proper(str)
	if str then
		if str:match(":") then
			str = str:split(":")[2]
		end
		str = all_first_to_upper(str)
		str = underscore_to_space(str)
		return str
	end
end

function mob_core.is_mobkit_mob(object)
	if type(object) == 'userdata' then
		object = object:get_luaentity()
	end
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

function mob_core.shared_owner(self, object)
	if object:is_player() then return false end
	if type(object) == 'userdata' then
		object = object:get_luaentity()
	end
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

function mob_core.find_val(tbl, val)
    for _, v in ipairs(tbl) do
        if v == val then
            return true
        end
    end
    return false
end

-- Follow Holding? --

function mob_core.follow_holding(self, player)
	local item = player:get_wielded_item()
	local t = type(self.follow)
	if t == "string"
	and item:get_name() == self.follow then
		return true
	elseif t == "table" then
		for no = 1, #self.follow do
			if self.follow[no] == item:get_name() then
				return true
			end
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
		if len1 == 6 then
			col1 = col1 .. "d9"
		end
		if len2 == 6 then
			col2 = col2 .. "d9"
		end
		local base = "mob_core_spawn_egg_base.png^(mob_core_spawn_egg_base.png^[colorize:#"..col1..")"
		local spots = "mob_core_spawn_egg_overlay.png^(mob_core_spawn_egg_overlay.png^[colorize:#"..col2..")"
		inventory_image = base .. "^" .. spots
	end
	minetest.register_craftitem(mob:split(":")[1]..":spawn_"..mob:split(":")[2], {
		description = "Spawn "..mob_core.get_name_proper(mob),
		inventory_image = inventory_image,
		stack_max = 99,
		on_place = function(itemstack, _, pointed_thing)
			local mobdef = minetest.registered_entities[mob]
			local spawn_offset = math.abs(mobdef.collisionbox[2])
			local pos = minetest.get_pointed_thing_position(pointed_thing, true)
			pos.y = pos.y+spawn_offset
            minetest.add_entity(pos, mob)
            if not creative then
                itemstack:take_item()
			    return itemstack
			end
		end,
	})
end

function mob_core.register_set(mob, background, mask)
	local invimg = background
	if mask then
		invimg = "mob_core_spawn_egg_base.png^(" .. invimg ..
			"^[mask:mob_core_spawn_egg_overlay.png)"
	end
	if not minetest.registered_entities[mob] then
		return
	end
	-- register new spawn egg containing mob information
	minetest.register_craftitem(mob .. "_set", {
		description = mob_core.get_name_proper(mob).." (Captured)",
		inventory_image = invimg,
		groups = {not_in_creative_inventory = 1},
		stack_max = 1,
		on_place = function(itemstack, placer, pointed_thing)
			local pos = pointed_thing.above
			-- am I clicking on something with existing on_rightclick function?
			local under = minetest.get_node(pointed_thing.under)
			local node = minetest.registered_nodes[under.name]
			if node and node.on_rightclick then
				return node.on_rightclick(pointed_thing.under, under, placer, itemstack)
			end
			if pos
			and not minetest.is_protected(pos, placer:get_player_name()) then
				pos.y = pos.y + 1
				local staticdata = itemstack:get_meta():get_string("staticdata")
				minetest.add_entity(pos, mob, staticdata)
				itemstack:take_item()
			end
			return itemstack
		end,
	})
end

-----------------------
-- Utility Functions --
-----------------------

------------
-- Sounds --
------------

function mob_core.make_sound(self, sound)
	local spec = self.sounds and self.sounds[sound]
	local parameters = {object = self.object}
	
	if type(spec) == 'table' then
		if #spec > 0 then spec = spec[random(#spec)] end

		local function in_range(value)
			return type(value) == 'table' and value[1]+random()*(value[2]-value[1]) or value
		end

		local pitch = 1.0

		pitch = pitch + random(-10, 10) * 0.005

		if self.child
		and self.sounds.alter_child_pitch then
			parameters.pitch = 2.0
		end

		minetest.sound_play(spec, parameters)

		if not spec.gain then spec.gain = 1.0 end
		if not spec.distance then spec.distance = 16 end
		
		--pick random values within a range if they're a table
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
	if math.random(1, chance) == 1 then
		mob_core.make_sound(self, "random")
	end
end

----------------
-- Drop Items --
----------------

function mob_core.item_drop(self) -- Drop Items
	if not self.drops or #self.drops == 0 then
		return
	end
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

-- Damage Indication --

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

-- Death --

local pi = math.pi

function mob_core.lq_fallover(self)
	local zrot = 0
	local init = true
	local func=function(self)
		if init then
			local vel = self.object:get_velocity()
			self.object:set_velocity(mobkit.pos_shift(vel,{y=1}))
			mobkit.animate(self,'stand')
			init = false
		end
		zrot=zrot+pi*0.05
		local rot = self.object:get_rotation()
		if rot then self.object:set_rotation({x=rot.x,y=rot.y,z=zrot}) end
		if zrot >= pi*0.5 then return true end
	end
	mobkit.queue_low(self,func)
end

function mob_core.on_die(self)
	mobkit.clear_queue_high(self)
	mobkit.clear_queue_low(self)
	local pos = mobkit.get_stand_pos(self)
	if self.driver then
		mob_core.force_detach(self.driver)
	end
	if self.owner then
		self.owner = nil
	end
	if self.sounds and self.sounds["death"] then
        mob_core.make_sound(self, "death")
	end
	self.object:set_velocity({x=0,y=0,z=0})
	self.object:settexturemod("^[colorize:#FF000040")
	local timer = 1
	local start = true
	local func = function()
		if not mobkit.exists(self) then return true end
		if start then
			if self.animation
			and self.animation["death"] then
				mobkit.animate(self,"death")
			else
				mob_core.lq_fallover(self)
			end
			self.logic = function() end	-- brain dead as well
			start = false
		end
		timer = timer-self.dtime
		if timer <= 0 then
			if self.driver then
				mob_core.force_detach(self.driver)
			end
			mob_core.item_drop(self)
			minetest.add_particlespawner({
				amount = 12,
				time = 0.1,
				minpos = {
					x = pos.x - self.collisionbox[4]*0.75,
					y = pos.y,
					z = pos.z - self.collisionbox[4]*0.75,
				},
				maxpos = {
					x = pos.x + self.collisionbox[4]*0.75,
					y = pos.y + self.collisionbox[4]*0.75,
					z = pos.z + self.collisionbox[4]*0.75,
				},
				minvel = {x=-0.2, y=-0.1, z=-0.2},
				maxvel = {x=0.2, y=-0.1, z=0.2},
				minacc = {x=0, y=0.25, z=0},
				maxacc = {x=0, y=0.45, z=0},
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
			if self.driver then
				mob_core.force_detach(self.driver)
			end
			mob_core.item_drop(self)
			minetest.add_particlespawner({
				amount = self.collisionbox[4]*4,
				time = 0.25,
				minpos = {
					x = pos.x - self.collisionbox[4]*0.5,
					y = pos.y,
					z = pos.z - self.collisionbox[4]*0.5,
				},
				maxpos = {
					x = pos.x + self.collisionbox[4]*0.5,
					y = pos.y + self.collisionbox[4]*0.5,
					z = pos.z + self.collisionbox[4]*0.5,
				},
				minacc = {x = -0.25, y = 0.5, z = -0.25},
				maxacc = {x = 0.25, y = 0.25, z = 0.25},
				minexptime = 0.75,
				maxexptime = 1,
				minsize = 4,
				maxsize = 4,
				texture = "mob_core_red_particle.png",
				glow = 16,
			})
			self.object:remove()
		end)
	end
	mobkit.queue_high(self, func, 100)
end

-- Vitals --

function mob_core.vitals(self)
	if not mobkit.is_alive(self) then return end
	-- Fall Damage
	if self.fall_damage == nil then
		self.fall_damage = true
	end
	if self.fall_damage then
		if not self.isonground
		and not self.isinliquid
		and not self.fall_start then
			self.fall_start = mobkit.get_stand_pos(self).y
		end
		if self.fall_start then
			local fall_distance = self.fall_start - mobkit.get_stand_pos(self).y
			if not self.max_fall then
				self.max_fall = 3
			end
			if self.isonground
			and fall_distance > self.max_fall then
				flash_red(self)
				mob_core.make_sound(self, "hurt")
				mobkit.hurt(self, fall_distance)
				self.fall_start = nil
			end
		end
	end

	-- Lava/Fire Damage
	if self.igniter_damage == nil then
		self.igniter_damage = true
	end

	if self.igniter_damage then
		local pos = mobkit.get_stand_pos(self)
		local node = minetest.get_node(pos)
		if node and minetest.registered_nodes[node.name].groups.igniter then
			if mobkit.timer(self,1) then
				flash_red(self)
				mob_core.make_sound(self, "hurt")
				mobkit.hurt(self, self.max_hp/16)
			end
		end
	end

	-- Drowning
	if self.lung_capacity then
		local colbox = self.object:get_properties().collisionbox
		local headnode = mobkit.nodeatpos(mobkit.pos_shift(self.object:get_pos(),{y=colbox[5]})) -- node at hitbox top
		if headnode and headnode.drawtype == 'liquid' then
			self.oxygen = self.oxygen - self.dtime
		else
			self.oxygen = self.lung_capacity
		end

		if self.oxygen <= 0 then
			if mobkit.timer(self,2) then
				flash_red(self)
				mobkit.hurt(self,self.max_hp/self.lung_capacity)
			end
		end
	end
end

-- Basic Damage -- Flash red, Knockback, Make sound.

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
				local hvel = vector.multiply(vector.normalize({x=dir.x,y=0,z=dir.z}),4)
				self.object:add_velocity({x=hvel.x,y=2,z=hvel.z})
			end
			mobkit.hurt(self,tool_capabilities.damage_groups.fleshy or 1)
			mob_core.make_sound(self, "hurt")
		end
	end
end

-- Retaliate --

function mob_core.on_punch_retaliate(self, puncher, water, group)
	if mobkit.is_alive(self) then
		local pos = self.object:get_pos()
		if (not water) or (water and self.semiaquatic) then
			mob_core.hq_hunt(self, 10, puncher)
			if group then
				local objs = minetest.get_objects_inside_radius(pos, self.view_range)
				for n = 1, #objs do
					local luaent = objs[n]:get_luaentity()
					if luaent and luaent.name == self.name and luaent.owner == self.owner and mobkit.is_alive(luaent) then
						mob_core.hq_hunt(luaent, 10, puncher)
					end
				end
			end
		elseif water and self.isinliquid then
			mob_core.hq_aqua_attack(self, 10, puncher, 1)
			if group then
				local objs = minetest.get_objects_inside_radius(pos, self.view_range)
				for n = 1, #objs do
					local luaent = objs[n]:get_luaentity()
					if luaent and luaent.name == self.name and luaent.owner == self.owner and mobkit.is_alive(luaent) then
						mob_core.hq_aqua_attack(luaent, 10, puncher, 1)
					end
				end
			end
		end
	end
end

-- Runaway --

function mob_core.on_punch_runaway(self, puncher, water, group)
	if mobkit.is_alive(self) then
		local pos = self.object:get_pos()
		if (not water) or (water and not self.isinliquid) then
			mobkit.hq_runfrom(self, 10, puncher)
			if group then
				local objs = minetest.get_objects_inside_radius(pos, self.view_range)
				for n = 1, #objs do
					local luaent = objs[n]:get_luaentity()
					if luaent and luaent.name == self.name and luaent.owner == self.owner and mobkit.is_alive(luaent) then
						mobkit.hq_runfrom(self, 10, puncher)
					end
				end
			end
		elseif water and self.isinliquid then
			mob_core.hq_swimfrom(self, 10, puncher, 1)
			if group then
				local objs = minetest.get_objects_inside_radius(pos, self.view_range)
				for n = 1, #objs do
					local luaent = objs[n]:get_luaentity()
					if luaent and luaent.name == self.name and luaent.owner == self.owner and mobkit.is_alive(luaent) then
						mob_core.hq_swimfrom(luaent, 10, puncher, 1)
					end
				end
			end
		end
	end
end

-- Default On Punch -- Likely won't be used, more of a demo

function mob_core.on_punch(self, puncher, time_from_last_punch, tool_capabilities, dir)
	mob_core.on_punch_basic(self, puncher, time_from_last_punch, tool_capabilities, dir)
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
	if not self.nametag then
		return
	end
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
	self.breed_mode = mobkit.recall(self, "breed_mode") or false
	self.breed_timer = mobkit.recall(self, "breed_timer") or 0
	self.growth_stage = mobkit.recall(self, "growth_stage") or 4
	self.growth_timer = mobkit.recall(self, "growth_timer") or 1801
	self.child = mobkit.recall(self, "child") or false
	self.status = mobkit.recall(self, "status") or ""
	self.nametag = mobkit.recall(self, "nametag") or ""
	set_gender(self)
	mob_core.activate_nametag(self)
	mob_core.set_textures(self)
	if self.protected then
		self.timeout = nil
	end
	if self.growth_stage == 1
	and self.scale_stage1 then
		mob_core.set_scale(self, self.scale_stage1)
	elseif self.growth_stage == 2
	and self.scale_stage2 then
		mob_core.set_scale(self, self.scale_stage2)
	elseif self.growth_stage == 3
	and self.scale_stage3 then
		mob_core.set_scale(self, self.scale_stage3)
	elseif self.growth_stage == 4 then
		mob_core.set_scale(self, 1)
	end
end

-----------------------
-- Utility Functions --
-----------------------

-- Set Scale --

function mob_core.set_scale(self, scale)
	self.base_size = self.visual_size
	self.base_colbox = self.collisionbox
	self.base_selbox = self.selectionbox

	self.object:set_properties({
		visual_size = {
			x = self.base_size.x*scale,
			y = self.base_size.y*scale
		},
		collisionbox = {
			self.base_colbox[1]*scale,
			self.base_colbox[2]*scale,
			self.base_colbox[3]*scale,
			self.base_colbox[4]*scale,
			self.base_colbox[5]*scale,
			self.base_colbox[6]*scale
		},
	})
end

-- Set Owner --

function mob_core.set_owner(self, name)
	self.tamed = mobkit.remember(self, "tamed", true)
	self.owner = mobkit.remember(self, "owner", name)
end

-- Spawn Child Mob --

function mob_core.spawn_child(pos, mob)
	local obj = minetest.add_entity(pos, mob)
	local luaent = obj:get_luaentity()
	luaent.child = mobkit.remember(luaent,"child",true)
	luaent.growth_timer = mobkit.remember(luaent,"growth_timer",1)
	luaent.growth_stage = mobkit.remember(luaent,"growth_stage",1)
	mob_core.set_scale(luaent, luaent.scale_stage1 or 0.25)
	mob_core.set_textures(luaent)
	return
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
					local mob_name = mob_core.get_name_proper(pointedobject.name)
					if not pointedobject.tamed then
						if not pointedobject.logic or pointedobject.brainfunc then
							minetest.chat_send_player(name, "This command only works on mobkit mobs")
							return
						end
						mob_core.set_owner(pointedobject, name)
						minetest.chat_send_player(name, mob_name.." has been tamed!")
						mobkit.clear_queue_high(pointedobject)
						pos = pointedobject.object:get_pos()
						minetest.add_particlespawner({
							amount = 16,
							time = 0.25,
							minpos = {
								x = pos.x - pointedobject.collisionbox[4],
								y = pos.y - pointedobject.collisionbox[4],
								z = pos.z - pointedobject.collisionbox[4],
							},
							maxpos = {
								x = pos.x + pointedobject.collisionbox[4],
								y = pos.y + pointedobject.collisionbox[4],
								z = pos.z + pointedobject.collisionbox[4],
							},
							minacc = {x = 0, y = 0.25, z = 0},
							maxacc = {x = 0, y = -0.25, z = 0},
							minexptime = 0.75,
							maxexptime = 1,
							minsize = 4,
							maxsize = 4,
							texture = "mob_core_green_particle.png",
							glow = 16,
						})
						return
					else
						minetest.chat_send_player(name, mob_name.." is already tamed.")
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

-- Spawning --

function mob_core.get_biome_name(pos)
	if not pos then return end
	return minetest.get_biome_name(minetest.get_biome_data(pos).biome)
end

local find_node_height = 32

local block_protected_spawn = minetest.settings:get_bool("block_protected_spawn") or true
local mob_limit = minetest.settings:get_bool("mob_limit") or 6

function mob_core.spawn(name, nodes, min_light, max_light, min_height, max_height, min_rad, max_rad, group, optional)
	group = group or 1
	if minetest.registered_entities[name] then
		for _,player in ipairs(minetest.get_connected_players()) do
			local mobs_amount = 0
			for _, entity in pairs(minetest.luaentities) do
				if entity.name == name then
					local ent_pos = entity.object:get_pos()
					if ent_pos and vector.distance(player:get_pos(), ent_pos) <= max_rad then
						mobs_amount = mobs_amount + 1
					end
				end
			end

			if mobs_amount >= mob_limit then
				return
			end

			local reliability = 3

			if optional
			and optional.reliability then
				reliability = optional.reliability
			end

			for _ = 1, reliability do -- 3 attempts
				local int = {-1,1}
				local pos = vector.floor(vector.add(player:get_pos(),0.5))
	
				local x,z
	
				--this is used to determine the axis buffer from the player
				local axis = math.random(0, 1)
	
				--cast towards the direction
				if axis == 0 then --x
					x = pos.x + math.random(min_rad, max_rad) * int[random(1,2)]
					z = pos.z + math.random(-max_rad, max_rad)
				else --z
					z = pos.z + math.random(min_rad, max_rad) * int[random(1,2)]
					x = pos.x + math.random(-max_rad, max_rad)
				end
	
				local spawner = minetest.find_nodes_in_area_under_air(
					vector.new(x - 1, pos.y - find_node_height, z - 1),
					vector.new(x + 1, pos.y + find_node_height, z + 1), nodes)
	
				if table.getn(spawner) > 0 then
					local mob_pos = spawner[1]
	
					if block_protected_spawn and minetest.is_protected(mob_pos, "") then
						return
					end
	
					if optional then
						if optional.biomes then
							if not mob_core.find_val(optional.biomes, mob_core.get_biome_name(pos)) then
								return
							end
						end
					end
	
					if mob_pos.y > max_height
					or mob_pos.y < min_height then
						return
					end
	
					local light = minetest.get_node_light(mob_pos)
					if not light
					or light > max_light
					or light < min_light then
						return
					end
	
					minetest.add_entity(mob_pos, name)
	
					if group then
	
						local spawned = 0
	
						local attempts = 0
	
						while spawned < group
						and attempts < group * 2 do
							local mobdef = minetest.registered_entities[name]
							local side = mobdef.collisionbox[4]
							local group_pos = vector.new(
								mob_pos.x + (random(-group, group) * side),
								mob_pos.y,
								mob_pos.z + (random(-group, group) * side)
							)
							local spawn_pos = minetest.find_nodes_in_area_under_air(
								vector.new(group_pos.x, group_pos.y - 8, group_pos.z),
								vector.new(group_pos.x, group_pos.y + 8, group_pos.z),
								nodes)
							if spawn_pos[1] then
								minetest.add_entity(vector.new(
									spawn_pos[1].x,
									spawn_pos[1].y + math.abs(mobdef.collisionbox[2]),
									spawn_pos[1].z
								), name)
								spawned = spawned + 1
							end
							attempts = attempts + 1
						end
					end
					break
				end
			end
		end
	end
end

function mob_core.register_spawn(def, interval, chance)
	local spawn_timer = 0
	minetest.register_globalstep(function(dtime)
		spawn_timer = spawn_timer + dtime
		if spawn_timer > interval then
			if random(1, chance) == 1 then
				mob_core.spawn(
					def.name,
					def.nodes or {"group:soil", "group:stone"},
					def.min_light or 0,
					def.max_light or 15,
					def.min_height or -31000,
					def.max_height or 31000,
					def.min_rad or 24,
					def.max_rad or 256,
					def.group or 1,
					def.optional or nil
				)
			end
			spawn_timer = 0
		end
	end)
end


-------------
-- On Step --
-------------

-- Push on entity collision --

function mob_core.collision_detection(self)
	if not mobkit.is_alive(self) then return end
	local pos = self.object:get_pos()
	local hitbox = self.object:get_properties().collisionbox
	local width = -hitbox[1] + hitbox[4] + 0.5
	for _, object in ipairs(minetest.get_objects_inside_radius(pos, width)) do
		if (object and object ~= self.object)
		and (object:is_player() or (object:get_luaentity() and object:get_luaentity().logic))
		and (not object:get_attach() or (object:get_attach() and object:get_attach() ~= self.object))
		and (not self.object:get_attach() or (self.object:get_attach() and self.object:get_attach() ~= object)) then
			local pos2 = object:get_pos()
			local dir = vector.direction(pos,pos2)
			dir.y = 0
			if dir.x == 0 and dir.z == 0 then
				dir = vector.new(math.random(-1,1)*math.random(),0,math.random(-1,1)*math.random())
			end
			local velocity = vector.multiply(dir,1.1)
			local vel1 = vector.multiply(velocity, -1)
			local vel2 = velocity
			self.object:add_velocity(vel1)
			if object:is_player() then
				object:add_player_velocity(vel2)
			else
				object:add_velocity(vel2)
			end
		end
	end
end

-- 4 Stage Growth --

function mob_core.growth(self,interval)
	if not mobkit.is_alive(self) then return end
	if self.growth_stage == 4 then return end
	if not self.base_hp then
		self.base_hp = mobkit.remember(self,"base_hp",self.max_hp)
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
    if self.growth_stage < 4 then
        self.growth_timer = self.growth_timer + 1
    end
	if self.growth_timer > interval then
		self.growth_timer = 1
		self.max_speed = speed/4
		if reach then
			self.reach = reach/4
		end
		if self.growth_stage == 1 then
			self.growth_stage = mobkit.remember(self,"growth_stage",2)
			self.object:set_pos({x=pos.x,y=pos.y+math.abs(self.collisionbox[2]),z=pos.z})
			mob_core.set_scale(self, self.scale_stage2)
			self.max_speed = speed/2
			if reach then
				self.reach = reach/2
			end
		elseif self.growth_stage == 2 then
			self.growth_stage = mobkit.remember(self,"growth_stage",3)
			self.object:set_pos({x=pos.x,y=pos.y+math.abs(self.collisionbox[2]),z=pos.z})
			mob_core.set_scale(self, self.scale_stage3)
			self.child = mobkit.remember(self,"child",false)
			mob_core.set_textures(self)
			self.max_speed = speed/1.5
			if reach then
				self.reach = reach/1.5
			end
		elseif self.growth_stage == 3 then
			self.growth_stage = mobkit.remember(self,"growth_stage",4)
			self.object:set_pos({x=pos.x,y=pos.y+math.abs(self.collisionbox[2]),z=pos.z})
			mob_core.set_scale(self, 1)
			self.max_speed = speed
			if reach then
				self.reach = reach
			end
		end
	end
	if self.growth_stage == 1
	and self.hp > self.max_hp/4 then
		self.hp = self.max_hp/4
	end
	if self.growth_stage == 2
	and self.hp > self.max_hp/2 then
		self.hp = self.max_hp/2
	end
	if self.growth_stage == 3
	and self.hp > self.max_hp/1.5 then
		self.hp = self.max_hp/1.5
	end
    self.growth_timer = mobkit.remember(self,"growth_timer",self.growth_timer)
end

-- Breeding --

function mob_core.breed(self)
	if not mobkit.is_alive(self) then return end
    if self.breed_timer > 0 then
        self.breed_timer = self.breed_timer - self.dtime
    else
        self.breed_timer = 0
    end
	if self.gender == "female" then
		local pos = self.object:get_pos()
		local objs = minetest.get_objects_inside_radius(pos, self.collisionbox[4]*4)
		for i = 1, #objs do
			local luaent = objs[i]:get_luaentity()
			if luaent and luaent.name == self.name then
				if luaent.breed_mode == true and luaent.gender == "male" then
					self.breed_mode = false
					self.breed_timer = 300
					luaent.breed_mode = false
					luaent.breed_timer = 300
					minetest.after(2.5,function()
						mob_core.spawn_child(pos,self.name)
						minetest.add_particlespawner({
							amount = 16,
							time = 0.25,
							minpos = {
								x = pos.x - self.collisionbox[4],
								y = pos.y - self.collisionbox[4],
								z = pos.z - self.collisionbox[4],
							},
							maxpos = {
								x = pos.x + self.collisionbox[4],
								y = pos.y + self.collisionbox[4],
								z = pos.z + self.collisionbox[4],
							},
							minacc = {x = 0, y = 0.25, z = 0},
							maxacc = {x = 0, y = -0.25, z = 0},
							minexptime = 0.75,
							maxexptime = 1,
							minsize = 4,
							maxsize = 4,
							texture = "heart.png",
							glow = 16,
						})
					end)
				end
			end
		end
	end
end

-- Step Function --

function mob_core.on_step(self, dtime, moveresult)
	mobkit.stepfunc(self, dtime)
	self.moveresult = moveresult
	if self.owner_target
	and not mobkit.exists(self.owner_target) then
		self.owner_target = nil
	end
	if self.custom_punch_target
	and not mobkit.exists(self.custom_punch_target) then
		self.custom_punch_target = nil
	end

	if self.core_growth then
		mob_core.growth(self)
	end
	if self.core_breeding then
		mob_core.breed(self)
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
		self.status = mobkit.remember(self,"status","ridden")
		mob_core.attach(self, clicker)
		return false
	else
		return true
	end
end

-- Capture Mob --

function mob_core.capture_mob(self, clicker, capture_tool, capture_chance, wear, force_take)
	if not clicker:is_player()
	or not clicker:get_inventory() then
		return false
	end
	local mobname = self.name
	local catcher = clicker:get_player_name()
	local tool = clicker:get_wielded_item()
	if tool:get_name() ~= capture_tool then
		return false
	end
	if self.tamed == false then
		minetest.chat_send_player(catcher, "Mob is not tamed.")
		return false
	end
	if self.owner ~= catcher
	and force_take == false then
		minetest.chat_send_player(catcher, "Mob is owned by @1"..self.owner)
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
		mobkit.heal(self, self.max_hp/feed_count)
		if self.hp >= self.max_hp then
			self.hp = self.max_hp
		end
		self.food = mobkit.remember(self, "food", self.food + 1)
		if self.food >= feed_count then
			self.food = mobkit.remember(self, "food", 0)
			if tame and not self.tamed then
				mob_core.set_owner(self, clicker:get_player_name())
				minetest.chat_send_player(clicker:get_player_name(), mob_name.." has been tamed!")
				mobkit.clear_queue_high(self)
				minetest.add_particlespawner({
					amount = 16,
					time = 0.25,
					minpos = {
						x = pos.x - self.collisionbox[4],
						y = pos.y - self.collisionbox[4],
						z = pos.z - self.collisionbox[4],
					},
					maxpos = {
						x = pos.x + self.collisionbox[4],
						y = pos.y + self.collisionbox[4],
						z = pos.z + self.collisionbox[4],
					},
					minacc = {x = 0, y = 0.25, z = 0},
					maxacc = {x = 0, y = -0.25, z = 0},
					minexptime = 0.75,
					maxexptime = 1,
					minsize = 4,
					maxsize = 4,
					texture = "mob_core_green_particle.png",
					glow = 16,
				})
			end
			if breed then
				if self.child then return false end
				if self.breed_mode then return false end
				if self.breed_timer == 0 and self.breed_mode == false then
					self.breed_mode = true
					minetest.add_particlespawner({
						amount = 16,
						time = 0.25,
						minpos = {
							x = pos.x - self.collisionbox[4],
							y = pos.y - self.collisionbox[4],
							z = pos.z - self.collisionbox[4],
						},
						maxpos = {
							x = pos.x + self.collisionbox[4],
							y = pos.y + self.collisionbox[4],
							z = pos.z + self.collisionbox[4],
						},
						minacc = {x = 0, y = 0.25, z = 0},
						maxacc = {x = 0, y = -0.25, z = 0},
						minexptime = 0.75,
						maxexptime = 1,
						minsize = 4,
						maxsize = 4,
						texture = "heart.png",
						glow = 16,
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
	if item:get_name() ~= "mob_core:protection_gem" then
		return false
	end
	if self.tamed == false and not force_protect then
		minetest.chat_send_player(name, mob_name.." is not tamed")
		return true
	end
	if self.protected == true then
		minetest.chat_send_player(name, mob_name.." is already protected")
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
	pos.y = pos.y + self.collisionbox[2] + 1/1
	minetest.add_particlespawner({
		amount = 16,
		time = 0.25,
		minpos = {
			x = pos.x - self.collisionbox[4],
			y = pos.y - self.collisionbox[4],
			z = pos.z - self.collisionbox[4],
		},
		maxpos = {
			x = pos.x + self.collisionbox[4],
			y = pos.y + self.collisionbox[4],
			z = pos.z + self.collisionbox[4],
		},
		minacc = {x = 0, y = 0.25, z = 0},
		maxacc = {x = 0, y = -0.25, z = 0},
		minexptime = 0.75,
		maxexptime = 1,
		minsize = 4,
		maxsize = 4,
		texture = "mob_core_green_particle.png",
		glow = 16,
	})
	return true
end

-- Set Nametag --

local nametag_obj = {}
local nametag_item = {}

function mob_core.nametag(self, clicker, force_name)
	if not force_name
	and clicker:get_player_name() ~= self.owner then
		return
	end
	local item = clicker:get_wielded_item()
	if item:get_name() == "mob_core:nametag" then

		local name = clicker:get_player_name()

		nametag_obj[name] = self
		nametag_item[name] = item

		local tag = self.nametag or ""

		minetest.show_formspec(name, "mob_core_nametag", "size[8,4]"
			.. "field[0.5,1;7.5,0;name;"
			.. minetest.formspec_escape("Enter name:") .. ";" .. tag .. "]"
			.. "button_exit[2.5,3.5;3,1;mob_rename;"
			.. minetest.formspec_escape("Rename") .. "]")
	end
end

minetest.register_on_player_receive_fields(function(player, formname, fields)

	if formname == "mob_core_nametag"
	and fields.name then

		local name = player:get_player_name()

		if not nametag_obj[name]
		or not nametag_obj[name].object then
			return
		end

		local item = player:get_wielded_item()

		if item:get_name() ~= "mob_core:nametag" then
			return
		end

		if string.len(fields.name) > 64 then
			fields.name = string.sub(fields.name, 1, 64)
		end

		nametag_obj[name].nametag = mobkit.remember(nametag_obj[name], "nametag", fields.name)

		mob_core.activate_nametag(nametag_obj[name])

		if fields.name ~= ""
		and not creative then
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

local function can_fit(pos, width, height)
	height = height or 0
    local pos1 = vector.new(pos.x - width, pos.y, pos.z - width)
    local pos2 = vector.new(pos.x + width, pos.y + height, pos.z + width)
    for x = pos1.x, pos2.x do
        for y = pos1.y, pos2.y do
            for z = pos1.z, pos2.z do
                local p2 = vector.new(x, y, z)
                local node = minetest.get_node(p2)
                if minetest.registered_nodes[node.name].walkable then
                    local p3 = vector.new(p2.x, p2.y + 1, p2.z)
                    local node2 = minetest.get_node(p3)
					if minetest.registered_nodes[node2.name].walkable then
                        return false
                    end
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
                if can_fit(p2, width) then
                    return p2
                end
            end
        end
    end
    return pos
end

function mob_core.find_path(pos, tpos, width)

	local raw

    if not minetest.registered_nodes[minetest.get_node(
        vector.new(pos.x, pos.y - 1, pos.z))
        .name].walkable then
        local min = vector.subtract(pos, width+1)
        local max = vector.add(pos, width+1)

        local index_table = minetest.find_nodes_in_area_under_air( min, max, mob_core.walkable_nodes)
        for _, i_pos in pairs(index_table) do
            if minetest.registered_nodes[minetest.get_node(i_pos)
                .name].walkable then
					pos = vector.new(i_pos.x, i_pos.y + 1, i_pos.z)
                break
            end
        end
	end

    if not minetest.registered_nodes[minetest.get_node(
        vector.new(tpos.x, tpos.y - 1, tpos.z))
        .name].walkable then
        local min = vector.subtract(tpos, width)
        local max = vector.add(tpos, width)

        local index_table = minetest.find_nodes_in_area_under_air( min, max, mob_core.walkable_nodes)
        for _, i_pos in pairs(index_table) do
            if minetest.registered_nodes[minetest.get_node(i_pos)
                .name].walkable then
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
		if vector.distance(pos, path[i]) <= width + 1 then
            for i = 3, #path do
                path[i - 1] = path[i]
			end
		end

        if not can_fit(path[i], width + 1) then
            local clear = move_from_wall(path[i], width + 1)
            if clear and can_fit(clear, width) then
                path[i] = clear
            end
		end

		if minetest.get_node(path[i]).name == "default:snow" then
			path[i] = vector.new(path[i].x, path[i].y + 1, path[i].z)
		end


		raw = path
		if #path > 3 then
			
			if vector.distance(pos, path[i]) < width then
				table.remove(path, i)
			end

            local pos1 = path[i - 2]
			local pos2 = path[i]
			-- Handle Diagonals
            if pos1
            and pos2
            and pos1.x ~= pos2.x
            and pos1.z ~= pos2.z then
				if minetest.line_of_sight(pos1, pos2) then
					local pos3 = vector.divide(vector.add(pos1, pos2), 2)
					if can_fit(pos, width) then
						table.remove(path, i - 1)
					end
                end
			end
			-- Reduce Straight Lines
			if pos1
            and pos2
            and pos1.x == pos2.x
			and pos1.z ~= pos2.z
			and pos1.y == pos2.y then
                if minetest.line_of_sight(pos1, pos2) then
					local pos3 = vector.divide(vector.add(pos1, pos2), 2)
					if can_fit(pos, width) then
						table.remove(path, i - 1)
					end
                end
            elseif pos1
			and pos2
			and pos1.x ~= pos2.x
			and pos1.z == pos2.z
			and pos1.y == pos2.y then
				if minetest.line_of_sight(pos1, pos2) then
					local pos3 = vector.divide(vector.add(pos1, pos2), 2)
					if can_fit(pos, width) then
						table.remove(path, i - 1)
					end
				end
			end
		end
    end

    return path, raw
end
