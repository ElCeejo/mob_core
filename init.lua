mob_core = {}

--------------
-- Mob Core --
--------------
--- Ver 0.1 --

local path = minetest.get_modpath("mob_core")

dofile(path.."/api.lua")
dofile(path.."/hq_lq.lua")
dofile(path.."/logic.lua")
dofile(path.."/craftitems.lua")
dofile(path.."/pathfinder.lua")

if minetest.get_modpath("default") then
    dofile(path.."/mount.lua")
end