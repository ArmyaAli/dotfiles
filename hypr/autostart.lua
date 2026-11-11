-- Extra autostart processes.
-- o.launch_on_start("my-service")

-- Open the Mushroom Grove dashboard (home) on login.
o.exec_on_start("sleep 1; hyprctl dispatch 'hl.dsp.focus({ workspace = \"name:home\" })'")
