function TankCopLogicAttack.enter(data, new_logic_name, enter_params)
	CopLogicBase.enter(data, new_logic_name, enter_params)

	local old_internal_data = data.internal_data
	local my_data = {
		unit = data.unit
	}
	data.internal_data = my_data
	my_data.detection = data.char_tweak.detection.combat

	if old_internal_data then
		my_data.turning = old_internal_data.turning
		my_data.firing = old_internal_data.firing
		my_data.shooting = old_internal_data.shooting
		my_data.attention_unit = old_internal_data.attention_unit
	end

	local key_str = tostring(data.key)
	my_data.detection_task_key = "CopLogicAttack._upd_enemy_detection" .. key_str

	CopLogicBase.queue_task(my_data, my_data.detection_task_key, CopLogicAttack._upd_enemy_detection, data)
	CopLogicIdle._chk_has_old_action(data, my_data)

	my_data.attitude = data.objective and data.objective.attitude or "avoid"
	my_data.weapon_range = data.char_tweak.weapon[data.unit:inventory():equipped_unit():base():weapon_tweak_data().usage].range

	data.unit:brain():set_update_enabled_state(true)
	data.unit:movement():set_cool(false)

	if my_data ~= data.internal_data then
		return
	end

	data.unit:brain():set_attention_settings({
		cbt = true
	})
end

function TankCopLogicAttack.update(data)
	local t = data.t
	local unit = data.unit
	local my_data = data.internal_data

	if my_data.has_old_action or my_data.old_action_advancing then
		CopLogicAttack._upd_stop_old_action(data, my_data)
		
		if my_data.has_old_action or my_data.old_action_advancing then
			return
		end
	end

	if CopLogicIdle._chk_relocate(data) then
		return
	end

	if not data.attention_obj or data.attention_obj.reaction < AIAttentionObject.REACT_AIM then
		CopLogicAttack._upd_enemy_detection(data, true)

		if my_data ~= data.internal_data or not data.attention_obj or data.attention_obj.reaction < AIAttentionObject.REACT_AIM then
			return
		end
	end

	local focus_enemy = data.attention_obj

	TankCopLogicAttack._process_pathing_results(data, my_data)

	local enemy_visible = focus_enemy.verified
	my_data.attitude = data.objective and data.objective.attitude or "engage"
	local engage = my_data.attitude == "engage"
	local action_taken = my_data.turning or data.unit:movement():chk_action_forbidden("walk") or my_data.walking_to_chase_pos

	if action_taken then
		return
	end

	if unit:anim_data().crouch then
		action_taken = CopLogicAttack._chk_request_action_stand(data)
	end

	if action_taken then
		return
	end

	local enemy_pos = enemy_visible and focus_enemy.m_pos or focus_enemy.verified_pos
	action_taken = CopLogicAttack._chk_request_action_turn_to_enemy(data, my_data, data.m_pos, enemy_pos)

	if action_taken then
		return
	end

	local chase = nil
	local z_dist = math.abs(data.m_pos.z - focus_enemy.m_pos.z)

	if AIAttentionObject.REACT_COMBAT <= focus_enemy.reaction then
		if enemy_visible then
			if z_dist < 300 or focus_enemy.verified_dis > 2000 or engage and focus_enemy.verified_dis > 500 then
				chase = true
			end

			if focus_enemy.verified_dis < 800 and unit:anim_data().run then
				local new_action = {
					body_part = 2,
					type = "idle"
				}

				data.unit:brain():action_request(new_action)
			end
		elseif z_dist < 300 or focus_enemy.verified_dis > 2000 or engage and (not focus_enemy.verified_t or t - focus_enemy.verified_t > 5 or focus_enemy.verified_dis > 700) then
			chase = true
		end
	end

	if chase then
		if not data.next_mov_time or data.next_mov_time < data.t then
			if my_data.walking_to_chase_pos then
				-- Nothing
			elseif my_data.pathing_to_chase_pos then
				-- Nothing
			elseif my_data.chase_path then
				local dist = focus_enemy.verified_dis
				local run_dist = focus_enemy.verified and 1500 or 800
				local walk = dist < run_dist

				TankCopLogicAttack._chk_request_action_walk_to_chase_pos(data, my_data, walk and "walk" or "run")
			elseif my_data.chase_pos then
				my_data.chase_path_search_id = tostring(unit:key()) .. "chase"
				my_data.pathing_to_chase_pos = true
				local to_pos = my_data.chase_pos
				my_data.chase_pos = nil

				data.brain:add_pos_rsrv("path", {
					radius = 60,
					position = mvector3.copy(to_pos)
				})
				unit:brain():search_for_path(my_data.chase_path_search_id, to_pos)
			elseif focus_enemy.nav_tracker then
				my_data.chase_pos = CopLogicAttack._find_flank_pos(data, my_data, focus_enemy.nav_tracker)
			end
		end
	else
		TankCopLogicAttack._cancel_chase_attempt(data, my_data)
	end
end