mob_core = {}

--------------
-- Mob Core --
--------------
--- Ver 0.1 --

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

local path = minetest.get_modpath("mob_core")

dofile(path.."/api.lua")
dofile(path.."/hq_lq.lua")
dofile(path.."/logic.lua")
dofile(path.."/craftitems.lua")

if minetest.get_modpath("default") then
    dofile(path.."/mount.lua")
end