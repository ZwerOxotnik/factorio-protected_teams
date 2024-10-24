---@class ProtectedTeams : module
local M = {}


--#region Global data

---@class mod_data
---@type table<string, any>
local _mod_data

-- {[player index] = true}
---@class vehicles_with_player
---@type table<uint, true>
local _vehicles_with_player

-- {[force index] = true}
---@class forced_protected_teams
---@type table<uint, true>
local _forced_protected_teams

-- {[force index] = radius}
---@class radius_protection
---@type table<uint, double>
local _protection_radius

-- {[force index] = radius}
---@class build_radius_protection
---@type table<uint, double>
local _build_protection_radius

-- {[force index] = radius}
---@class max_radius_protection
---@type table<uint, double>
local _max_radius_protection

-- {[force index] = speed}
---@class speed_protection
---@type table<uint, double>
local _speed_protection

-- {[force index] = uint}
---@class planned_disabled_protection
---@type table<uint, uint>
local _planned_disabled_protection

---@class time_protection
---@field start_tick uint
---@field ticks_of_protection uint

-- {[force index] = speed}
---@type table<uint, time_protection>
local _time_protection


---@class teams_data
---@field ticks_used_protection_for_entering uint
---@field base_surface LuaSurface?
---@field base_position MapPosition.0?

---@type table<uint, teams_data>
local _teams_data


-- {[surface index] = {[force index] = {number, number}}}
---@class main_bases
---@type table<uint, table<uint, MapPosition.1>>
local _main_bases


---@class main_base_rendering
---@field [1] uint64 # rendering build zone id for own team
---@field [2] uint64 # rendering build zone id for enemy teams
---@field [3] uint64 # rendering build zone id for neutral teams
---@field [4] uint64 # rendering build zone id for friendly teams
---@field [5] uint64? # rendering protection zone id for own team
---@field [6] uint64? # rendering protection zone id for enemy teams
---@field [7] uint64? # rendering protection zone id for neutral teams
---@field [8] uint64? # rendering protection zone id for friendly teams

-- {[force index] = main_base_rendering}
---@class main_bases
---@type table<uint, main_base_rendering>
local _main_base_rendering

--#endregion


--#region Constants
local tremove = table.remove
local call = remote.call
local cos = math.cos
local sin = math.sin
local atan2 = math.atan2
local get_render_object_by_id = rendering.get_object_by_id
local print_to_rcon = rcon.print
local DESTROY_PARAM = {raise_destroy = true} --[[@as LuaEntity.destroy_param]]
local _flying_anti_build_text_param = {
	text = {"protected_teams.warning_not_your_team_build_zone"}, create_at_cursor=true,
	color = {1, 0, 0}, time_to_live = 210,
	speed = 0.1
}
local draw_text = rendering.draw_text
local _render_text_position = {0, 0} --[[@as MapPosition.1]]
---@type ForceIdentification[]
local _render_target_force = {nil}
local _render_anti_build_text_param = {
	text = {"protected_teams.warning_not_your_team_build_zone"},
	target = _render_text_position,
	surface = nil,
	forces = _render_target_force,
	scale = 1,
	time_to_live = 210,
	color = {200, 0, 0}
}


--#endregion


--#region Global functions


---@param target? LuaForce|LuaPlayer # From whom the data?
---@param getter? LuaForce|LuaPlayer # Print to whom? (game by default)
function print_force_data(target, getter)
	if getter then
		if not getter.valid then
			log("Invalid object")
			return
		end
	else
		getter = game
	end

	local index
	local object_name = target.object_name
	if object_name == "LuaPlayer" then
		index = target.force_index
	elseif object_name == "LuaForce" then
		index = target.index
	else
		log("Invalid type")
		return
	end

	local print_to_target = getter.print
	print_to_target('')
	--TODO: change
	print_to_target("planned_disabled_protection:" .. serpent.line(_planned_disabled_protection[index]))
	print_to_target("speed_protection:" .. serpent.line(_speed_protection[index]))
	print_to_target("max_radius_protection:"  .. serpent.line(_max_radius_protection[index]))
	print_to_target("forced_protected_teams:"  .. serpent.line(_forced_protected_teams[index]))
	print_to_target("build_radius_protection:"  .. serpent.line(_build_protection_radius[index]))
	print_to_target("radius_protection:"  .. serpent.line(_protection_radius[index]))
	print_to_target("time_protection:"  .. serpent.line(_time_protection[index]))
	print_to_target("teams_data:"  .. serpent.line(_teams_data[index]))
	print_to_target("main_base_rendering:"  .. serpent.line(_main_base_rendering[index]))
