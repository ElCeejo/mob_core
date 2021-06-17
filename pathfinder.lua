mob_core_pathfinder = {}

local openSet = {}
local closedSet = {}
local random = math.random
local abs = math.abs
local ceil = math.ceil
local floor = math.floor

local function clamp(num, min, max)
	if num < min then
		num = min
	elseif num > max then
		num = max    
	end
	
	return num
end


local vec_dir = vector.direction
local vec_round = vector.round
local vec_add = vector.add
local vec_multiply = vector.multiply

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

local function walkable(node)
    if minetest.registered_nodes[node.name].drawtype == "liquid" then
        return true
    elseif minetest.registered_nodes[node.name].walkable then
        return true
    end
    return false
end

local function can_stand(pos, width)
    local stage = 1
    local pos1 = vector.new(pos.x - width, pos.y - 1, pos.z - width)
    local pos2 = vector.new(pos.x + width, pos.y, pos.z + width)
    for x = pos1.x, pos2.x do
        for z = pos1.z, pos2.z do
            local v_new = vector.new(x, pos1.y, z)
            local node = minetest.get_node(v_new)
            local def = minetest.registered_nodes[node.name]
            if def
            and def.walkable then
                stage = 2
                break
            end
        end
    end
    if stage == 2 then
        for x = pos1.x, pos2.x do
            for z = pos1.z, pos2.z do
                local v_new = vector.new(x, pos.y, z)
                local node = minetest.get_node(v_new)
                local def = minetest.registered_nodes[node.name]
                if def
                and def.walkable then
                    return false
                end
            end
        end
    end
    return true
end

local function is_object_at_pos(self, pos)
    local objects = minetest.get_objects_inside_radius(pos, 0.5)
    if #objects < 1 then return false end
    for i = 1, #objects do
        if objects[i] ~= self.object
        and not (objects[i]:get_luaentity()
        and objects[i]:get_luaentity().collide_with_objects) then
            return true
        end
    end
    return false
end

local function moveable(pos, width, height, self)
    local pos1 = vector.new(pos.x - width, pos.y, pos.z - width)
    local pos2 = vector.new(pos.x + width, pos.y + height, pos.z + width)
    for z = pos1.z, pos2.z do
        for y = pos1.y, pos2.y do
            for x = pos1.x, pos2.x do
                local p2 = vector.new(x, y, z)
                local node = minetest.get_node(p2)
                local def = minetest.registered_nodes[node.name]
                if def
                and def.walkable
                and mobkit.get_node_height(p2) > 4.5 then
                    if p2.y > pos2.y then return false end
                    local p3 = vector.new(p2.x, p2.y + 1, p2.z)
                    local node2 = minetest.get_node(p3)
                    local def2 = minetest.registered_nodes[node2.name]
                    if def2
                    and def2.walkable
                    and mobkit.get_node_height(p3) > 4.5 then
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

local function is_liquid(pos)
    local node = minetest.get_node(pos)
    return minetest.registered_nodes[node.name].drawtype == "liquid"
end

local function get_platform(pos, width)
    local pos1 = vector.new(pos.x - width, pos.y - 1, pos.z - width)
    local pos2 = vector.new(pos.x + width, pos.y - 1, pos.z + width)
    for z = pos1.z, pos2.z do
        for x = pos1.x, pos2.x do
            local pltfrm = vector.new(x, pos.y - 1, z)
            local node = minetest.get_node(pltfrm)
            local def = minetest.registered_nodes[node.name]
            if def
            and def.walkable then
                local abv_pltfrm = vector.new(x, pos.y, z)
                local abv_node = minetest.get_node(abv_pltfrm)
                local abv_def = minetest.registered_nodes[abv_node.name]
                if abv_def
                and abv_def.walkable then
                    return "buried"
                end
                return "solid"
            end
        end
    end
    return "air"
end

