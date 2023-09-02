Hooks:PostHook(CopBrain, "init", "lies_init", function(self, unit)
	CopBrain._logic_variants.marshal_marksman = CopBrain._logic_variants.swat

	CopBrain._logic_variants.tank.attack = BossLogicAttack
	CopBrain._logic_variants.tank_medic.attack = BossLogicAttack
	CopBrain._logic_variants.tank_mini.attack = BossLogicAttack
	CopBrain._logic_variants.mobster_boss = CopBrain._logic_variants.tank
	CopBrain._logic_variants.biker_boss = CopBrain._logic_variants.tank
	CopBrain._logic_variants.drug_lord_boss = CopBrain._logic_variants.tank
end)

Hooks:PostHook(CopBrain, "post_init", "lies_post", function(self)
	if self._logic_data.char_tweak.buddy then
		local level = Global.level_data and Global.level_data.level_id
		
		if tweak_data.levels[level].follow_by_default then
			self._logic_data.check_crim_jobless = true
		end
	end
end)

Hooks:PostHook(CopBrain, "_reset_logic_data", "lies_reset_logic_data", function(self)
	self._logic_data.char_tweak = self._unit:base()._char_tweak or tweak_data.character[self._unit:base()._tweak_table]
	
	if LIES.settings.hhtacs and self._unit:base()._tweak_table == "tank_mini" then
		local difficulty_index = tweak_data:difficulty_to_index(Global.game_settings.difficulty)
		
		if difficulty_index > 7 then
			self._minigunner_firing_buff = {
				id = self._unit:base():add_buff("base_damage", 0),
				amount = 0,
				last_chk_t = self._timer:time()
			}
		end
	end
	
	self._logic_data.next_mov_time = self:get_movement_delay()
end)

Hooks:PostHook(CopBrain, "set_spawn_entry", "lies_accessentry", function(self, spawn_entry, tactics_map)
	if spawn_entry.access then
		self._SO_access = managers.navigation:convert_access_flag(spawn_entry.access)
		self._logic_data.SO_access = self._SO_access
		self._logic_data.SO_access_str = spawn_entry.access
	end
end)

Hooks:PostHook(CopBrain, "convert_to_criminal", "lies_convert_to_criminal", function(self, mastermind_criminal)
	local char_tweaks = deep_clone(self._unit:base()._char_tweak)
	
	char_tweaks.suppression = nil
	char_tweaks.throwable = nil
	char_tweaks.crouch_move = false
	
	if LIES.settings.jokerhurts then
		char_tweaks.damage.hurt_severity = tweak_data.character.presets.hurt_severities.only_light_hurt
		
		char_tweaks.damage.hurt_severity.explosion = {
			health_reference = 1,
			zones = {
				{
					light = 1
				}
			}
		}
	end
	
	self._logic_data.char_tweak = char_tweaks
	self._unit:base()._char_tweak = char_tweaks
	self._unit:character_damage()._char_tweak = char_tweaks
	self._unit:movement()._tweak_data = char_tweaks
	self._unit:movement()._action_common_data.char_tweak = char_tweaks
end)

local ludicrous_damage = {
	m4 = true,
	m4_yellow = true,
	ak47 = true
}
local mayhem_rifles = {
	m4_yellow = true,
	g36 = true
}
local scaling_units = {
	security = true,
	shield = true,
	cop = true,
	fbi = true,
	swat = true,
	heavy_swat = true,
	gangster = true,
	swat = true,
	taser = true
}

local non_scaling_units = {
	fbi_heavy_swat = "heavy_swat",
	fbi_swat = "swat",
	city_swat = "swat"
}

