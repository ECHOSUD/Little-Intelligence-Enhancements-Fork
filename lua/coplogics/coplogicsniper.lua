local tmp_vec1 = Vector3()

function CopLogicSniper.enter(data, new_logic_name, enter_params)
	CopLogicBase.enter(data, new_logic_name, enter_params)

	local objective = data.objective

	data.unit:brain():cancel_all_pathing_searches()

	local old_internal_data = data.internal_data
	local my_data = {
		unit = data.unit,
		detection = data.char_tweak.detection.recon
	}

	if old_internal_data then
		my_data.turning = old_internal_data.turning

		if old_internal_data.firing then
			data.unit:movement():set_allow_fire(false)
		end

		if old_internal_data.shooting then
			data.unit:brain():action_request({
				body_part = 3,
				type = "idle"
			})
		end

		if old_internal_data.nearest_cover then
			my_data.nearest_cover = old_internal_data.nearest_cover

			managers.navigation:reserve_cover(my_data.nearest_cover[1], data.pos_rsrv_id)
		end

		if old_internal_data.best_cover then
			my_data.best_cover = old_internal_data.best_cover

			managers.navigation:reserve_cover(my_data.best_cover[1], data.pos_rsrv_id)
		end
	end

	data.internal_data = my_data
	local key_str = tostring(data.unit:key())
	my_data.detection_task_key = "CopLogicSniper._upd_enemy_detection" .. key_str
	CopLogicIdle._chk_has_old_action(data, my_data)
	CopLogicBase.queue_task(my_data, my_data.detection_task_key, CopLogicSniper._upd_enemy_detection, data, data.t)

	if objective then
		my_data.wanted_stance = objective.stance
		my_data.wanted_pose = objective.pose
		my_data.attitude = objective.attitude or "avoid"
	end

	data.unit:movement():set_cool(false)

	if my_data ~= data.internal_data then
		return
	end
	
	

	data.unit:brain():set_attention_settings({
		cbt = true
	})

	my_data.weapon_range = data.char_tweak.weapon[data.unit:inventory():equipped_unit():base():weapon_tweak_data().usage].range

	if data.char_tweak.weapon[data.unit:inventory():equipped_unit():base():weapon_tweak_data().usage].use_laser then
		data.unit:inventory():equipped_unit():base():set_laser_enabled(true)

		my_data.weapon_laser_on = true

		data.unit:base():prevent_main_bones_disabling(true)
		managers.network:session():send_to_peers_synched("sync_unit_event_id_16", data.unit, "brain", HuskCopBrain._NET_EVENTS.weapon_laser_on)
	end
end

