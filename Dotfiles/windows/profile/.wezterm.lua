-- Pull in the wezterm API
local wezterm = require 'wezterm'

-- This will hold the configuration.
local config = wezterm.config_builder()

-- This is where you actually apply your config choices.
config.default_prog = { "powershell.exe", "-NoLogo" }


-- For example, changing the initial geometry for new windows:
config.initial_cols = 120
config.initial_rows = 28

-- or, changing the font size and color scheme.
config.font_size = 14
config.color_scheme = 'AdventureTime'
config.window_background_opacity = 0.7
config.win32_system_backdrop = 'Acrylic'

-- Finally, return the configuration to wezterm:
return config