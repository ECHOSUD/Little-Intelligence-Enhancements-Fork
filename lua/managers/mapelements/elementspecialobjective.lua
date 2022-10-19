function ElementSpecialObjective:nav_link_delay()
	local original_value = self:_get_default_value_if_nil("interval")
	
	if original_value <= 0 or LIES.settings.nav_link_interval < 2 then
		return original_value
	end
	
	
	if LIES.settings.nav_link_interval > 3 then
		return -1
	else	
		local divide_by = LIES.settings.nav_link_interval
		
		return original_value / divide_by
	end
end