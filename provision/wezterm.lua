-- WezTerm configuration used only for agent workspace windows.
--
-- Start-Project.ps1 points WEZTERM_CONFIG_FILE at this file, so your personal
-- ~/.wezterm.lua is never modified and still governs every other terminal you
-- open. This inherits it wholesale - theme, font, opacity - and changes one
-- thing: the window title.
--
-- Without this, every project window is titled "wslhost.exe". On Windows
-- WezTerm derives a title from the local process tree, and the only local
-- process is the WSL host helper; it cannot see what is actually running
-- inside the instance. With several projects open at once - the whole point of
-- moving off Windows Sandbox - the taskbar becomes unusable.

local wezterm = require 'wezterm'

-- Inherit the user's own configuration. If it is missing or malformed, fall
-- back to defaults rather than failing to open a terminal at all.
local ok, config = pcall(dofile, wezterm.home_dir .. '/.wezterm.lua')
if not ok or type(config) ~= 'table' then
  config = wezterm.config_builder()
end

-- The project name arrives as a user var, not as an OSC window title. herdr is
-- a multiplexer and manages the pane title itself, so a title set before
-- exec'ing it is immediately overwritten. User vars are separate state that
-- the program in the pane does not touch.
local function project_of(pane)
  if pane and pane.user_vars then
    local name = pane.user_vars.agentdev_project
    if name and name ~= '' then
      return name
    end
  end
  return nil
end

wezterm.on('format-window-title', function(tab)
  local name = project_of(tab.active_pane)
  if name then
    return name .. '  -  agent workspace'
  end
  -- Not an agent workspace pane: keep WezTerm's normal behaviour.
  return tab.active_pane.title
end)

wezterm.on('format-tab-title', function(tab)
  local name = project_of(tab.active_pane)
  if name then
    return ' ' .. name .. ' '
  end
  return ' ' .. tab.active_pane.title .. ' '
end)

return config
