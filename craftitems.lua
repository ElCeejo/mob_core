--------------------
-- Mob Core Items --
--------------------
------ Ver 0.1 -----

-- Protection Gem --

minetest.register_craftitem("mob_core:protection_gem", {
	description = "Protection Gem",
	inventory_image = "mob_core_protection_gem.png",
})

-- Nametag --

minetest.register_craftitem("mob_core:nametag", {
	description = "Name Tag",
	inventory_image = "mob_core_nametag.png",
	groups = {flammable = 2}
})

-- Crafting --

minetest.register_craft({
	type = "shapeless",
	output = "mob_core:protection_gem",
	recipe = {"default:diamond"}
})

if minetest.get_modpath("dye") and minetest.get_modpath("farming") then
	minetest.register_craft({
		type = "shapeless",
		output = "mob_core:nametag",
		recipe = {"default:paper", "dye:black", "farming:string"}
	})
end
