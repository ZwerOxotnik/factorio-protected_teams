local settings = {
	{
		type = "bool-setting",
		name = "PTZO_is_new_team_protected_by_default",
		default_value = true,
		setting_type = "runtime-global",
	}, {
		type = "bool-setting",
		name = "PTZO_is_afk_protection_on",
		default_value = true,
		setting_type = "runtime-global",
	}, {
		type = "bool-setting",
		name = "PTZO_is_offline_protection_on",
		default_value = true,
		setting_type = "runtime-global",
	}, {
		type = "int-setting",
		name = "PTZO_default_radius_protection",
		minimum_value = 0, default_value = 10,
		setting_type = "runtime-global",
	}, {
		type = "int-setting",
		name = "PTZO_default_max_radius_protection",
		minimum_value = 0, default_value = 100,
		setting_type = "runtime-global",
	}, {
		type = "int-setting",
		name = "PTZO_default_build_radius_protection",
		minimum_value = 0, default_value = 150,
		setting_type = "runtime-global",
	}, {
		type = "double-setting",
		name = "PTZO_default_speed_protection",
		minimum_value = 0, default_value = 0.1,
		setting_type = "runtime-global",
	}, {
		type = "int-setting",
		name = "PTZO_init_time_protection",
		minimum_value = 0, default_value = 60, -- mins
		setting_type = "runtime-global",
	}, {
		type = "int-setting",
		name = "PTZO_max_time_protection",
		minimum_value = 0, default_value = 60 * 24, -- mins
		setting_type = "runtime-global",
	}, {
		type = "int-setting",
		name = "PTZO_min_afk_time_for_protection",
		minimum_value = 0, default_value = 1, -- mins
		setting_type = "runtime-global",
	}, {
		type = "int-setting",
		name = "PTZO_disable_protection_in_N_mins_after_joining",
		minimum_value = 0, default_value = 1, -- mins
		setting_type = "runtime-global",
	},
}

data:extend(settings)
