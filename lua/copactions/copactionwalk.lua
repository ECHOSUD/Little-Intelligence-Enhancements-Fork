local mvec3_set = mvector3.set
local mvec3_z = mvector3.z
local mvec3_set_z = mvector3.set_z
local mvec3_sub = mvector3.subtract
local mvec3_norm = mvector3.normalize
local mvec3_add = mvector3.add
local mvec3_mul = mvector3.multiply
local mvec3_lerp = mvector3.lerp
local mvec3_cpy = mvector3.copy
local mvec3_set_l = mvector3.set_length
local mvec3_dot = mvector3.dot
local mvec3_cross = mvector3.cross
local mvec3_dis = mvector3.distance
local mvec3_dis_sq = mvector3.distance_sq
local mvec3_len = mvector3.length
local mvec3_rot = mvector3.rotate_with

function CopActionWalk:_init()
	if not self:_sanitize() then
		return
	end

	self._init_called = true
	local action_desc = self._action_desc
	local common_data = self._common_data

	if self._is_civilian then
		print("common_data ", inspect(common_data))
	end

	if self._sync then
		if managers.groupai:state():all_AI_criminals()[common_data.unit:key()] then
			self._nav_link_invul = true
		end

		local nav_path = {}

		for i, nav_point in ipairs(self._nav_path) do
			if nav_point.x then
				table.insert(nav_path, nav_point)
			elseif alive(nav_point) then
				table.insert(nav_path, {
					element = nav_point:script_data().element,
					c_class = nav_point
				})
			else
				debug_pause_unit(self._unit, "dead nav_link", self._unit)

				return false
			end
		end

		self._nav_path = nav_path
	else
		local t_ins = table.insert
		local new_nav_points = self._simplified_path

		if new_nav_points then
			for _, nav_point in ipairs(new_nav_points) do
				t_ins(self._nav_path, nav_point.x and mvec3_cpy(nav_point) or nav_point)
			end
		end

		if not action_desc.interrupted or not self._nav_path[1].x then
			t_ins(self._nav_path, 1, mvec3_cpy(common_data.pos))
		else
			self._nav_path[1] = mvec3_cpy(common_data.pos)
		end

		for i, nav_point in ipairs(self._nav_path) do
			if not nav_point.x then
				function nav_point.element.value(element, name)
					return element[name]
				end

				function nav_point.element.nav_link_wants_align_pos(element)
					return element.from_idle
				end
			end
		end

		if not action_desc.host_stop_pos_ahead and self._nav_path[2] then
			local ray_params = {
				tracker_from = common_data.nav_tracker,
				pos_to = self._nav_point_pos(self._nav_path[2])
			}

			if managers.navigation:raycast(ray_params) then
				t_ins(self._nav_path, 2, mvec3_cpy(self._ext_movement:m_host_stop_pos()))

				self._host_stop_pos_ahead = true
			end
		end
	end

	if action_desc.path_simplified and action_desc.persistent then
		self._simplified_path = self._nav_path
	else
		local good_pos = mvector3.copy(common_data.pos)
		self._simplified_path = self._calculate_simplified_path(good_pos, self._nav_path, (not self._sync or self._common_data.stance.name == "ntl") and 3 or 2, self._sync, true)
	end

	if not self._simplified_path[2].x then
		self._next_is_nav_link = self._simplified_path[2]
	end

	self._curve_path_index = 1

	self:_chk_start_anim(CopActionWalk._nav_point_pos(self._simplified_path[2]))

	if self._start_run then
		self:_set_updator("_upd_start_anim_first_frame")
	end

	if not self._start_run_turn and mvec3_dis(self._nav_point_pos(self._simplified_path[2]), self._simplified_path[1]) > 400 and self._ext_base:lod_stage() == 1 then
		self._curve_path = self:_calculate_curved_path(self._simplified_path, 1, 1)
	else
		self._curve_path = {
			self._simplified_path[1],
			mvec3_cpy(self._nav_point_pos(self._simplified_path[2]))
		}
	end

	if #self._simplified_path == 2 and not self._was_interrupted and not self._NO_RUN_STOP and not self._no_walk and self._haste ~= "walk" and mvec3_dis(self._curve_path[2], self._curve_path[1]) >= 210 then
		self._chk_stop_dis = 210
	end

	if Network:is_server() then
		local sync_yaw = 0

		if self._end_rot then
			local yaw = self._end_rot:yaw()

			if yaw < 0 then
				yaw = 360 + yaw
			end

			sync_yaw = 1 + math.ceil(yaw * 254 / 360)
		end

		local sync_haste = self._haste == "walk" and 1 or 2
		local next_nav_point = self._nav_point_pos(self._simplified_path[2])
		local pose_code = nil

		if not action_desc.pose then
			pose_code = 0
		elseif action_desc.pose == "stand" then
			pose_code = 1
		else
			pose_code = 2
		end

		local end_pose_code = nil

		if not action_desc.end_pose then
			end_pose_code = 0
		elseif action_desc.end_pose == "stand" then
			end_pose_code = 1
		else
			end_pose_code = 2
		end

		self._ext_network:send("action_walk_start", self._nav_point_pos(next_nav_point), 1, 0, false, sync_haste, sync_yaw, self._no_walk and true or false, self._no_strafe and true or false, pose_code, end_pose_code)
	else
		local pose = action_desc.pose

		if pose and not self._unit:anim_data()[pose] then
			if pose == "stand" then
				local action, success = CopActionStand:new(action_desc, self._common_data)
			else
				local action, success = CopActionCrouch:new(action_desc, self._common_data)
			end
		end
	end

	if Network:is_server() then
		self._unit:brain():rem_pos_rsrv("stand")
		self._unit:brain():add_pos_rsrv("move_dest", {
			radius = 30,
			position = mvector3.copy(self._simplified_path[#self._simplified_path])
		})
	end

	return true
end

local tmp_vec1 = Vector3()
local tmp_vec2 = Vector3()
local tmp_vec3 = Vector3()
local tmp_vec4 = Vector3()
local tmp_vec5 = Vector3()
local tmp_vec6 = Vector3()

local diagonals = {
    tmp_vec1,
    tmp_vec2,
    tmp_vec5,
    tmp_vec6
}

function CopActionWalk._apply_padding_to_simplified_path(path)
	local dim_mag = 212.132

	mvector3.set_static(tmp_vec1, dim_mag, dim_mag, 0)
	mvector3.set_static(tmp_vec2, dim_mag, -dim_mag, 0)
	mvector3.set_static(tmp_vec5, dim_mag, 0, 0)
	mvector3.set_static(tmp_vec6, 0, dim_mag, 0)

	local index = 2
	local offset = tmp_vec3
	local to_pos = tmp_vec4

	while index < #path do
		local pos = path[index]

		if pos.x then
			for _, diagonal in ipairs(diagonals) do
				mvec3_set(to_pos, pos)
				mvec3_add(to_pos, diagonal)

				local col_pos, trace = CopActionWalk._chk_shortcut_pos_to_pos(pos, to_pos, true)

				mvec3_set(offset, trace[1])
				mvec3_set(to_pos, pos)
				mvec3_mul(diagonal, -1)
				mvec3_add(to_pos, diagonal)

				col_pos, trace = CopActionWalk._chk_shortcut_pos_to_pos(pos, to_pos, true)

				mvec3_lerp(offset, offset, trace[1], 0.5)

				local ray_fwd = CopActionWalk._chk_shortcut_pos_to_pos(offset, CopActionWalk._nav_point_pos(path[index + 1]))

				if ray_fwd then
					break
				else
					local ray_bwd = CopActionWalk._chk_shortcut_pos_to_pos(offset, CopActionWalk._nav_point_pos(path[index - 1]))

					if ray_bwd then
						break
					end
				end

				mvec3_set(pos, offset)
			end

			index = index + 1
		else
			index = index + 2
		end
	end
end

function CopActionWalk:append_path_mid_logic(path)
	--local line = Draw:brush(Color.yellow:with_alpha(1), 3)
		
	if line then
		local simpath = self._simplified_path
		for i = 1, #simpath do
			if simpath[i + 1] then
				if simpath[i].z and simpath[i + 1].z then
					line:cylinder(simpath[i], simpath[i + 1], 5)
				elseif simpath[i].z then
					line:sphere(simpath[i], 20)
				elseif simpath[i + 1].z then
					line:sphere(simpath[i + 1], 20)
				elseif simpath[i - 1] and simpath[i - 1].z then
					line:sphere(simpath[i - 1], 20)
				end
			end
		end
	end

	local nav_path = {}
		
	for i = 1, #path do
		local nav_point = path[i]

		if nav_point.x then
			nav_path[#nav_path + 1] = nav_point
		elseif alive(nav_point) then
			nav_path[#nav_path + 1] = {
				element = nav_point:script_data().element,
				c_class = nav_point
			}
		else
			return
		end
	end

	for i = 1, #nav_path do
		local nav_point = nav_path[i]
		table.insert(self._simplified_path, nav_point)
	end
	
	if not self._simplified_path[1].x then
		self._simplified_path[1] = self._simplified_path[1].c_class:end_position()
	end
	
	if #self._simplified_path == 2 then
		table.insert(self._simplified_path, 2, path[1])
	end

	if self._curve_path and self._simplified_path[2] ~= self._curve_path[#self._curve_path] then
		table.insert(self._simplified_path, 2, self._curve_path[#self._curve_path])
	end

	self._unit:brain():add_pos_rsrv("move_dest", {
		radius = 30,
		position = mvector3.copy(self._simplified_path[#self._simplified_path])
	})
	
	--local line2 = Draw:brush(Color.blue:with_alpha(0.5), 6)
		
	if line2 then
		local simpath = self._simplified_path
		for i = 1, #simpath do
			if simpath[i + 1] then
				if simpath[i].z and simpath[i + 1].z then
					line2:cylinder(simpath[i], simpath[i + 1], 5)
				elseif simpath[i].z then
					line2:sphere(simpath[i], 20)
				elseif simpath[i + 1].z then
					line2:sphere(simpath[i + 1], 20)
				elseif simpath[i - 1] and simpath[i - 1].z then
					line2:sphere(simpath[i - 1], 20)
				end
			end
		end
	end
	
	return true
end