Hooks:PostHook(CopBrain, "set_group", "lies_reset_weapons", function(self, group)
	if not Network:is_server() then
		return
	end
	
	if LIES.settings.hhtacs then
		local not_america = tweak_data.group_ai._not_america
		local difficulty = Global.game_settings and Global.game_settings.difficulty or "normal"
		local difficulty_index = tweak_data:difficulty_to_index(difficulty)
		
		if not_america and difficulty == "sm_wish" and not self._unit:base()._loudtweakdata then
			if non_scaling_units[self._unit:base()._tweak_table] then
				local new_tweak_name = non_scaling_units[self._unit:base()._tweak_table]
				self._unit:base():change_and_sync_char_tweak(new_tweak_name)
			end
		end
		
		if scaling_units[self._unit:base()._tweak_table] and difficulty_index > 6 then
			self._needs_falloff = {
				id = self._unit:base():add_buff("base_damage", 0),
				amount = 0
			}
		end
	end

	local weap_name = self._unit:base():default_weapon_name()
	
	if self._unit:base()._old_weapon and weap_name ~= self._unit:base()._old_weapon then
		self._unit:base()._old_weapon = nil
		PlayerInventory.destroy_all_items(self._unit:inventory())

		self._unit:inventory():add_unit_by_name(weap_name, true)
	end
	
	if LIES.settings.hhtacs then	
		if not self._ludicrous_damage_debuff and ludicrous_damage[self._unit:base()._current_weapon_id] and scaling_units[self._unit:base()._tweak_table] and Global.game_settings.difficulty == "sm_wish" then
			--m4 nerds with spicy tactics on death sentence will deal the same damage as a zeal heavy
			self._ludicrous_damage_debuff = self._unit:base():add_buff("base_damage", -0.6)
		elseif not self._ludicrous_damage_debuff and self._unit:base()._current_weapon_id == "sg417" and scaling_units[self._unit:base()._tweak_table] and Global.game_settings.difficulty == "sm_wish" then
			self._ludicrous_damage_debuff = self._unit:base():add_buff("base_damage", -0.4)
		elseif not self._ludicrous_damage_debuff and self._unit:base()._current_weapon_id == "g36" and Global.game_settings.difficulty == "sm_wish" then 
			self._ludicrous_damage_debuff = self._unit:base():add_buff("base_damage", -0.5) --g36 users deal 75 damage with "good" preset compared to zeal's 90
		elseif not self._ludicrous_damage_debuff and mayhem_rifles[self._unit:base()._current_weapon_id] and Global.game_settings.difficulty == "easy_wish" then
			self._ludicrous_damage_debuff = self._unit:base():add_buff("base_damage", 1.25) 
		elseif not self._ludicrous_damage_debuff and self._unit:base()._current_weapon_id == "ak47_ass" and Global.game_settings.difficulty == "easy_wish" then
			self._ludicrous_damage_debuff = self._unit:base():add_buff("base_damage", -0.1) 
		elseif self._ludicrous_damage_debuff then
			self._unit:base():remove_buff_by_id("base_damage", self._ludicrous_damage_debuff) 
			
			self._ludicrous_damage_debuff = nil
		end
	end
end)

Hooks:PostHook(CopBrain, "on_reload", "lies_on_reload", function(self)
	if not Network:is_server() then
		return
	end
	
	self._logic_data.char_tweak = self._unit:base()._char_tweak or tweak_data.character[self._unit:base()._tweak_table]
	
	local weap_name = self._unit:base():default_weapon_name()
	
	if self._unit:base()._old_weapon and weap_name ~= self._unit:base()._old_weapon then
		self._unit:base()._old_weapon = nil
		PlayerInventory.destroy_all_items(self._unit:inventory())

		self._unit:inventory():add_unit_by_name(weap_name, true)
	end
	
	if LIES.settings.hhtacs then	
		if not self._ludicrous_damage_debuff and ludicrous_damage[self._unit:base()._current_weapon_id] and scaling_units[self._unit:base()._tweak_table] and Global.game_settings.difficulty == "sm_wish" then
			--m4 nerds with spicy tactics on death sentence will deal the same damage as a zeal heavy
			self._ludicrous_damage_debuff = self._unit:base():add_buff("base_damage", -0.6)
		elseif not self._ludicrous_damage_debuff and self._unit:base()._current_weapon_id == "sg417" and scaling_units[self._unit:base()._tweak_table] and Global.game_settings.difficulty == "sm_wish" then
			self._ludicrous_damage_debuff = self._unit:base():add_buff("base_damage", -0.4)
		elseif self._ludicrous_damage_debuff then
			self._unit:base():remove_buff_by_id("base_damage", self._ludicrous_damage_debuff) 
			
			self._ludicrous_damage_debuff = nil
		end
	end
end)

Hooks:PostHook(CopBrain, "clbk_death", "lies_clbk_death", function(self, unit, dmg_info)
	self:rem_all_pos_rsrv()
end)

function CopBrain:add_pos_rsrv(rsrv_name, pos_rsrv)
	if self._unit:character_damage():dead() then
		return
	end

	local pos_reservations = self._logic_data.pos_rsrv

	if pos_reservations[rsrv_name] then
		managers.navigation:unreserve_pos(pos_reservations[rsrv_name])
	end

	pos_rsrv.filter = self._logic_data.pos_rsrv_id

	managers.navigation:add_pos_reservation(pos_rsrv)

	pos_reservations[rsrv_name] = pos_rsrv

	if not pos_rsrv.id then
		debug_pause_unit(self._unit, "[CopBrain:add_pos_rsrv] missing id", inspect(pos_rsrv))

		return
	end
end

