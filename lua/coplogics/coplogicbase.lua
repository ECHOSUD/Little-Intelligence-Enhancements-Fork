local tmp_vec1 = Vector3()
local tmp_vec2 = Vector3()

local mvec3_set = mvector3.set
local mvec3_norm = mvector3.normalize
local mvec3_dir = mvector3.direction
local mvec3_dot = mvector3.dot
local mvec3_set_z = mvector3.set_z
local mvec3_sub = mvector3.subtract
local mvec3_dis = mvector3.distance
local mvec3_dis_sq = mvector3.distance_sq

local m_rot_x = mrotation.x
local m_rot_y = mrotation.y
local m_rot_z = mrotation.z

function CopLogicBase.chk_am_i_aimed_at(data, attention_obj, max_dot)
	if not attention_obj.is_person or not attention_obj.is_alive then
		return
	end

	if attention_obj.dis < 700 and max_dot > 0.3 then
		max_dot = math.lerp(0.3, max_dot, (attention_obj.dis - 50) / 650)
	end

	local enemy_look_dir = tmp_vec1
	local weapon_rot = nil

	if attention_obj.is_husk_player then
		mvec3_set(enemy_look_dir, attention_obj.unit:movement():detect_look_dir())
	else
		if attention_obj.is_local_player then
			m_rot_y(attention_obj.unit:movement():m_head_rot(), enemy_look_dir)
		else
			if attention_obj.unit:inventory() and attention_obj.unit:inventory():equipped_unit() then
				if attention_obj.unit:movement()._stance.values[3] >= 0.6 then
					local weapon_fire_obj = attention_obj.unit:inventory():equipped_unit():get_object(Idstring("fire"))

					if alive(weapon_fire_obj) then
						weapon_rot = weapon_fire_obj:rotation()
					end
				end
			end

			if weapon_rot then
				m_rot_y(weapon_rot, enemy_look_dir)
			else
				m_rot_z(attention_obj.unit:movement():m_head_rot(), enemy_look_dir)
			end
		end

		mvec3_norm(enemy_look_dir)
	end

	local enemy_vec = tmp_vec2

	mvec3_dir(enemy_vec, attention_obj.m_head_pos, data.unit:movement():m_com())

	return max_dot < mvec3_dot(enemy_vec, enemy_look_dir)
end

function CopLogicBase.is_obstructed(data, objective, strictness, attention)
	local my_data = data.internal_data
	attention = attention or data.attention_obj

	if not objective or objective.is_default or (objective.in_place or not objective.nav_seg) and not objective.action then
		return true, false
	end

	if objective.interrupt_suppression and data.is_suppressed then
		return true, true
	end

	strictness = strictness or 0

	if objective.interrupt_health then
		local health_ratio = data.unit:character_damage():health_ratio()
		local too_much_damage = health_ratio < 1 and health_ratio * (1 - strictness) < objective.interrupt_health
		local is_dead = data.unit:character_damage():dead()

		if too_much_damage or is_dead then
			return true, true
		end
	end

	if objective.interrupt_dis then
		if attention and (AIAttentionObject.REACT_COMBAT <= attention.reaction or data.cool and AIAttentionObject.REACT_SURPRISED <= attention.reaction) then
			if objective.interrupt_dis == -1 then
				return true, true
			elseif math.abs(attention.m_pos.z - data.m_pos.z) < 250 then
				local enemy_dis = attention.dis * (1 - strictness)

				if not attention.verified then
					enemy_dis = 2 * attention.dis * (1 - strictness)
				end

				if attention.is_very_dangerous then
					enemy_dis = enemy_dis * 0.25
				end

				if enemy_dis < objective.interrupt_dis then
					return true, true
				end
			end

			if objective.pos and math.abs(attention.m_pos.z - objective.pos.z) < 250 then
				local enemy_dis = mvector3.distance(objective.pos, attention.m_pos) * (1 - strictness)

				if enemy_dis < objective.interrupt_dis then
					return true, true
				end
			end
		elseif objective.interrupt_dis == -1 and not data.unit:movement():cool() then
			return true, true
		end
	end
	
	if not data.cool and data.unit:base()._tweak_table == "marshal_marksman" and attention and AIAttentionObject.REACT_COMBAT <= attention.reaction and (objective.type == "defend_area" or objective.type == "assault_area") then --this is unit is fucking ballin, its almost like i know what im doing
		local weapon = data.unit:inventory():equipped_unit()
		local usage = weapon and weapon:base():weapon_tweak_data().usage
		local range_entry = usage and (data.char_tweak.weapon[usage] or {}).range or {}
		local engage_range = range_entry.optimal or 2000

		if attention.verified then
			engage_range = engage_range * 1.2
		end

		if attention.dis < engage_range then
			return true, true
		end
	end
	
	if objective.interrupt_on_contact then
		if attention and AIAttentionObject.REACT_COMBAT <= attention.reaction and attention.verified_t and data.t - attention.verified_t <= 15 then
			local z_diff = math.abs(attention.m_pos.z - data.m_pos.z)
			local enemy_dis = attention.dis * (1 - strictness)
			
			local aggro_level = LIES.settings.enemy_aggro_level
			local interrupt_dis = nil
			
			if aggro_level > 2 then
				interrupt_dis = my_data.weapon_range and my_data.weapon_range.close or 1000
			else
				interrupt_dis = my_data.weapon_range and my_data.weapon_range.optimal or 2000
			end
			
			interrupt_dis = interrupt_dis * (1 - strictness)
			
			if objective.grp_objective and objective.grp_objective.push then
				interrupt_dis = interrupt_dis * 0.5
			end
			
			interrupt_dis = math.lerp(interrupt_dis, 0, z_diff / 400)

			if enemy_dis < interrupt_dis then
				return true, true
			end
		end
	end

	return false, false