function CopLogicSniper._upd_aim(data, my_data)
	local shoot, aim = nil
	local focus_enemy = data.attention_obj
	local enemy_pos = nil

	if focus_enemy then
		enemy_pos = focus_enemy.verified and focus_enemy.m_head_pos or focus_enemy.last_verified_pos or focus_enemy.verified_pos
	
		if focus_enemy.verified then
			shoot = true
		elseif my_data.wanted_stance == "cbt" then
			aim = true
		elseif focus_enemy.verified_t and data.t - focus_enemy.verified_t < 20 then
			aim = true
		end

		if aim and not shoot and my_data.shooting and focus_enemy.verified_t and data.t - focus_enemy.verified_t < 2 then
			shoot = true
		end
	end

	if shoot and focus_enemy.reaction < AIAttentionObject.REACT_SHOOT then
		shoot = nil
		aim = true
	end

	local action_taken = my_data.turning or data.unit:movement():chk_action_forbidden("walk")

	if not action_taken then
		local anim_data = data.unit:anim_data()

		if anim_data.reload and not anim_data.crouch and (not data.char_tweak.allowed_poses or data.char_tweak.allowed_poses.crouch) then
			action_taken = CopLogicAttack._chk_request_action_crouch(data)
		end

		if action_taken then
			-- Nothing
		elseif my_data.attitude == "engage" and not data.is_suppressed then
			if focus_enemy then 
				if not CopLogicAttack._chk_request_action_turn_to_enemy(data, my_data, data.m_pos, enemy_pos) and not focus_enemy.verified and not anim_data.reload then
					if anim_data.crouch then
						if (not data.char_tweak.allowed_poses or data.char_tweak.allowed_poses.stand) and not CopLogicSniper._chk_stand_visibility(data.m_pos, enemy_pos, data.visibility_slotmask) then
							CopLogicAttack._chk_request_action_stand(data)
						end
					elseif (not data.char_tweak.allowed_poses or data.char_tweak.allowed_poses.crouch) and not CopLogicSniper._chk_crouch_visibility(data.m_pos, enemy_pos, data.visibility_slotmask) then
						CopLogicAttack._chk_request_action_crouch(data)
					end
				end
			elseif my_data.wanted_pose and not anim_data.reload then
				if my_data.wanted_pose == "crouch" then
					if not anim_data.crouch and (not data.char_tweak.allowed_poses or data.char_tweak.allowed_poses.crouch) then
						action_taken = CopLogicAttack._chk_request_action_crouch(data)
					end
				elseif not anim_data.stand and (not data.char_tweak.allowed_poses or data.char_tweak.allowed_poses.stand) then
					action_taken = CopLogicAttack._chk_request_action_stand(data)
				end
			end
		elseif focus_enemy then
			if not CopLogicAttack._chk_request_action_turn_to_enemy(data, my_data, data.m_pos, enemy_pos) and focus_enemy.verified and anim_data.stand and (not data.char_tweak.allowed_poses or data.char_tweak.allowed_poses.crouch) and CopLogicSniper._chk_crouch_visibility(data.m_pos, enemy_pos, data.visibility_slotmask) then
				CopLogicAttack._chk_request_action_crouch(data)
			end
		elseif my_data.wanted_pose and not anim_data.reload then
			if my_data.wanted_pose == "crouch" then
				if not anim_data.crouch and (not data.char_tweak.allowed_poses or data.char_tweak.allowed_poses.crouch) then
					action_taken = CopLogicAttack._chk_request_action_crouch(data)
				end
			elseif not anim_data.stand and (not data.char_tweak.allowed_poses or data.char_tweak.allowed_poses.stand) then
				action_taken = CopLogicAttack._chk_request_action_stand(data)
			end
		end
	end

	if my_data.reposition and not action_taken and not my_data.advancing then
		local objective = data.objective
		my_data.advance_path = {
			mvector3.copy(data.m_pos),
			mvector3.copy(objective.pos)
		}

		if CopLogicTravel._chk_request_action_walk_to_advance_pos(data, my_data, objective.haste or "walk", objective.rot) then
			action_taken = true
		end
	end
	
	if focus_enemy then
		CopLogicAttack._chk_enrage(data, focus_enemy)
	end
	
	if my_data.firing and focus_enemy then
		LIESBossLogicAttack._chk_use_throwable(data, my_data, focus_enemy)
	end
	
	if focus_enemy and AIAttentionObject.REACT_COMBAT <= focus_enemy.reaction then
		if LIES.settings.enemy_reaction_level < 3 and not data.unit:in_slot(16) then
			if not focus_enemy.react_t then
				focus_enemy.react_t = data.t
			end
		
			if not focus_enemy.verified_t or data.t - focus_enemy.verified_t > 2 then
				focus_enemy.react_t = data.t
			end
		
			local react_t = 2 / LIES.settings.enemy_reaction_level
		
			if data.t - focus_enemy.react_t < react_t then
				shoot = nil
			end
		end
	end
	
	if aim or shoot then
		if focus_enemy.verified then
			if my_data.attention_unit ~= focus_enemy.unit:key() then
				CopLogicBase._set_attention(data, focus_enemy)

				my_data.attention_unit = focus_enemy.unit:key()
			end
		else
			local enemy_pos = focus_enemy.last_verified_pos or focus_enemy.verified_pos
			
			if my_data.attention_unit ~= enemy_pos then
				CopLogicBase._set_attention_on_pos(data, mvector3.copy(enemy_pos))

				my_data.attention_unit = mvector3.copy(enemy_pos)
			end
		end

		if not my_data.shooting and not data.unit:anim_data().reload and not data.unit:movement():chk_action_forbidden("action") then
			local shoot_action = {
				body_part = 3,
				type = "shoot"
			}

			if data.unit:brain():action_request(shoot_action) then
				my_data.shooting = true
			end
		end
	else
		if my_data.shooting then
			local new_action = {
				body_part = 3,
				type = "idle"
			}
			
			data.unit:brain():action_request(new_action)
		end

		if my_data.attention_unit then
			CopLogicBase._reset_attention(data)

			my_data.attention_unit = nil
		end
	end

	CopLogicAttack.aim_allow_fire(shoot, aim, data, my_data)