function CopBrain:set_pos_rsrv(rsrv_name, pos_rsrv)
	if self._unit:character_damage():dead() then
		return
	end

	local pos_reservations = self._logic_data.pos_rsrv

	if pos_reservations[rsrv_name] == pos_rsrv then
		return
	end

	if pos_reservations[rsrv_name] then
		managers.navigation:unreserve_pos(pos_reservations[rsrv_name])
	end

	if not pos_rsrv.id then
		debug_pause_unit(self._unit, "[CopBrain:set_pos_rsrv] missing id", inspect(pos_rsrv))

		return
	end

	pos_reservations[rsrv_name] = pos_rsrv
end

function CopBrain:_on_player_slow_pos_rsrv_upd()
	if self:is_criminal() then
		if not self._logic_data.objective or self._logic_data.objective.type == "free" then
			self._logic_data.path_fail_t = nil
		elseif self._current_logic._on_player_slow_pos_rsrv_upd then
			self._current_logic._on_player_slow_pos_rsrv_upd(self._logic_data)
		end
	end
end

function CopBrain:get_movement_delay()
	if LIES.settings.enemy_travel_level < 4 then
		local base_delay = 0.2 + 0.7 * math.random()
		
		if self._logic_data.important then
			base_delay = base_delay / 1 + math.random()
		end
		
		base_delay = base_delay / LIES.settings.enemy_travel_level
		
		return base_delay
	else
		return -1
	end
end

function CopBrain:on_suppressed(state)
	if state ~= self._logic_data.is_suppressed then
		self._logic_data.is_suppressed = state or nil
		
		if self._logic_data.is_suppressed then
			if self._current_logic.on_suppressed_state then
				self._current_logic.on_suppressed_state(self._logic_data)
			end
		end
	end
end

function CopBrain:set_objective(new_objective, params)
	local old_objective = self._logic_data.objective
	
	--if new_objective and self._logic_data.char_tweak.is_escort then
		--managers.groupai:state():print_objective(new_objective)
	--end
	
	if new_objective and self._logic_data.char_tweak.buddy then
		local level = Global.level_data and Global.level_data.level_id

		if new_objective.element then
			if tweak_data.levels[level] and tweak_data.levels[level].ignored_so_elements and tweak_data.levels[level].ignored_so_elements[new_objective.element._id] then
				if new_objective.complete_clbk then
					new_objective.complete_clbk(self._unit, self._logic_data)
				end
				
				if new_objective.action_start_clbk then
					new_objective.action_start_clbk(self._unit)
				end
				
				return
			end
		end
		
		if tweak_data.levels[level].trigger_follower_behavior_element and new_objective.element and tweak_data.levels[level].trigger_follower_behavior_element[new_objective.element._id] then
			self._logic_data.check_crim_jobless = true
		end

		if new_objective.stance == "ntl" then
			new_objective.stance = nil
		end
	end
	
	self._logic_data.objective = new_objective

	if new_objective and new_objective.followup_objective and new_objective.followup_objective.interaction_voice then
		self._unit:network():send("set_interaction_voice", new_objective.followup_objective.interaction_voice)
	elseif old_objective and old_objective.followup_objective and old_objective.followup_objective.interaction_voice then
		self._unit:network():send("set_interaction_voice", "")
	end

	self._current_logic.on_new_objective(self._logic_data, old_objective, params)
end

function CopBrain:search_for_coarse_immediate(search_id, to_seg, verify_clbk, access_neg)
	local params = {
		from_tracker = self._unit:movement():nav_tracker(),
		to_seg = to_seg,
		access = {
			"walk"
		},
		id = search_id,
		verify_clbk = verify_clbk,
		access_pos = self._logic_data.char_tweak.access,
		access_neg = access_neg
	}

	return managers.navigation:search_coarse(params)
end

function CopBrain:search_for_path(search_id, to_pos, prio, access_neg, nav_segs)
	if not prio then
		prio = CopLogicTravel.get_pathing_prio(self._logic_data)
	end

	local params = {
		tracker_from = self._unit:movement():nav_tracker(),
		pos_to = to_pos,
		result_clbk = callback(self, self, "clbk_pathing_results", search_id),
		id = search_id,
		prio = prio,
		access_pos = self._SO_access,
		access_neg = access_neg,
		nav_segs = nav_segs
	}
	
	self._logic_data.active_searches[search_id] = true

	managers.navigation:search_pos_to_pos(params)

	return true
end

function CopBrain:search_for_path_from_pos(search_id, from_pos, to_pos, prio, access_neg, nav_segs)
	if not prio then
		prio = CopLogicTravel.get_pathing_prio(self._logic_data)
	end

	local params = {
		pos_from = from_pos,
		pos_to = to_pos,
		result_clbk = callback(self, self, "clbk_pathing_results", search_id),
		id = search_id,
		prio = prio,
		access_pos = self._SO_access,
		access_neg = access_neg,
		nav_segs = nav_segs
	}
	
	self._logic_data.active_searches[search_id] = true
	managers.navigation:search_pos_to_pos(params)

	return true