end

function CopLogicBase.queue_task(internal_data, id, func, data, exec_t, asap)
	if not id then
		log("bad task queued")
		log(tostring(data.name))
	end

	if internal_data.unit and internal_data ~= internal_data.unit:brain()._logic_data.internal_data then
		log("task queued from the wrong logic")
		log(tostring(data.name))
		log(tostring(id))
	end

	local qd_tasks = internal_data.queued_tasks

	if qd_tasks then
		if qd_tasks[id] then
			debug_pause("[CopLogicBase.queue_task] Task queued twice", internal_data.unit, id, func, data, exec_t, asap)
		end

		qd_tasks[id] = true
	else
		internal_data.queued_tasks = {
			[id] = true
		}
	end

	managers.enemy:queue_task(id, func, data, exec_t, callback(CopLogicBase, CopLogicBase, "on_queued_task", internal_data), asap)
end

function CopLogicBase._upd_attention_obj_detection(data, min_reaction, max_reaction)
	local t = data.t
	local detected_obj = data.detected_attention_objects
	local my_data = data.internal_data
	local my_key = data.key
	local my_pos = data.unit:movement():m_head_pos()
	local my_access = data.SO_access
	local all_attention_objects = managers.groupai:state():get_AI_attention_objects_by_filter(data.SO_access_str, data.team)
	local my_head_fwd = nil
	local my_tracker = data.unit:movement():nav_tracker()
	--local chk_vis_func = my_tracker.check_visibility
	local is_detection_persistent = managers.groupai:state():is_detection_persistent()
	local is_weapons_hot = managers.groupai:state():enemy_weapons_hot()
	local delay = 2
	local player_importance_wgt = data.unit:in_slot(managers.slot:get_mask("enemies")) and {}

	local function _angle_chk(attention_pos, dis, strictness)
		mvector3.direction(tmp_vec1, my_pos, attention_pos)

		my_head_fwd = my_head_fwd or data.unit:movement():m_head_rot():z()
		local angle = mvector3.angle(my_head_fwd, tmp_vec1)
		local angle_max = math.lerp(180, my_data.detection.angle_max, math.clamp((dis - 150) / 700, 0, 1))

		if angle_max > angle * strictness then
			return true
		end
	end

	local function _angle_and_dis_chk(handler, settings, attention_pos)
		attention_pos = attention_pos or handler:get_detection_m_pos()
		local dis = mvector3.direction(tmp_vec1, my_pos, attention_pos)
		local dis_multiplier, angle_multiplier = nil
		local max_dis = math.min(my_data.detection.dis_max, settings.max_range or my_data.detection.dis_max)

		if settings.detection and settings.detection.range_mul then
			max_dis = max_dis * settings.detection.range_mul
		end

		dis_multiplier = dis / max_dis

		if settings.uncover_range and my_data.detection.use_uncover_range and dis < settings.uncover_range then
			return -1, 0
		end

		if dis_multiplier < 1 then
			if not is_weapons_hot and settings.notice_requires_FOV then
				my_head_fwd = my_head_fwd or data.unit:movement():m_head_rot():z()
				local angle = mvector3.angle(my_head_fwd, tmp_vec1)

				if angle < 55 and not my_data.detection.use_uncover_range and settings.uncover_range and dis < settings.uncover_range then
					return -1, 0
				end

				local angle_max = math.lerp(180, my_data.detection.angle_max, math.clamp((dis - 150) / 700, 0, 1))
				angle_multiplier = angle / angle_max

				if angle_multiplier < 1 then
					return angle, dis_multiplier
				end
			else
				return 0, dis_multiplier
			end
		end
	end

	local function _nearly_visible_chk(attention_info, detect_pos)
		local near_pos = tmp_vec1

		mvec3_set(near_pos, detect_pos)

		local near_vis_ray = World:raycast("ray", my_pos, near_pos, "slot_mask", data.visibility_slotmask, "ray_type", "ai_vision", "report")

		if near_vis_ray then
			local side_vec = tmp_vec2

			mvec3_set(side_vec, my_pos)
			mvec3_sub(side_vec, detect_pos)
			mvector3.cross(side_vec, side_vec, math.UP)
			mvector3.set_length(side_vec, 29)
			mvector3.set(near_pos, detect_pos)
			mvector3.add(near_pos, side_vec)

			near_vis_ray = World:raycast("ray", my_pos, near_pos, "slot_mask", data.visibility_slotmask, "ray_type", "ai_vision", "report")

			if near_vis_ray then
				mvector3.multiply(side_vec, -2)
				mvector3.add(near_pos, side_vec)

				near_vis_ray = World:raycast("ray", my_pos, near_pos, "slot_mask", data.visibility_slotmask, "ray_type", "ai_vision", "report")
			end
		end

		if not near_vis_ray then
			attention_info.nearly_visible = true
			attention_info.release_t = nil

			if attention_info.last_verified_pos then
				mvec3_set(attention_info.last_verified_pos, near_pos)
			else
				attention_info.last_verified_pos = mvector3.copy(near_pos)
			end
		end
	end

	local function _chk_record_acquired_attention_importance_wgt(attention_info)
		if not player_importance_wgt or not attention_info.is_human_player then
			return
		end

		local weight = mvector3.direction(tmp_vec1, attention_info.m_head_pos, my_pos)
		local e_fwd = nil

		if attention_info.is_husk_player then
			e_fwd = attention_info.unit:movement():detect_look_dir()
		else
			e_fwd = attention_info.unit:movement():m_head_rot():y()
		end

		local dot = mvector3.dot(e_fwd, tmp_vec1)
		weight = weight * weight * (1 - dot)

		table.insert(player_importance_wgt, attention_info.u_key)
		table.insert(player_importance_wgt, weight)
	end

	local function _chk_record_attention_obj_importance_wgt(u_key, attention_info)
		if not player_importance_wgt then
			return
		end

		local is_human_player, is_local_player, is_husk_player = nil

		if attention_info.unit:base() then
			is_local_player = attention_info.unit:base().is_local_player
			is_husk_player = not is_local_player and attention_info.unit:base().is_husk_player
			is_human_player = is_local_player or is_husk_player
		end

		if not is_human_player then
			return
		end

		local weight = mvector3.direction(tmp_vec1, attention_info.handler:get_detection_m_pos(), my_pos)
		local e_fwd = nil

		if is_husk_player then
			e_fwd = attention_info.unit:movement():detect_look_dir()
		else
			e_fwd = attention_info.unit:movement():m_head_rot():y()
		end

		local dot = mvector3.dot(e_fwd, tmp_vec1)
		weight = weight * weight * (1 - dot)

		table.insert(player_importance_wgt, u_key)
		table.insert(player_importance_wgt, weight)
	end

	for u_key, attention_info in pairs(all_attention_objects) do
		if u_key ~= my_key and not detected_obj[u_key] then
			local settings = attention_info.handler:get_attention(my_access, min_reaction, max_reaction, data.team)

			if settings then
				local acquired = nil
				local attention_pos = attention_info.handler:get_detection_m_pos()

				if _angle_and_dis_chk(attention_info.handler, settings, attention_pos) then
					local vis_ray = World:raycast("ray", my_pos, attention_pos, "slot_mask", data.visibility_slotmask, "ray_type", "ai_vision")

					if not vis_ray or vis_ray.unit:key() == u_key then
						acquired = true
						detected_obj[u_key] = CopLogicBase._create_detected_attention_object_data(data.t, data.unit, u_key, attention_info, settings)
					end
				end

				if not acquired then
					_chk_record_attention_obj_importance_wgt(u_key, attention_info)
				end
			end
		end
	end

	for u_key, attention_info in pairs(detected_obj) do
		if min_reaction and attention_info.reaction < min_reaction or max_reaction and attention_info.reaction > max_reaction then
			detected_obj[u_key] = nil
		elseif t < attention_info.next_verify_t then
			if AIAttentionObject.REACT_SUSPICIOUS <= attention_info.reaction then
				delay = math.min(attention_info.next_verify_t - t, delay)
			end
		else
			attention_info.next_verify_t = t + (attention_info.identified and attention_info.verified and attention_info.settings.verification_interval or attention_info.settings.notice_interval or attention_info.settings.verification_interval)
			delay = math.min(delay, attention_info.settings.verification_interval)
			
			if not data.cool then
				if not attention_info.identified then
					local noticable = nil
					attention_info.notice_progress = nil
					attention_info.prev_notice_chk_t = nil
					attention_info.identified = true
					attention_info.release_t = t + attention_info.settings.release_delay
					attention_info.identified_t = t
					noticable = true

					data.logic.on_attention_obj_identified(data, u_key, attention_info)

					if noticable ~= false and attention_info.settings.notice_clbk then
						attention_info.settings.notice_clbk(data.unit, noticable)
					end
				end
			elseif not attention_info.identified then
				local noticable = nil
				local angle, dis_multiplier = _angle_and_dis_chk(attention_info.handler, attention_info.settings)

				if angle then
					local attention_pos = attention_info.handler:get_detection_m_pos()
					local vis_ray = World:raycast("ray", my_pos, attention_pos, "slot_mask", data.visibility_slotmask, "ray_type", "ai_vision")

					if not vis_ray or vis_ray.unit:key() == u_key then
						noticable = true
					end
				end

				local delta_prog = nil
				local dt = t - attention_info.prev_notice_chk_t

				if noticable then
					if angle == -1 then
						delta_prog = 1
					else
						local min_delay = my_data.detection.delay[1]
						local max_delay = my_data.detection.delay[2]
						local angle_mul_mod = 0.25 * math.min(angle / my_data.detection.angle_max, 1)
						local dis_mul_mod = 0.75 * dis_multiplier
						local notice_delay_mul = attention_info.settings.notice_delay_mul or 1

						if attention_info.settings.detection and attention_info.settings.detection.delay_mul then
							notice_delay_mul = notice_delay_mul * attention_info.settings.detection.delay_mul
						end

						local notice_delay_modified = math.lerp(min_delay * notice_delay_mul, max_delay, dis_mul_mod + angle_mul_mod)
						delta_prog = notice_delay_modified > 0 and dt / notice_delay_modified or 1
					end
				else
					delta_prog = dt * -0.125
				end

				attention_info.notice_progress = attention_info.notice_progress + delta_prog

				if attention_info.notice_progress > 1 then
					attention_info.notice_progress = nil
					attention_info.prev_notice_chk_t = nil
					attention_info.identified = true
					attention_info.release_t = t + attention_info.settings.release_delay
					attention_info.identified_t = t
					noticable = true

					data.logic.on_attention_obj_identified(data, u_key, attention_info)
				elseif attention_info.notice_progress < 0 then
					CopLogicBase._destroy_detected_attention_object_data(data, attention_info)

					noticable = false
				else
					noticable = attention_info.notice_progress
					attention_info.prev_notice_chk_t = t

					if data.cool and AIAttentionObject.REACT_SCARED <= attention_info.settings.reaction then
						managers.groupai:state():on_criminal_suspicion_progress(attention_info.unit, data.unit, noticable)
					end
				end

				if noticable ~= false and attention_info.settings.notice_clbk then
					attention_info.settings.notice_clbk(data.unit, noticable)
				end
			end

			if attention_info.identified then
				delay = math.min(delay, attention_info.settings.verification_interval)
				attention_info.nearly_visible = nil
				local verified, vis_ray = nil
				local attention_pos = attention_info.handler:get_detection_m_pos()
				local dis = mvector3.distance(data.m_pos, attention_info.m_pos)

				if dis < my_data.detection.dis_max * 1.2 and (not attention_info.settings.max_range or dis < attention_info.settings.max_range * (attention_info.settings.detection and attention_info.settings.detection.range_mul or 1) * 1.2) then
					local detect_pos = nil

					if attention_info.is_husk_player and attention_info.unit:anim_data().crouch then
						detect_pos = tmp_vec1

						mvector3.set(detect_pos, attention_info.m_pos)
						mvector3.add(detect_pos, tweak_data.player.stances.default.crouched.head.translation)
					else
						detect_pos = attention_pos
					end

					local in_FOV = not attention_info.settings.notice_requires_FOV or data.enemy_slotmask and attention_info.unit:in_slot(data.enemy_slotmask) or _angle_chk(attention_pos, dis, 0.8)

					if in_FOV then
						vis_ray = World:raycast("ray", my_pos, detect_pos, "slot_mask", data.visibility_slotmask, "ray_type", "ai_vision")

						if not vis_ray or vis_ray.unit:key() == u_key then
							verified = true
						end
					end

					attention_info.verified = verified
				end

				attention_info.dis = dis
				attention_info.vis_ray = vis_ray and vis_ray.dis or nil
				local is_ignored = false

				if attention_info.unit:movement() and attention_info.unit:movement().is_cuffed then
					is_ignored = attention_info.unit:movement():is_cuffed()
				end

				if is_ignored then
					CopLogicBase._destroy_detected_attention_object_data(data, attention_info)
				elseif verified then
					attention_info.release_t = nil
					attention_info.verified_t = t

					mvector3.set(attention_info.verified_pos, attention_pos)

					attention_info.last_verified_pos = mvector3.copy(attention_pos)
					attention_info.verified_dis = dis
				elseif data.enemy_slotmask and attention_info.unit:in_slot(data.enemy_slotmask) then
					if attention_info.criminal_record and AIAttentionObject.REACT_COMBAT <= attention_info.settings.reaction then
						if not is_detection_persistent and mvector3.distance(attention_pos, attention_info.criminal_record.pos) > 700 then
							CopLogicBase._destroy_detected_attention_object_data(data, attention_info)
						else
							delay = math.min(0.2, delay)
							attention_info.verified_pos = mvector3.copy(attention_info.criminal_record.pos)
							attention_info.verified_dis = dis

							if data.logic._chk_nearly_visible_chk_needed(data, attention_info, u_key) and attention_info.dis < 2000 then
								_nearly_visible_chk(attention_info, attention_pos)
							end
						end
					elseif attention_info.release_t and attention_info.release_t < t then
						CopLogicBase._destroy_detected_attention_object_data(data, attention_info)
					else
						attention_info.release_t = attention_info.release_t or t + attention_info.settings.release_delay
					end
				elseif attention_info.release_t and attention_info.release_t < t then
					CopLogicBase._destroy_detected_attention_object_data(data, attention_info)
				else
					attention_info.release_t = attention_info.release_t or t + attention_info.settings.release_delay
				end
			end
		end

		_chk_record_acquired_attention_importance_wgt(attention_info)
	end

	if player_importance_wgt then
		managers.groupai:state():set_importance_weight(data.key, player_importance_wgt)
	end

	return delay