local function get_neighbor_ground_level(pos, jump_height, fall_height, width)
    local node = minetest.get_node(pos)
    local height = 0
    if get_platform(pos, width) == "solid" then
        return pos
    elseif get_platform(pos, width) == "buried" then
        repeat
            height = height + 1
            if height > jump_height then return nil end
            pos.y = pos.y + 1
            node = minetest.get_node(pos)
        until get_platform(pos, width) == "solid"
        return pos
    else
        repeat
            height = height + 1
            if height > fall_height then return nil end
            pos.y = pos.y - 1
            node = minetest.get_node(pos)
        until get_platform(pos, width) == "solid"
        return {x = pos.x, y = pos.y, z = pos.z}
    end
end

local function round(x) -- Round to nearest multiple of 0.5
	return x + 0.5 - (x + 0.5) % 1
end

function mob_core_pathfinder.find_path(self, pos, endpos, max_length, dtime)
    -- if dtime > 0.1 then
    -- 	return
    -- end
    -- round positions if not done by former functions

    pos = {
        x = floor(pos.x + 0.5),
        y = floor(pos.y + 0.5),
        z = floor(pos.z + 0.5)
    }

    endpos = {
        x = floor(endpos.x + 0.5),
        y = floor(endpos.y + 0.5),
        z = floor(endpos.z + 0.5)
    }

    -- self values
    local self_height = self.height or 1
    local self_width = (self.collisionbox[4] - 0.1 ) or 0.5
    local self_fear_height = self.max_fall or 3
    local self_jump_height = self.jump_height or 1

    -- offset start and end positons

    if not moveable(pos, self_width, self_height, self) then
        local min =
            vector.new(pos.x - self_width, pos.y - 1, pos.z - self_width)
        local max =
            vector.new(pos.x + self_width, pos.y + 1, pos.z + self_width)

        for x = min.x, max.x do
            for y = min.y, max.y do
                for z = min.z, max.z do
                    local npos = vector.new(x, y, z)
                    npos = {
                        x = floor(npos.x + 0.5),
                        y = floor(npos.y + 0.5),
                        z = floor(npos.z + 0.5)
                    }
                    if moveable(npos, self_width, self_height, self) and
                        minetest.line_of_sight(pos, npos) then
                        pos = npos
                        break
                    end
                end
            end
        end
    end

    if not moveable(endpos, self_width, self_height, self) then
        local min =
            vector.new(endpos.x - self_width, endpos.y - 1, endpos.z - self_width)
        local max =
            vector.new(endpos.x + self_width, endpos.y + 1, endpos.z + self_width)

        for x = min.x, max.x do
            for y = min.y, max.y do
                for z = min.z, max.z do
                    local npos = vector.new(x, y, z)
                    npos = {
                        x = floor(npos.x + 0.5),
                        y = floor(npos.y + 0.5),
                        z = floor(npos.z + 0.5)
                    }
                    if moveable(npos, self_width, self_height, self) and
                        minetest.line_of_sight(endpos, npos) then
                            endpos = npos
                        break
                    end
                end
            end
        end
    end

    local start_node = minetest.get_node(pos)
    if string.find(start_node.name, "doors:door") then
        if start_node.param2 == 0 then
            pos.z = pos.z + 1
        elseif start_node.param2 == 1 then
            pos.x = pos.x + 1
        elseif start_node.param2 == 2 then
            pos.z = pos.z - 1
        elseif start_node.param2 == 3 then
            pos.x = pos.x - 1
        end
    end

    local start_time = minetest.get_us_time()
    local start_index = minetest.hash_node_position(pos)
    local target_index = minetest.hash_node_position(endpos)
    local count = 1

    openSet = {}
    closedSet = {}
    -- minetest.set_node(pos, {name = "default:glass"})
    -- minetest.set_node(endpos, {name = "default:glass"})
    -- print(dump(pos))
    -- print(endpos)

    local h_start = get_distance(pos, endpos)
    openSet[start_index] = {
        hCost = h_start,
        gCost = 0,
        fCost = h_start,
        parent = nil,
        pos = pos
    }

    local neighbors_cache = {}

    local current_index
    local current_values
    repeat

        -- Get one index as reference from openSet
        for i, v in pairs(openSet) do
            current_index = i
            current_values = v
            break
        end

        -- Search for lowest fCost
        for i, v in pairs(openSet) do
            if v.fCost < openSet[current_index].fCost or v.fCost ==
                current_values.fCost and v.hCost < current_values.hCost then
                current_index = i
                current_values = v
            end
        end

        openSet[current_index] = nil
        closedSet[current_index] = current_values
        count = count - 1

        if current_index == target_index then
            local path = {}
            repeat
                if not closedSet[current_index] then return end
                table.insert(path, closedSet[current_index].pos)
                current_index = closedSet[current_index].parent
            until start_index == current_index
            table.insert(path, closedSet[current_index].pos)
            local reverse_path = {}
            repeat table.insert(reverse_path, table.remove(path)) until #path ==
                0
            return reverse_path
        end

        local current_pos = current_values.pos

        local neighbors = {}
        local neighbors_index = 1
        for z = -1, 1 do
            for x = -1, 1 do
                local neighbor_pos = {
                    x = current_pos.x + x,
                    y = current_pos.y,
                    z = current_pos.z + z
                }
                local neighbor = minetest.get_node(neighbor_pos)
                local neighbor_ground_level =
                    get_neighbor_ground_level(neighbor_pos, self_jump_height, self_fear_height, self_width)
                local neighbor_clearance = false
                if neighbor_ground_level
                and moveable(neighbor_ground_level, self_width, self_height, self) then
                    if neighbors[neighbors_index - 1]
                    and neighbors[neighbors_index - 1].pos then
                        local parent_pos = neighbors[neighbors_index - 1].pos
                        local move_dir = vec_dir(current_pos, neighbor_ground_level)
                        local jump_dir = vec_dir(parent_pos, neighbor_ground_level)
                        if vector.equals(move_dir, jump_dir) then
                            local neighbor_jump_point = vec_add(neighbor_ground_level, vec_multiply(move_dir, ceil(self_width * 0.5)))
                            neighbor_jump_point = {
                                x = floor(neighbor_jump_point.x + 0.5),
                                y = floor(neighbor_jump_point.y + 0.5),
                                z = floor(neighbor_jump_point.z + 0.5)
                            }
                            if move_dir.y == 0
                            and moveable(neighbor_jump_point, self_width, self_height, self)
                            and get_neighbor_ground_level(neighbor_jump_point, self_jump_height, self_fear_height, self_width) then
                                neighbor_pos = neighbor_jump_point
                                neighbor = minetest.get_node(neighbor_pos)
                                neighbor_ground_level = get_neighbor_ground_level(neighbor_pos, self_jump_height, self_fear_height, self_width)
                            end
                        end
                    end
                    neighbors[neighbors_index] = {
                        hash = minetest.hash_node_position(neighbor_ground_level),
                        pos = neighbor_ground_level,
                        clear = true,
                        walkable = walkable(neighbor)
                    }
                else
                    neighbors[neighbors_index] =
                        {hash = nil, pos = nil, clear = nil, walkable = nil}
                end

                neighbors_index = neighbors_index + 1
            end
        end

        for id, neighbor in pairs(neighbors) do
            -- don't cut corners
            local cut_corner = false
            if id == 1 then
                if not neighbors[id + 1].clear or not neighbors[id + 3].clear or
                    neighbors[id + 1].walkable or neighbors[id + 3].walkable then
                    cut_corner = true
                end
            elseif id == 3 then
                if not neighbors[id - 1].clear or not neighbors[id + 3].clear or
                    neighbors[id - 1].walkable or neighbors[id + 3].walkable then
                    cut_corner = true
                end
            elseif id == 7 then
                if not neighbors[id + 1].clear or not neighbors[id - 3].clear or
                    neighbors[id + 1].walkable or neighbors[id - 3].walkable then
                    cut_corner = true
                end
            elseif id == 9 then
                if not neighbors[id - 1].clear or not neighbors[id - 3].clear or
                    neighbors[id - 1].walkable or neighbors[id - 3].walkable then
                    cut_corner = true
                end
            end
            if neighbor.hash ~= current_index and not closedSet[neighbor.hash] and
                neighbor.clear and not cut_corner then
                local move_cost_to_neighbor =
                    current_values.gCost +
                        get_distance_to_neighbor(current_values.pos,
                                                 neighbor.pos)
                local gCost = 0
                if openSet[neighbor.hash] then
                    gCost = openSet[neighbor.hash].gCost
                end
                if move_cost_to_neighbor < gCost or not openSet[neighbor.hash] then
                    if not openSet[neighbor.hash] then
                        count = count + 1
                    end
                    local hCost = get_distance(neighbor.pos, endpos)
                    openSet[neighbor.hash] =
                        {
                            gCost = move_cost_to_neighbor,
                            hCost = hCost,
                            fCost = move_cost_to_neighbor + hCost,
                            parent = current_index,
                            pos = neighbor.pos
                        }
                end
            end
        end
        if count > max_length then
            return
        end
        if (minetest.get_us_time() - start_time) / 1000 > 100 - dtime * 50 then
            return
        end
    until count < 1
    return {pos}