end

function CopBrain:search_for_path_to_cover(search_id, cover, offset_pos, access_neg)
	if not prio then
		prio = CopLogicTravel.get_pathing_prio(self._logic_data)
		--log("Waaaah")
	end

	local params = {
		tracker_from = self._unit:movement():nav_tracker(),
		tracker_to = cover[3],
		prio = prio,
		result_clbk = callback(self, self, "clbk_pathing_results", search_id),
		id = search_id,
		access_pos = self._SO_access,
		access_neg = access_neg
	}
	
	if offset_pos then
		params.pos_to = mvector3.copy(offset_pos)
		params.tracker_to = nil
	end

	self._logic_data.active_searches[search_id] = true
	managers.navigation:search_pos_to_pos(params)

	return true
end

Hooks:PostHook(CopBrain, "_add_pathing_result", "lies_pathing", function(self, search_id, path)
	if path and path ~= "failed" then
		--local line2 = Draw:brush(Color.green:with_alpha(0.5), 3)
		
		if line2 then
			for i = 1, #path do
				if path[i + 1] then
					local cur_nav_point = path[i]
					
					if not cur_nav_point.z then
						if alive(cur_nav_point) then
							cur_nav_point = CopActionWalk._nav_point_pos(cur_nav_point:script_data())
						end
					end
					
					if cur_nav_point.z then
						local next_nav_point = path[i + 1]
						
						if not next_nav_point.z then
							if alive(next_nav_point) then
								next_nav_point = CopActionWalk._nav_point_pos(next_nav_point:script_data())
							end
						end
						
						if next_nav_point.z then
							line2:cylinder(cur_nav_point, next_nav_point, 20)
						end
					end
				end
			end
		end
	
		self._logic_data.t = self._timer:time()
		self._logic_data.dt = self._timer:delta_time()

		--enemies in logictravel and logicattack will perform their appropriate actions as soon as possible once pathing has finished
		
		if self._current_logic._pathing_complete_clbk then
			managers.groupai:state():on_unit_pathing_complete(self._unit)
		
			self._current_logic._pathing_complete_clbk(self._logic_data)
		end
	else
		managers.groupai:state():on_unit_pathing_failed(self._unit)
	end
end)

function CopBrain:_chk_use_cover_grenade(unit)
	if not Network:is_server() or not self._logic_data.char_tweak.dodge_with_grenade or not self._logic_data.attention_obj then
		return
	end

	local t = TimerManager:game():time()
	
	if not self._next_grenade_use_t or self._next_grenade_use_t < t then
		if self._logic_data.char_tweak.dodge_with_grenade.smoke then
			local duration_tweak = self._logic_data.char_tweak.dodge_with_grenade.smoke.duration
			local duration = math.lerp(duration_tweak[1], duration_tweak[2], math.random())

			managers.groupai:state():detonate_smoke_grenade(self._logic_data.m_pos + math.UP * 10, self._unit:movement():m_head_pos(), duration, false)

			self._next_grenade_use_t = t + duration
		elseif self._logic_data.char_tweak.dodge_with_grenade.flash then
			local duration_tweak = self._logic_data.char_tweak.dodge_with_grenade.flash.duration
			local duration = math.lerp(duration_tweak[1], duration_tweak[2], math.random())

			managers.groupai:state():detonate_smoke_grenade(self._logic_data.m_pos + math.UP * 10, self._unit:movement():m_head_pos(), duration, true)

			self._next_grenade_use_t = t + duration
		end
	end
end

local walk_blocked_actions = {
	hurt = true,
	healed = true,
	heal = true,
	walk = true,
	act = true,
	dodge = true
}

function CopBrain:action_complete_clbk(action)
	if self._unit:character_damage():dead() then
		return
	end
	
	local action_type = action:type()
	
	if walk_blocked_actions[action_type] then
		if action_type ~= "walk" then
			self._unit:movement():upd_m_head_pos()
		end
		
		if not self:is_criminal() then
			local delay = self:get_movement_delay()
			
			if delay > 0 then
				self._logic_data.next_mov_time = self._timer:time() + delay
			end
		end
	end
	
	self._current_logic.action_complete_clbk(self._logic_data, action)
end

function CopBrain:request_stillness(t)
	self._logic_data.next_mov_time = self._timer:time() + t
end

function CopBrain:is_criminal()
	if self._unit:in_slot(16) or self._logic_data.team.id == tweak_data.levels:get_default_team_ID("player") or self._logic_data.team.friends[tweak_data.levels:get_default_team_ID("player")] then
		return true
	end
end