end


---@param local_data table
---@param global_data_name string
---@param receiver table?
---@return boolean
function check_local_and_global_data(local_data, global_data_name, receiver)
	if (type(global_data_name) == "string" and local_data ~= storage.PTZO[global_data_name]) then
		local message = string.format("!WARNING! Desync has been detected in __%s__ %s. Please report and send log files to %s and try to load your game again or use /sync", script.mod_name, "mod_data[\"" .. global_data_name .. "\"]", "ZwerOxotnik")
		log(message)
		if game and (game.is_multiplayer() == false or receiver) then
			message = {"EasyAPI.report-desync",
				script.mod_name, "mod_data[\"" .. global_data_name .. "\"]", "ZwerOxotnik"
			}
			receiver = receiver or game
			receiver.print(message)
		end
		return true
	end
	return false
end


---@param receiver table?
function detect_desync(receiver)
	check_local_and_global_data(_planned_disabled_protection, "planned_disabled_protection", receiver)
	check_local_and_global_data(_speed_protection, "speed_protection", receiver)
	check_local_and_global_data(_max_radius_protection, "max_radius_protection", receiver)
	check_local_and_global_data(_forced_protected_teams, "forced_protected_teams", receiver)
	check_local_and_global_data(_build_protection_radius, "build_radius_protection", receiver)
	check_local_and_global_data(_protection_radius, "radius_protection", receiver)
	check_local_and_global_data(_time_protection, "time_protection", receiver)
	check_local_and_global_data(_teams_data, "teams_data", receiver)
	check_local_and_global_data(_main_base_rendering, "main_base_rendering", receiver)
end