end

function CopLogicBase.chk_start_action_dodge(data, reason)
	if not data.char_tweak.dodge or not data.char_tweak.dodge.occasions[reason] then
		return
	end

	if data.dodge_timeout_t and data.t < data.dodge_timeout_t or data.dodge_chk_timeout_t and data.t < data.dodge_chk_timeout_t or data.unit:movement():chk_action_forbidden("walk") then
		return
	end

	local dodge_tweak = data.char_tweak.dodge.occasions[reason]
	data.dodge_chk_timeout_t = TimerManager:game():time() + math.lerp(dodge_tweak.check_timeout[1], dodge_tweak.check_timeout[2], math.random())

	if dodge_tweak.chance == 0 or dodge_tweak.chance < math.random() then
		return
	end

	local rand_nr = math.random()
	local total_chance = 0
	local variation, variation_data = nil

	for test_variation, test_variation_data in pairs(dodge_tweak.variations) do
		total_chance = total_chance + test_variation_data.chance

		if test_variation_data.chance > 0 and rand_nr <= total_chance then
			variation = test_variation
			variation_data = test_variation_data

			break
		end
	end

	local dodge_dir = Vector3()
	local face_attention = nil
	local valid_directions_forward_and_back = nil

	if data.attention_obj and AIAttentionObject.REACT_COMBAT <= data.attention_obj.reaction then
		mvec3_set(dodge_dir, data.attention_obj.m_pos)
		mvec3_sub(dodge_dir, data.m_pos)
		mvector3.set_z(dodge_dir, 0)
		mvector3.normalize(dodge_dir)

		mvector3.cross(dodge_dir, dodge_dir, math.UP)	
	else
		mvector3.random_orthogonal(dodge_dir, math.UP)
	end

	local dodge_dir_reversed = false

	if math.random() < 0.5 then
		mvector3.negate(dodge_dir)

		dodge_dir_reversed = not dodge_dir_reversed
	end

	local prefered_space = 130
	local min_space = 90
	local ray_to_pos = tmp_vec1

	mvec3_set(ray_to_pos, dodge_dir)
	mvector3.multiply(ray_to_pos, 130)
	mvector3.add(ray_to_pos, data.m_pos)

	local ray_params = {
		trace = true,
		tracker_from = data.unit:movement():nav_tracker(),
		pos_to = ray_to_pos
	}
	local ray_hit1 = managers.navigation:raycast(ray_params)
	local dis = nil

	if ray_hit1 then
		local hit_vec = tmp_vec2

		mvec3_set(hit_vec, ray_params.trace[1])
		mvec3_sub(hit_vec, data.m_pos)
		mvec3_set_z(hit_vec, 0)

		dis = mvector3.length(hit_vec)

		mvec3_set(ray_to_pos, dodge_dir)
		mvector3.multiply(ray_to_pos, -130)
		mvector3.add(ray_to_pos, data.m_pos)

		ray_params.pos_to = ray_to_pos
		local ray_hit2 = managers.navigation:raycast(ray_params)

		if ray_hit2 then
			mvec3_set(hit_vec, ray_params.trace[1])
			mvec3_sub(hit_vec, data.m_pos)
			mvec3_set_z(hit_vec, 0)

			local prev_dis = dis
			dis = mvector3.length(hit_vec)

			if prev_dis < dis and min_space < dis then
				mvector3.negate(dodge_dir)

				dodge_dir_reversed = not dodge_dir_reversed
			end
		else
			mvector3.negate(dodge_dir)

			dis = nil
			dodge_dir_reversed = not dodge_dir_reversed
		end
	end

	if ray_hit1 and dis and dis < min_space then
		return
	end

	local dodge_side = nil

	if face_attention then
		if valid_directions_forward_and_back then
			if dodge_dir_reversed then
				dodge_side = "bwd"
			else
				dodge_side = "fwd"
			end
		elseif dodge_dir_reversed then
			dodge_side = "l"
		else
			dodge_side = "r"
		end
	else
		local fwd_dot = mvec3_dot(dodge_dir, data.unit:movement():m_fwd())
		local my_right = tmp_vec1

		mrotation.x(data.unit:movement():m_rot(), my_right)

		local right_dot = mvec3_dot(dodge_dir, my_right)

		if math.abs(fwd_dot) > 0.7071067690849 then
			if fwd_dot > 0 then
				dodge_side = "fwd"
			else
				dodge_side = "bwd"
			end
		elseif right_dot > 0 then
			dodge_side = "r"
		else
			dodge_side = "l"
		end
	end

	local body_part = 1
	local shoot_chance = variation_data.shoot_chance

	if shoot_chance and shoot_chance > 0 and math.random() < shoot_chance then
		body_part = 2
	end

	local action_data = {
		type = "dodge",
		body_part = body_part,
		variation = variation,
		side = dodge_side,
		direction = dodge_dir,
		timeout = variation_data.timeout,
		speed = data.char_tweak.dodge.speed,
		shoot_accuracy = variation_data.shoot_accuracy,
		blocks = {
			act = -1,
			tase = -1,
			bleedout = -1,
			dodge = -1,
			walk = -1,
			action = body_part == 1 and -1 or nil,
			aim = body_part == 1 and -1 or nil
		}
	}

	if variation ~= "side_step" then
		action_data.blocks.hurt = -1
		action_data.blocks.heavy_hurt = -1
	end

	local action = data.unit:movement():action_request(action_data)

	if action then
		local my_data = data.internal_data

		CopLogicAttack._cancel_cover_pathing(data, my_data)
		CopLogicAttack._cancel_charge(data, my_data)
		CopLogicAttack._cancel_expected_pos_path(data, my_data)
		CopLogicAttack._cancel_walking_to_cover(data, my_data, true)
	end

	return action
end