end

function mob_core.find_liquid_path(self, pos, endpos, max_length)
    if not endpos then return end

    local dtime = self.dtime

    pos = {
        x = floor(pos.x + 0.5),
        y = floor(pos.y + 0.5),
        z = floor(pos.z + 0.5)
    }

    endpos = {
        x = floor(endpos.x + 0.5),
        y = floor(endpos.y + 0.5),
        z = floor(endpos.z + 0.5)
    }

    -- self values
    local self_height =
        ceil(self.collisionbox[5] - self.collisionbox[2]) or 2
    local self_width = self.collisionbox[4] or 1
    local self_fear_height = self.max_fall or 3
    local self_jump_height = self.jump_height or 1

    -- offset start and end positons

    if not moveable(pos, self_width, self_height, self)
    or not is_liquid(pos) then

        local min = vector.new(pos.x - self_width - 1, pos.y,
                               pos.z - self_width - 1)
        local max = vector.new(pos.x - self_width + 1, pos.y,
                               pos.z - self_width + 1)

        for x = min.x, max.x do
            for y = min.y, max.y do
                for z = min.z, max.z do
                    local npos = vector.new(x, y, z)
                    if moveable(npos, self_width, self_height, self)
                    and is_liquid(npos) then
                        pos = npos
                        break
                    end
                end
            end
        end
    end

    if not moveable(endpos, self_width, self_height, self)
    or not is_liquid(endpos) then

        local min = vector.new(endpos.x - self_width - 1, endpos.y,
        endpos.z - self_width - 1)
        local max = vector.new(endpos.x - self_width + 1, endpos.y,
        endpos.z - self_width + 1)

        for x = min.x, max.x do
            for y = min.y, max.y do
                for z = min.z, max.z do
                    local npos = vector.new(x, y, z)
                    if moveable(npos, self_width, self_height, self)
                    and not is_liquid(npos) then
                        endpos = npos
                        break
                    end
                end
            end
        end
    end

    local start_time = minetest.get_us_time()
    local start_index = minetest.hash_node_position(pos)
    local target_index = minetest.hash_node_position(endpos)
    local count = 1

    openSet = {}
    closedSet = {}

    local h_start = get_distance(pos, endpos)
    openSet[start_index] = {
        hCost = h_start,
        gCost = 0,
        fCost = h_start,
        parent = nil,
        pos = pos
    }

    local neighbors_cache = {}

    repeat
        local current_index
        local current_values

        -- Get one index as reference from openSet
        for i, v in pairs(openSet) do
            current_index = i
            current_values = v
            break
        end

        -- Search for lowest fCost
        for i, v in pairs(openSet) do
            if v.fCost < openSet[current_index].fCost or v.fCost ==
                current_values.fCost and v.hCost < current_values.hCost then
                current_index = i
                current_values = v
            end
        end

        openSet[current_index] = nil
        closedSet[current_index] = current_values
        count = count - 1

        if current_index == target_index then
            -- ~ minetest.chat_send_all("Found path in " .. (minetest.get_us_time() - start_time) / 1000 .. "ms")
            local path = {}
            repeat
                if not closedSet[current_index] then return end
                table.insert(path, closedSet[current_index].pos)
                current_index = closedSet[current_index].parent
            until start_index == current_index
            table.insert(path, closedSet[current_index].pos)
            local reverse_path = {}
            repeat table.insert(reverse_path, table.remove(path)) until #path ==
                0
            -- minetest.chat_send_all("Found path in " .. (minetest.get_us_time() - start_time) / 1000 .. "ms. " .. "Path length: " .. #reverse_path)
            return reverse_path
        end

        local current_pos = current_values.pos

        local neighbors = {}
        local neighbors_index = 1
        for z = -1, 1 do
            for y = -1, 1 do
                for x = -1, 1 do
                    local neighbor_pos =
                        {
                            x = current_pos.x + x,
                            y = current_pos.y + y,
                            z = current_pos.z + z
                        }

                    if moveable(current_pos, self_width, self_height, self)
                    and is_liquid(current_pos)
                    and moveable(neighbor_pos, self_width, self_height, self)
                    and is_liquid(neighbor_pos) then

                        local neighbor = minetest.get_node(neighbor_pos)

                        local neighbor_ground_level = get_neighbor_ground_level(neighbor_pos, self_width, self_height, self_width)

                        if neighbor_ground_level then
                            if neighbors[neighbors_index - 1]
                            and neighbors[neighbors_index - 1].pos then
                                local parent_pos = neighbors[neighbors_index - 1].pos
                                local move_dir = vec_dir(current_pos, neighbor_ground_level)
                                local jump_dir = vec_dir(parent_pos, neighbor_ground_level)
                                if vector.equals(move_dir, jump_dir) then
                                    local neighbor_jump_point = vec_add(neighbor_ground_level, vec_multiply(move_dir, ceil(self_width * 0.5)))
                                    neighbor_jump_point = {
                                        x = floor(neighbor_jump_point.x + 0.5),
                                        y = floor(neighbor_jump_point.y + 0.5),
                                        z = floor(neighbor_jump_point.z + 0.5)
                                    }
                                    if move_dir.y == 0
                                    and moveable(neighbor_jump_point, self_width, self_height, self)
                                    and is_liquid(neighbor_jump_point)
                                    and get_neighbor_ground_level(neighbor_jump_point, self_jump_height, self_fear_height, self_width) then
                                        neighbor_pos = neighbor_jump_point
                                        neighbor = minetest.get_node(neighbor_pos)
                                        neighbor_ground_level = get_neighbor_ground_level(neighbor_pos, self_jump_height, self_fear_height, self_width)
                                    end
                                end
                            end
                            neighbors[neighbors_index] = {
                                hash = minetest.hash_node_position(neighbor_ground_level),
                                pos = neighbor_ground_level,
                                clear = true,
                                walkable = walkable(neighbor, neighbor_pos, current_pos)
                            }
                        else
                            neighbors[neighbors_index] = {
                                hash = minetest.hash_node_position(neighbor_pos),
                                pos = neighbor_pos,
                                clear = true,
                                walkable = walkable(neighbor, neighbor_pos, current_pos)
                            }
                        end
                    else
                        neighbors[neighbors_index] =
                            {hash = nil, pos = nil, clear = nil, walkable = nil}
                    end

                    neighbors_index = neighbors_index + 1
                end
            end
        end

        for id, neighbor in pairs(neighbors) do
            -- don't cut corners
            local cut_corner = false
            if id == 1 then
                if not neighbors[id + 1].clear or not neighbors[id + 3].clear or
                    neighbors[id + 1].walkable or neighbors[id + 3].walkable then
                    cut_corner = true
                end
            elseif id == 3 then
                if not neighbors[id - 1].clear or not neighbors[id + 3].clear or
                    neighbors[id - 1].walkable or neighbors[id + 3].walkable then
                    cut_corner = true
                end
            elseif id == 7 then
                if not neighbors[id + 1].clear or not neighbors[id - 3].clear or
                    neighbors[id + 1].walkable or neighbors[id - 3].walkable then
                    cut_corner = true
                end
            elseif id == 9 then
                if not neighbors[id - 1].clear or not neighbors[id - 3].clear or
                    neighbors[id - 1].walkable or neighbors[id - 3].walkable then
                    cut_corner = true
                end
            end
            if neighbor.hash ~= current_index and not closedSet[neighbor.hash] and
                neighbor.clear and not cut_corner then
                local move_cost_to_neighbor =
                    current_values.gCost +
                        get_distance(current_values.pos,
                                                 neighbor.pos)
                local gCost = 0
                if openSet[neighbor.hash] then
                    gCost = openSet[neighbor.hash].gCost
                end
                if move_cost_to_neighbor < gCost or not openSet[neighbor.hash] then
                    if not openSet[neighbor.hash] then
                        count = count + 1
                    end
                    local hCost = get_distance(neighbor.pos, endpos)
                    openSet[neighbor.hash] =
                        {
                            gCost = move_cost_to_neighbor,
                            hCost = hCost,
                            fCost = move_cost_to_neighbor + hCost,
                            parent = current_index,
                            pos = neighbor.pos
                        }
                end
            end
        end
        if count > 500 then return end
        if (minetest.get_us_time() - start_time) / 1000 > 100 - dtime * 50 then
            return
        end
    until count < 1
    return {pos}
end

local function get_neighbor_flyable_level(pos, min_width, min_height, self)
    local node = minetest.get_node(pos)
    local height = 0
    if walkable(node) then
        repeat
            height = height + 1
            if height > min_height then return nil end
            pos.y = pos.y + 1
            node = minetest.get_node(pos)
        until not walkable(node) and moveable(pos, min_width, min_height, self)
        return pos
    end
    return pos
end
function mob_core.find_aerial_path(self, pos, endpos, max_length)
    if not endpos then return end

    local dtime = self.dtime
    
    pos = {
        x = floor(pos.x + 0.5),
        y = floor(pos.y + 0.5),
        z = floor(pos.z + 0.5)
    }

    endpos = {
        x = floor(endpos.x + 0.5),
        y = floor(endpos.y + 0.5),
        z = floor(endpos.z + 0.5)
    }

    -- self values
    local self_height = self.height or 1
    local self_width = self.collisionbox[4] or 0.5
    local self_fear_height = self.max_fall or 3
    local self_jump_height = self.jump_height or 1

    -- offset start and end positons

    if not moveable(pos, self_width, self_height, self) then

        local min = vector.new(pos.x - self_width - 1, pos.y,
                               pos.z - self_width - 1)
        local max = vector.new(pos.x - self_width + 1, pos.y,
                               pos.z - self_width + 1)

        for x = min.x, max.x do
            for y = min.y, max.y do
                for z = min.z, max.z do
                    local npos = vector.new(x, y, z)
                    if moveable(npos, self_width, self_height, self) then
                        pos = npos
                        break
                    end
                end
            end
        end
    end

    local target_node = minetest.get_node(endpos)

    if not moveable(endpos, self_width, self_height, self) then

        local min = vector.new(endpos.x - self_width - 1, endpos.y,
        endpos.z - self_width - 1)
        local max = vector.new(endpos.x - self_width + 1, endpos.y,
        endpos.z - self_width + 1)

        for x = min.x, max.x do
            for y = min.y, max.y do
                for z = min.z, max.z do
                    local npos = vector.new(x, y, z)
                    if moveable(npos, self_width, self_height, self) then
                        endpos = npos
                        break
                    end
                end
            end
        end
    end

    local start_time = minetest.get_us_time()
    local start_index = minetest.hash_node_position(pos)
    local target_index = minetest.hash_node_position(endpos)
    local count = 1

    openSet = {}
    closedSet = {}

    local h_start = get_distance_to_neighbor(pos, endpos)
    openSet[start_index] = {
        hCost = h_start,
        gCost = 0,
        fCost = h_start,
        parent = nil,
        pos = pos
    }

    local neighbors_cache = {}

    repeat
        local current_index
        local current_values

        -- Get one index as reference from openSet
        for i, v in pairs(openSet) do
            current_index = i
            current_values = v
            break
        end

        -- Search for lowest fCost
        for i, v in pairs(openSet) do
            if v.fCost < openSet[current_index].fCost or v.fCost ==
                current_values.fCost and v.hCost < current_values.hCost then
                current_index = i
                current_values = v
            end
        end

        openSet[current_index] = nil
        closedSet[current_index] = current_values
        count = count - 1

        if current_index == target_index then
            -- ~ minetest.chat_send_all("Found path in " .. (minetest.get_us_time() - start_time) / 1000 .. "ms")
            local path = {}
            repeat
                if not closedSet[current_index] then return end
                table.insert(path, closedSet[current_index].pos)
                current_index = closedSet[current_index].parent
            until start_index == current_index
            table.insert(path, closedSet[current_index].pos)
            local reverse_path = {}
            repeat table.insert(reverse_path, table.remove(path)) until #path ==
                0
            return reverse_path
        end

        local current_pos = current_values.pos

        local neighbors = {}
        local neighbors_index = 1
        for z = -1, 1 do
            for y = -1, 1 do
                for x = -1, 1 do
                    local neighbor_pos = {
                        x = current_pos.x + x,
                        y = current_pos.y + y,
                        z = current_pos.z + z
                    }
                    if moveable(neighbor_pos, self_width, self_height, self) then
                        local neighbor = minetest.get_node(neighbor_pos)
                        local neighbor_flyable_level = get_neighbor_flyable_level(neighbor_pos, self_width, self_height, self)
                        if neighbor_flyable_level then
                            neighbors[neighbors_index] = {
                                hash = minetest.hash_node_position(neighbor_flyable_level),
                                pos = neighbor_flyable_level,
                                clear = true,
                                walkable = walkable(neighbor)
                            }
                        else
                            neighbors[neighbors_index] =
                                {hash = nil, pos = nil, clear = nil, walkable = nil}
                        end
                    else
                        neighbors[neighbors_index] =
                            {hash = nil, pos = nil, clear = nil, walkable = nil}
                    end

                    neighbors_index = neighbors_index + 1
                end
            end
        end

        for id, neighbor in pairs(neighbors) do
            -- don't cut corners
            local cut_corner = false
            if id == 1 then
                if not neighbors[id + 1].clear or not neighbors[id + 3].clear or
                    neighbors[id + 1].walkable or neighbors[id + 3].walkable then
                    cut_corner = true
                end
            elseif id == 3 then
                if not neighbors[id - 1].clear or not neighbors[id + 3].clear or
                    neighbors[id - 1].walkable or neighbors[id + 3].walkable then
                    cut_corner = true
                end
            elseif id == 7 then
                if not neighbors[id + 1].clear or not neighbors[id - 3].clear or
                    neighbors[id + 1].walkable or neighbors[id - 3].walkable then
                    cut_corner = true
                end
            elseif id == 9 then
                if not neighbors[id - 1].clear or not neighbors[id - 3].clear or
                    neighbors[id - 1].walkable or neighbors[id - 3].walkable then
                    cut_corner = true
                end
            end
            if neighbor.hash ~= current_index and not closedSet[neighbor.hash] and
                neighbor.clear and not cut_corner then
                local move_cost_to_neighbor =
                    current_values.gCost +
                    get_distance_to_neighbor(current_values.pos,
                                                 neighbor.pos)
                local gCost = 0
                if openSet[neighbor.hash] then
                    gCost = openSet[neighbor.hash].gCost
                end
                if move_cost_to_neighbor < gCost or not openSet[neighbor.hash] then
                    if not openSet[neighbor.hash] then
                        count = count + 1
                    end
                    local hCost = get_distance_to_neighbor(neighbor.pos, endpos)
                    openSet[neighbor.hash] =
                        {
                            gCost = move_cost_to_neighbor,
                            hCost = hCost,
                            fCost = move_cost_to_neighbor + hCost,
                            parent = current_index,
                            pos = neighbor.pos
                        }
                end
            end
        end
        if count > 500 then return end
        if (minetest.get_us_time() - start_time) / 1000 > 100 - dtime * 50 then
            return
        end
    until count < 1
    return {pos}
end