---@param target_force LuaForce
---@return LuaForce[], LuaForce[], LuaForce[] # enemy forces, neutral forces, ally forces
function get_forces_by_relations(target_force)
	---@type LuaForce[]
	local enemy_forces = {nil}
	---@type LuaForce[]
	local neutral_forces = {nil}
	---@type LuaForce[]
	local ally_forces = {}

	for _, force in pairs(game.forces) do
		if not (force.valid and target_force ~= force) then
			goto continue
		end
		if target_force.is_enemy(force) then
			enemy_forces[#enemy_forces+1] = force
		elseif target_force.get_friend(force) then -- tricky case
			ally_forces[#ally_forces+1] = force
		else
			neutral_forces[#neutral_forces+1] = force
		end
	    ::continue::
	end

	return enemy_forces, neutral_forces, ally_forces
end


--#endregion


--#region Function for RCON

---@param name string
function getRconData(name)
	print_to_rcon(helpers.table_to_json(_mod_data[name]))
end

---@param name string
---@param force LuaForce
function getRconForceData(name, force)
	if not force.valid then return end
	print_to_rcon(helpers.table_to_json(_mod_data[name][force.index]))
end

---@param name string
---@param force_index integer
function getRconForceDataByIndex(name, force_index)
	print_to_rcon(helpers.table_to_json(_mod_data[name][force_index]))
end

--#endregion


--#region utils

-- local __simple_vehicles = {car = true, ["spider-vehicle"] = true}
function check_vehicles_data()
	for i=#_vehicles_with_player, 1, -1 do
		local entity = _vehicles_with_player[i]
		if not entity.valid then
			tremove(_vehicles_with_player, i)
			goto continue
		end
		local driver, passenger

		if entity.train then
			passenger = entity.train.passengers[1]
		-- elseif __simple_vehicles[entity.type] then
		else

			driver = entity.get_driver()
			if driver and driver.valid and driver.is_player() then
				goto continue
			end
			passenger = entity.get_passenger()
		end
		if passenger and passenger.valid and passenger.is_player() then
			goto continue
		end
		tremove(_vehicles_with_player, i)
		::continue::
	end
end


---@param entity LuaEntity
function M.add_vehicle(entity)
	for i=1, #_vehicles_with_player do
		if _vehicles_with_player[i] == entity then
			return
		end
	end
	_vehicles_with_player[#_vehicles_with_player+1] = entity
end


function update_bases_rendering()
	local forces = game.forces
	for force_index, ids in pairs(_main_base_rendering) do
		local force = forces[force_index]
		if not (force and force.valid) then
			goto continue
		end

		local enemies, neutrals, allies = get_forces_by_relations(game.forces[force_index])
		local id = ids[2]
		if id and get_render_object_by_id(id).valid then
			rendering.set_visible(id, (#enemies ~= 0))
		end
		id = ids[3]
		if id and get_render_object_by_id(id).valid then
			rendering.set_visible(id, (#neutrals ~= 0))
		end
		id = ids[4]
		if id and get_render_object_by_id(id).valid then
			rendering.set_visible(id, (#allies ~= 0))
		end
		id = ids[6]
		if id and get_render_object_by_id(id).valid then
			rendering.set_visible(id, (#enemies ~= 0))
		end
		id = ids[7]
		if id and get_render_object_by_id(id).valid then
			rendering.set_visible(id, (#neutrals ~= 0))
		end
		id = ids[8]
		if id and get_render_object_by_id(id).valid then
			rendering.set_visible(id, (#allies ~= 0))
		end
	    ::continue::
	end
end


---@param index uint
function init_team_data(index)
	local max_radius = _max_radius_protection[index]
	_max_radius_protection[index] = _max_radius_protection[index] or settings.global["PTZO_default_max_radius_protection"].value
	_build_protection_radius[index] = _build_protection_radius[index] or settings.global["PTZO_default_build_radius_protection"].value
	if max_radius == nil and settings.global["PTZO_init_time_protection"].value > 0 then
		enable_protection(index, settings.global["PTZO_init_time_protection"].value * 60 * 60)
	end
end


---@param force_index uint
function destroy_team_base_rendering(force_index)
	local rendering_ids = _main_base_rendering[force_index]
	if not rendering_ids then return end

	for i=1, 8 do
		local id = rendering_ids[i]
		if id == nil then
			break
		end
		local render_object = get_render_object_by_id(id)
		if render_object.valid then
			render_object.destroy()
		end
	end
end


---@param force_index uint
---@param is_force_exist boolean?
function remove_team_data(force_index, is_force_exist)
	destroy_team_base_rendering(force_index)

	_planned_disabled_protection[force_index] = nil
	_max_radius_protection[force_index]   = nil
	_build_protection_radius[force_index] = nil
	_time_protection[force_index]   = nil
	_speed_protection[force_index]  = nil
	_protection_radius[force_index] = nil
	local team_data = _teams_data[force_index]
	if team_data and not is_force_exist then
		_teams_data[force_index] = nil
	else
		team_data.base_position = nil
		team_data.base_surface  = nil
	end
	for _, forces_data in pairs(_main_bases) do
		forces_data[force_index] = nil
	end
	_main_base_rendering[force_index] = nil
end


local _render_tick = -1
---@param entity LuaEntity
---@param player LuaPlayer?
local function destroy_entity(entity, player)
	if player and player.valid then
		if _render_tick ~= game.tick then
			player.create_local_flying_text(_flying_anti_build_text_param)
		end
		player.mine_entity(entity, true) -- forced mining
		return
	end

	-- Show warning text
	_render_target_force[1] = entity.force
	_render_anti_build_text_param.surface = entity.surface
	local ent_pos = entity.position
	_render_text_position[1] = ent_pos.x
	_render_text_position[2] = ent_pos.y
	draw_text(_render_anti_build_text_param)

	entity.destroy(DESTROY_PARAM)
end
M.destroy_entity = destroy_entity


---@param force_index uint
---@param is_forced boolean?
function disable_protection(force_index, is_forced)
	if _time_protection[force_index] == nil then return end

	_time_protection[force_index]   = nil
	_protection_radius[force_index] = nil
	_speed_protection[force_index]  = nil
	_planned_disabled_protection[force_index] = nil
	local rendering_ids = _main_base_rendering[force_index]
	for i=5, 8 do
		local id = rendering_ids[i]
		if id == nil then
			break
		end
		local render_object = get_render_object_by_id(id)
		if render_object.valid then
			render_object.destroy()
		end
	end
end


---@param force_index uint
---@param duration_in_ticks uint
function enable_protection(force_index, duration_in_ticks)
	local time_data = _time_protection[force_index]
	if time_data then
		time_data.ticks_of_protection = duration_in_ticks
		return
	end

	-- Set protection data
	_time_protection[force_index] = {
		start_tick = game.tick,
		ticks_of_protection = duration_in_ticks
	}
	_speed_protection[force_index]  = _speed_protection[force_index]  or settings.global["PTZO_default_speed_protection"].value
	_protection_radius[force_index] = _protection_radius[force_index] or settings.global["PTZO_default_radius_protection"].value

	-- Delete rendering of protection zone
	local rendering_ids = _main_base_rendering[force_index]
	for i=5, 8 do
		local id = rendering_ids[i]
		if id == nil then
			break
		end
		local render_object = get_render_object_by_id(id)
		if render_object.valid then
			render_object.destroy()
		end
	end

	-- Create rendering of protection zone
	local force = game.forces[force_index]
	local enemies, neutrals, allies = get_forces_by_relations(force)
	local team_data = _teams_data[force_index]
	local render_data = {
		target  = team_data.base_position,
		surface = team_data.base_surface,
		radius  = _protection_radius[force_index],
		color   = {255, 165, 0},
		forces  = {force},
		filled  = false,
		width   = 6,
		draw_on_ground = true
	} --[[@as LuaRendering.draw_circle_param]]
	_main_base_rendering[force_index][5] = rendering.draw_circle(render_data).id
	render_data.color   = {1, 0, 0}
	render_data.forces  = enemies
	render_data.visible = (#enemies ~= 0)
	_main_base_rendering[force_index][6] = rendering.draw_circle(render_data).id
	render_data.color   = {1, 1, 1}
	render_data.forces  = neutrals
	render_data.visible = (#neutrals ~= 0)
	_main_base_rendering[force_index][7] = rendering.draw_circle(render_data).id
	render_data.color   = {0, 1, 0}
	render_data.forces  = allies
	render_data.visible = (#allies ~= 0)
	_main_base_rendering[force_index][8] = rendering.draw_circle(render_data).id
end


function clear_invalid_forces()
	local forces = game.forces
	for _, data in ipairs({_forced_protected_teams,
		_protection_radius, _build_protection_radius,
		_max_radius_protection, _speed_protection,
		_planned_disabled_protection, _time_protection,
		_main_base_rendering, _teams_data})
	do
		for force_index in pairs(data) do
			local force = forces[force_index]
			if not (force and force.valid) then
				data[force_index] = nil
			end
		end
	end

	-- TODO: check _main_bases
end


function clear_invalid_data()
	clear_invalid_forces()
end

--#endregion


--#region Functions of events

function M.on_player_joined_game(event)
	local player = game.get_player(event.player_index)
	if not (player and player.valid) then return end

	if #game.connected_players == 1 then
		detect_desync()
	end


	local force = player.force
	if #force.connected_players == 0 and
		not _forced_protected_teams[force.index] and
		settings.global["PTZO_is_offline_protection_on"].value
	then
		disable_protection(force.index)
	end

	local surface = player.surface
	local bases_position = _main_bases[surface.index]
	if bases_position == nil then return end

	local player_force_index = force.index
	local ent_pos = player.position
	local ent_x = ent_pos.x
	local ent_y = ent_pos.y
	for force_index, base_position in pairs(bases_position) do
		local protection_radius = _protection_radius[force_index]
		if protection_radius == nil then
			goto continue
		end

		if force_index == player_force_index then
			goto continue
		end

		local center_x = base_position[1]
		local center_y = base_position[2]
		local xdiff = ent_x - center_x
		local ydiff = ent_y - center_y
		-- Teleport outside of radius
		if (xdiff * xdiff + ydiff * ydiff)^0.5 <= protection_radius then
			local r = protection_radius + 2
			local t = atan2(ydiff, xdiff)
			_teleport_position.x = r * cos(t) + center_x
			_teleport_position.y = r * sin(t) + center_y
			player.teleport(_teleport_position)
			return
		end
		::continue::
	end
end


---@param event on_player_left_game
function M.on_player_left_game(event)
	local player = game.get_player(event.player_index)
	if not (player and player.valid) then return end

	local force = player.force
	if #force.connected_players == 0 and
		not _forced_protected_teams[force.index] and
		settings.global["PTZO_is_offline_protection_on"].value
	then
		enable_protection(force.index) -- TODO: fix
	end
end

---@param event on_forces_merging
function M.on_forces_merging(event)
	update_bases_rendering()
end

---@param event on_robot_built_entity
M.on_robot_built_entity = function(event)
	local entity = event.entity
	if not entity.valid then return end
	local surface = entity.surface
	local bases_position = _main_bases[surface.index]
	if bases_position == nil then return end

	local force = entity.force
	local entity_force_index = force.index
	local ent_pos = entity.position
	local ent_x = ent_pos.x
	local ent_y = ent_pos.y
	for force_index, base_position in pairs(bases_position) do
		if force_index == entity_force_index then
			goto continue
		end

		local radius_protection = _build_protection_radius[force_index]
		local xdiff = ent_x - base_position[1]
		local ydiff = ent_y - base_position[2]
		-- Destroy if in radius
		if (xdiff * xdiff + ydiff * ydiff)^0.5 <= radius_protection then
			destroy_entity(entity)

			-- Show warning text
			_render_target_force[1] = force
			_render_text_position[1] = ent_x
			_render_text_position[2] = ent_y
			_render_anti_build_text_param.surface = surface
			draw_text(_render_anti_build_text_param)
			return
		end
		::continue::
	end
end


---@param event on_built_entity
M.on_built_entity = function(event)
	local entity = event.entity
	if not entity.valid then return end
	local surface = entity.surface
	local bases_position = _main_bases[surface.index]
	if bases_position == nil then return end

	local force = entity.force
	local entity_force_index = force.index
	local ent_pos = event.position
	local ent_x = ent_pos.x
	local ent_y = ent_pos.y
	for force_index, base_position in pairs(bases_position) do
		if force_index == entity_force_index then
			goto continue
		end

		local radius_protection = _build_protection_radius[force_index]
		local xdiff = ent_x - base_position[1]
		local ydiff = ent_y - base_position[2]
		-- Destroy if in radius
		if (xdiff * xdiff + ydiff * ydiff)^0.5 <= radius_protection then
			destroy_entity(entity, game.get_player(event.player_index))
			return
		end
		::continue::
	end
end


---@param event on_pre_build
M.on_pre_build = function(event)
	local player = game.get_player(event.player_index)
	if not (player and player.valid) then return end
	local surface = player.surface
	local bases_position = _main_bases[surface.index]
	if bases_position == nil then return end

	local force = player.force
	local entity_force_index = force.index
	local ent_pos = event.position
	local ent_x = ent_pos.x
	local ent_y = ent_pos.y
	for force_index, base_position in pairs(bases_position) do
		if force_index == entity_force_index then
			goto continue
		end

		local radius_protection = _build_protection_radius[force_index]
		local xdiff = ent_x - base_position[1]
		local ydiff = ent_y - base_position[2]
		-- Destroy if in radius
		if (xdiff * xdiff + ydiff * ydiff)^0.5 <= radius_protection then
			player.clear_cursor()
			-- Show warning text
			player.create_local_flying_text(_flying_anti_build_text_param)
			return
		end
		::continue::
	end
end


---@param event script_raised_built
-- M.script_raised_built = function(event)
-- 	local entity = event.entity
-- 	if not entity.valid then return end
-- end


---@param event on_entity_cloned
-- function M.on_entity_cloned(event)
-- 	local destination = event.destination
-- 	if not destination.valid then return end
-- end


---@param event on_player_changed_force
-- function M.on_player_changed_force(event)
-- 	local player_index = event.player_index
-- 	local player = game.get_player(player_index)
-- 	if not (player and player.valid) then return end

-- 	local force_index = player.force_index
-- end


---@param event on_player_driving_changed_state
M.on_player_driving_changed_state = function(event)
	local player = game.get_player(event.player_index)
	if not (player and player.valid) then return end

	check_vehicles_data()

	local entity = event.entity
	if entity and entity.valid and
		player.vehicle and player.vehicle == entity
	then
		M.add_vehicle(entity)
	end
end


---@type MapPosition.0
_teleport_position = {x = 0, y = 0}
---@param event on_player_changed_position
function M.on_player_changed_position(event)
	local player = game.get_player(event.player_index)
	if not (player and player.valid) then return end

	local surface = player.surface
	local bases_position = _main_bases[surface.index]
	if bases_position == nil then return end

	local force = player.force
	local player_force_index = force.index
	local ent_pos = player.position
	local ent_x = ent_pos.x
	local ent_y = ent_pos.y
	for force_index, base_position in pairs(bases_position) do
		local protection_radius = _protection_radius[force_index]
		if protection_radius == nil then
			goto continue
		end

		if force_index == player_force_index then
			goto continue
		end

		local center_x = base_position[1]
		local center_y = base_position[2]
		local xdiff = ent_x - center_x
		local ydiff = ent_y - center_y
		-- Teleport outside of radius
		if (xdiff * xdiff + ydiff * ydiff)^0.5 <= protection_radius then
			local r = protection_radius + 2
			local t = atan2(ydiff, xdiff)
			_teleport_position.x = r * cos(t) + center_x
			_teleport_position.y = r * sin(t) + center_y
			player.teleport(_teleport_position)
			return
		end
		::continue::
	end
end


---@param event on_force_cease_fire_changed | on_force_friends_changed
function M.on_force_relation_changed(event)
	--- Perhaps, it should ignore added forces
	local force = event.force
	if not force.valid then return end
	update_bases_rendering()
end


--- Should be fine without it because of EasyAPI
---@param event on_pre_surface_deleted
-- function M.on_pre_surface_deleted(event)
-- 	local surface_index = event.surface_index
-- 	local bases = _main_bases[surface_index]
-- 	if bases == nil then return end

-- 	for force_index in pairs(bases) do
-- 		remove_team_data(force_index, true)
-- 	end
-- 	_main_bases[surface_index] = nil
-- end


function check_vehicles()
	for i=#_vehicles_with_player, 1, -1 do
		local entity = _vehicles_with_player[i]
		if not entity.valid then
			tremove(_vehicles_with_player, i)
			goto skip_entity
		end

		local surface = entity.surface
		local bases_position = _main_bases[surface.index]
		if bases_position == nil then
			goto skip_entity
		end

		local force = entity.force
		local entity_force_index = force.index
		local ent_pos = entity.position
		local ent_x = ent_pos.x
		local ent_y = ent_pos.y
		for force_index, base_position in pairs(bases_position) do
			local protection_radius = _protection_radius[force_index]
			if protection_radius == nil then
				goto skip_force
			end

			if force_index == entity_force_index then
				goto skip_force
			end

			local center_x = base_position[1]
			local center_y = base_position[2]
			local xdiff = ent_x - center_x
			local ydiff = ent_y - center_y
			-- Teleport outside of radius
			if (xdiff * xdiff + ydiff * ydiff)^0.5 <= protection_radius then
				local r = protection_radius + 2
				local t = atan2(ydiff, xdiff)
				_teleport_position.x = r * cos(t) + center_x
				_teleport_position.y = r * sin(t) + center_y
				entity.teleport(_teleport_position)
				entity.speed = 0
				return
			end
			::skip_force::
		end
		:: skip_entity ::
	end
end


function expand_protections()
	if next(_speed_protection) == nil then
		return
	end

	for force_index, speed in pairs(_speed_protection) do
		local radius_protection = _protection_radius[force_index] + speed
		local max_radius_protection = _max_radius_protection[force_index]
		if radius_protection < 0 then
			disable_protection(force_index, true)
			goto continue
		elseif radius_protection < max_radius_protection then
			_protection_radius[force_index] = radius_protection
			goto update_rendering
		else
			radius_protection = max_radius_protection
			_protection_radius[force_index] = max_radius_protection
			_speed_protection[force_index] = nil
		end

		::update_rendering::
		local rendering_ids = _main_base_rendering[force_index]
		for i=5, 8 do
			local id = rendering_ids[i]
			if id == nil then
				break
			end

			local render_object = get_render_object_by_id(id)
			if render_object.valid then
				render_object.radius = radius_protection
			end
		end
		::continue::
	end

	-- Teleport players outside of protection zone
	for _, player in pairs(game.connected_players) do
		if not player.valid then
			goto skip_player
		end
		local surface = player.surface
		local bases_position = _main_bases[surface.index]
		if bases_position == nil then return end

		local force = player.force
		local player_force_index = force.index
		local ent_pos = player.position
		local ent_x = ent_pos.x
		local ent_y = ent_pos.y
		for force_index, base_position in pairs(bases_position) do
			local protection_radius = _protection_radius[force_index]
			if protection_radius == nil then
				goto continue
			end

			if force_index == player_force_index then
				goto continue
			end

			local center_x = base_position[1]
			local center_y = base_position[2]
			local xdiff = ent_x - center_x
			local ydiff = ent_y - center_y
			-- Teleport outside of radius
			if (xdiff * xdiff + ydiff * ydiff)^0.5 <= protection_radius then
				local r = protection_radius + 2
				local t = atan2(ydiff, xdiff)
				_teleport_position.x = r * cos(t) + center_x
				_teleport_position.y = r * sin(t) + center_y
				player.teleport(_teleport_position)
				goto continue
			end
			::continue::
		end
		:: skip_player ::
	end
end


function check_planned_disabled_protections(event)
	local current_tick = event.tick
	for force_index, end_tick in pairs(_planned_disabled_protection) do
		if end_tick >= current_tick then
			disable_protection(force_index, true)
		end
	end
end


function check_protections(event)
	local current_tick = event.tick
	for force_index, time_data in pairs(_time_protection) do
		if current_tick >= (time_data.start_tick + time_data.ticks_of_protection) then
			disable_protection(force_index)
		end
	end
end


--#endregion


--#region Pre-game stage

local function add_remote_interface()
	-- https://lua-api.factorio.com/latest/LuaRemote.html
	remote.remove_interface("protected_teams") -- For safety
	remote.add_interface("protected_teams", {
		get_mod_data = function() return _mod_data end,
		get_internal_data = function(name) return _mod_data[name] end,
		change_setting = function(type, name, value)
			settings[type][name] = {value = value}
		end,
		clear_invalid_data = clear_invalid_data,
		clear_invalid_forces = clear_invalid_forces,
		init_team_data = init_team_data,
		destroy_entity = destroy_entity,
		enable_protection = enable_protection,
		disable_protection = disable_protection,
		get_speed_protection = function() return _speed_protection end,
		get_max_radius_protection  = function() return _max_radius_protection end,
	})
end

local function link_data()
	_mod_data = storage.PTZO
	_vehicles_with_player = _mod_data.vehicles_with_player
	_forced_protected_teams = _mod_data.forced_protected_teams
	_protection_radius = _mod_data.radius_protection
	_build_protection_radius = _mod_data.build_radius_protection
	_max_radius_protection = _mod_data.max_radius_protection
	_speed_protection = _mod_data.speed_protection
	_planned_disabled_protection = _mod_data.planned_disabled_protection
	_time_protection = _mod_data.time_protection
	_teams_data = _mod_data.teams_data
	_main_bases = _mod_data.main_bases
	_main_base_rendering = _mod_data.main_base_rendering
end

local function update_global_data()
	storage.PTZO = storage.PTZO or {}
	_mod_data = storage.PTZO
	_mod_data.vehicles_with_player = _mod_data.vehicles_with_player or {}
	_mod_data.planned_disabled_protection = _mod_data.planned_disabled_protection or {}
	_mod_data.forced_protected_teams = _mod_data.forced_protected_teams or {}
	_mod_data.radius_protection = _mod_data.radius_protection or {}
	_mod_data.build_radius_protection = _mod_data.build_radius_protection or {}
	_mod_data.max_radius_protection = _mod_data.max_radius_protection or {}
	_mod_data.speed_protection = _mod_data.speed_protection or {}
	_mod_data.time_protection = _mod_data.time_protection or {}
	_mod_data.teams_data = _mod_data.teams_data or {}
	_mod_data.main_bases = _mod_data.main_bases or {}
	_mod_data.main_base_rendering = _mod_data.main_base_rendering or {}

	link_data()

	clear_invalid_data()

	if game then
		detect_desync(game)
	end
end

local function on_configuration_changed(event)
	update_global_data()

	-- local mod_changes = event.mod_changes["trading_system"]
	-- if not (mod_changes and mod_changes.old_version) then return end

	-- local version = tonumber(string.gmatch(mod_changes.old_version, "%d+.%d+")())
end

do
	local function set_filters()
		script.set_event_filter(defines.events.on_built_entity, {
			{filter = "type", type = "entity-ghost"}
		})
		script.set_event_filter(defines.events.script_raised_teleported, {
			{filter = "type", type = "character"}
		})

		local EasyAPI_events = call("EasyAPI", "get_events")

		if EasyAPI_events.on_fix_bugs then
			script.on_event(EasyAPI_events.on_fix_bugs, function()
				clear_invalid_forces()

				detect_desync(game)
			end)
		end

		if EasyAPI_events.on_new_team then
			script.on_event(EasyAPI_events.on_new_team, function(event)
				local force = event.force
				if not force.valid then return end

				_teams_data[force.index] = {
					ticks_used_protection_for_entering = 0
				}
			end)
		end

		if EasyAPI_events.on_pre_deleted_team then
			script.on_event(EasyAPI_events.on_pre_deleted_team, function(event)
				local force = event.force
				if not force.valid then return end --- welp

				remove_team_data(force.index)
			end)
		end

		if EasyAPI_events.on_new_team_base then
			script.on_event(EasyAPI_events.on_new_team_base, function(event)
				local force = event.force
				if not force.valid then return end
				local surface = event.surface
				if not surface.valid then return end

				-- Set global data
				local surface_index = surface.index
				local force_index = force.index
				local teams_bases = _main_bases[surface_index]
				local position = event.position
				if teams_bases then
					teams_bases[force_index] = {position.x, position.y}
				else
					_main_bases[surface_index] = {[force_index] = {position.x, position.y}}
				end

				local team_data = _teams_data[force_index]
				team_data.base_position = position
				team_data.base_surface	= surface

				-- Create rendering of build protection zone
				_build_protection_radius[force_index] = _build_protection_radius[force_index] or settings.global["PTZO_default_build_radius_protection"].value
				local build_protection_radius = _build_protection_radius[force_index]
				local render_data = {
					target  = position,
					surface = surface,
					radius  = build_protection_radius,
					color   = {255, 165, 0, math.floor(255/2)},
					forces  = {force},
					filled  = false,
					width   = 6,
					draw_on_ground = true
				} --[[@as LuaRendering.draw_circle_param]]
				local enemies, neutrals, allies = get_forces_by_relations(game.forces[force_index])
				_main_base_rendering[force_index] = {nil,nil,nil,nil,nil,nil,nil,nil}
				_main_base_rendering[force_index][1] = rendering.draw_circle(render_data).id
				render_data.color   = {1, 0, 0, 0.5}
				render_data.forces  = enemies
				render_data.visible = (#enemies ~= 0)
				_main_base_rendering[force_index][2] = rendering.draw_circle(render_data).id
				render_data.color   = {1, 1, 1, 0.5}
				render_data.forces  = neutrals
				render_data.visible = (#neutrals ~= 0)
				_main_base_rendering[force_index][3] = rendering.draw_circle(render_data).id
				render_data.color   = {0, 1, 0, 0.5}
				render_data.forces  = allies
				render_data.visible = (#allies ~= 0)
				_main_base_rendering[force_index][4] = rendering.draw_circle(render_data).id

				init_team_data(force_index)
			end)
		end

		if EasyAPI_events.on_new_team_base then
			script.on_event(EasyAPI_events.on_pre_deleted_team_base, function(event)
				remove_team_data(event.force.index, true)
			end)
		end

		if EasyAPI_events.on_sync then
			script.on_event(EasyAPI_events.on_sync, function()
				link_data()
			end)
		end
	end

	M.on_load = function()
		link_data()
		set_filters()
	end
	M.on_init = function()
		update_global_data()
		set_filters()
	end
end
M.on_configuration_changed = on_configuration_changed
M.add_remote_interface = add_remote_interface

--#endregion


M.events = {
	[defines.events.on_player_joined_game] = M.on_player_joined_game,
	[defines.events.on_player_left_game] = M.on_player_left_game,
	[defines.events.on_player_changed_force] = M.on_player_changed_force, -- TODO: check teams
	[defines.events.on_forces_merging] = M.on_forces_merging,
	[defines.events.on_robot_built_entity] = M.on_robot_built_entity,
	[defines.events.on_built_entity] = M.on_built_entity,
	[defines.events.on_pre_build] = M.on_pre_build,
	[defines.events.on_player_driving_changed_state] = M.on_player_driving_changed_state,
	[defines.events.on_player_changed_position] = M.on_player_changed_position,
	[defines.events.on_force_cease_fire_changed] = M.on_force_relation_changed,
	[defines.events.on_force_friends_changed] = M.on_force_relation_changed,
}

M.on_nth_tick = {
	[1] = check_vehicles,
	[3] = expand_protections,
	[60] = check_planned_disabled_protections,
	[60 * 30] = check_protections
}


return M