end

function CopLogicSniper._chk_stand_visibility(my_pos, target_pos, slotmask)
	mvector3.set(tmp_vec1, my_pos)
	mvector3.set_z(tmp_vec1, my_pos.z + 180)

	local ray = World:raycast("ray", tmp_vec1, target_pos, "slot_mask", slotmask, "ray_type", "ai_vision", "report")

	return ray
end

function CopLogicSniper._chk_crouch_visibility(my_pos, target_pos, slotmask)
	mvector3.set(tmp_vec1, my_pos)
	mvector3.set_z(tmp_vec1, my_pos.z + 90)

	local ray = World:raycast("ray", tmp_vec1, target_pos, "slot_mask", slotmask, "ray_type", "ai_vision", "report")

	return ray
end

function CopLogicSniper._upd_enemy_detection(data)
	managers.groupai:state():on_unit_detection_updated(data.unit)

	data.t = TimerManager:game():time()
	local my_data = data.internal_data
	
	if my_data.has_old_action or my_data.old_action_advancing then
		CopLogicAttack._upd_stop_old_action(data, my_data)
	end
	
	local min_reaction = AIAttentionObject.REACT_AIM
	local delay = CopLogicBase._upd_attention_obj_detection(data, min_reaction, nil)
	local new_attention, new_prio_slot, new_reaction = CopLogicIdle._get_priority_attention(data, data.detected_attention_objects, CopLogicSniper._chk_reaction_to_attention_object)
	local old_att_obj = data.attention_obj

	CopLogicBase._set_attention_obj(data, new_attention, new_reaction)

	if new_reaction and AIAttentionObject.REACT_SCARED <= new_reaction then
		local objective = data.objective
		local wanted_state = nil
		local allow_trans, obj_failed = CopLogicBase.is_obstructed(data, objective, nil, new_attention)

		if allow_trans and obj_failed then
			wanted_state = CopLogicBase._get_logic_state_from_reaction(data)
		end

		if wanted_state and wanted_state ~= data.name then
			if obj_failed then
				data.objective_failed_clbk(data.unit, data.objective)
			end

			if my_data == data.internal_data then
				CopLogicBase._exit(data.unit, wanted_state)
			end

			CopLogicBase._report_detections(data.detected_attention_objects)

			return
		end
	end

	CopLogicSniper._upd_aim(data, my_data)

	delay = data.important and 0 or delay

	CopLogicBase.queue_task(my_data, my_data.detection_task_key, CopLogicSniper._upd_enemy_detection, data, data.t + delay)
	CopLogicBase._report_detections(data.detected_attention_objects)
end

function CopLogicSniper.action_complete_clbk(data, action)
	local action_type = action:type()
	local my_data = data.internal_data

	if action_type == "turn" then
		my_data.turning = nil
		
		if action:expired() then
			CopLogicSniper._upd_aim(data, my_data)
		end
	elseif action_type == "shoot" then
		my_data.shooting = nil
	elseif action_type == "walk" then
		my_data.advacing = nil
		my_data.advancing = nil
		my_data.old_action_advancing = nil

		if action:expired() then
			my_data.reposition = nil
			CopLogicSniper._upd_aim(data, my_data)
		end
	elseif (action_type == "hurt" or action_type == "healed") and data.objective and data.objective.pos then
		if action:expired() then
			my_data.reposition = true
		end
	end
end