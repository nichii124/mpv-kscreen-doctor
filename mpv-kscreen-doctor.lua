--[[
	mpv-kscreen-doctor

Use kscreen-doctor to adjust the display's refresh rate to match the video's frame rate

	Author: Nicola Smaniotto <smaniotto.nicola@gmail.com>
	Version: 0.2.2
]]--

local mp = require "mp"
local utils = require "mp.utils"
local msg = require "mp.msg"

local function is_empty(t)
	return next(t) == nil
end

local MODESFILE = "/tmp/mpv-kscreen-doctor.modes"
local PIDFILE = "/tmp/mpv-kscreen-doctor.pid"

local function get_available()
	--[[
		Get the current resolution and the available modes
	]]--
	local command = {
		name = "subprocess",
		playback_only = false,
		capture_stdout = true,
		args = {
			"kscreen-doctor",
			"-j",
		},
	}
	-- get screen info in JSON format
	local r = mp.command_native(command)

	assert(r.status == 0, "Could not detect display config")

	local raw_json = r.stdout

	-- https://stackoverflow.com/q/42139363
	-- in case parse_json is removed
	local parsed = utils.parse_json(raw_json)

	local enabled_outputs = {}
	for index, output in pairs(parsed.outputs) do
		if output.enabled then
			table.insert(enabled_outputs, {
				index = index,
				id = output.id,
			})
		end
	end

	local resolutions = {}
	local valid_modes = {}
	local old_modes = {}

	for _, output in pairs(enabled_outputs) do
		local current_mode = parsed.outputs[output.index].currentModeId

		old_modes[output.id] = current_mode

		-- go through the modes and find the current one
		local target = {}
		local all_modes = parsed.outputs[output.index].modes

		-- first find the resolution
		for _, mode in pairs(all_modes) do
			if mode.id == current_mode then
				target = mode.size
				break
			end
		end

		-- then find the available refresh rates for this resolution
		local good_modes = {}
		for _, mode in pairs(all_modes) do
			local s = mode.size
			if target.width == s.width and target.height == s.height then
				table.insert(good_modes, {
					id = mode.id,
					rate = mode.refreshRate,
				})
			end
		end

		table.insert(resolutions, { output = output, resolution = target })
		table.insert(valid_modes, { output = output, modes = good_modes })
	end

       -- save the modes if no one already did
	local modesfile = io.open(MODESFILE, "r")
	if not modesfile then
		-- there is nothing saved yet
		modesfile = io.open(MODESFILE, "w")
		for output, mode in pairs(old_modes) do
			modesfile:write(string.format("%d %d\n", output, mode))
		end
	end
	modesfile:close()

	return resolutions, valid_modes
end

local function best_fit(target, options)
	--[[
		Try to find the mode that best approximates the target refresh rate
	]]--
	local best = { distance = math.huge, id = nil }

	for mul = 1, 3 do
		for _, mode in pairs(options) do
			local offset = math.abs(target * mul - mode.rate)
			if offset < best.distance then
				best = {
					distance = offset,
					id = mode.id,
				}
			end
		end
	end

	return best.id
end

local function kscreen_doctor_set_mode(modes)
	--[[
		Invoke kscreen-doctor and set the mode ids
	]]--
	local command = {
		name = "subprocess",
		playback_only = false,
		capture_stderr = true, -- prints here, don't want to log that
		args = {
			"kscreen-doctor",
		},
	}
	for output, id in pairs(modes) do
		msg.info(string.format("Setting output %d to mode %d", output , id))
		local arg = string.format("output.%d.mode.%d", output , id)
		table.insert(command.args, arg)
	end
	-- set the modes
	local r = mp.command_native(command)

	assert(r.status == 0, "Could not change display rate")
end

local function set_rate()
	--[[
		Set the best fitting display rates
	]]--
	local _, modes = get_available()

	local container_fps = mp.get_property_native("container-fps")
	if not container_fps then
		-- nothing to do
		return
	end

	local best_modes = {}
	for _, mode in pairs(modes) do
		local best_mode = best_fit(container_fps, mode.modes)
		best_modes[mode.output.id] = best_mode
	end

	kscreen_doctor_set_mode(best_modes)
end

local function restore_old()
	--[[
		If we know the previous modes, restore them
	]]--
       local modesfile = io.open(MODESFILE, "r")
       if not modesfile then
               -- nothing was ever saved
               return
       end

	local old_modes = {}
        while true do
                local output, mode = modesfile:read("*n", "*n")
                if not output then
                        break
                end
                old_modes[output] = mode
        end
        modesfile:close()

        if is_empty(old_modes) then
                -- we don't have a saved rate, nothing to do
                return
        end

	msg.info("Restoring previous modes")
	kscreen_doctor_set_mode(old_modes)
	os.remove(MODESFILE)
end

local function save_pids(list)
	--[[
		Write the new pidfile
	]]--
	local pidfile = io.open(PIDFILE, "w")
	for _, pid in pairs(list) do
		pidfile:write(string.format("%d\n", pid))
	end
	pidfile:close()
end

local function check_active(pids, my_pid)
	--[[
		Check if the pids in the list are still valid
		If we receive my_pid, remove it from the list
	]]--
	for index, pid in pairs(pids) do
		local command = io.popen(string.format("ps -p %d -o comm=", pid))
		if command:read("*l") ~= "mpv" or pid == my_pid then
			-- old pid or our own, remove it
			pids[index] = nil
		end
	end
	return pids
end

local function clean_shutdown()
	--[[
		Revert our changes
	]]--
	local pidfile = assert(io.open(PIDFILE, "r"), "Missing pidfile")

	local pids = {}
	for line in pidfile:lines() do
		table.insert(pids, tonumber(line))
	end
	local my_pid = mp.get_property_native("pid")

	-- check if processes are still active
	pids = check_active(pids, my_pid)

	if is_empty(pids) then
		-- we are the last instance
		os.remove(PIDFILE)
		restore_old()
	else
		-- write back the list, removing us
		save_pids(pids)
	end
end

-- set the pidfile path
local command = {
	name = "subprocess",
	playback_only = false,
	capture_stdout = true,
	args = {
		"id",
		"-u",
	},
}
local r = mp.command_native(command)

if r.status == 0 then
	local uid = tonumber(r.stdout)
	PIDFILE = string.format("/run/user/%d/mpv-kscreen-doctor.pid", uid)
else
	msg.warn("Could not get the current user id, the pidfile will be in /tmp")
end

-- update the pidfile on start
local pidfile = io.open(PIDFILE, "r")

if pidfile then
	-- the pidfile exists, update it
	local pids = {}
	for line in pidfile:lines() do
		table.insert(pids, tonumber(line))
	end
	pidfile:close()

	-- check if processes are still active
	pids = check_active(pids)

	-- add us
	local my_pid = mp.get_property_native("pid")
	table.insert(pids, my_pid)

	-- write back the list, adding us
	save_pids(pids)
else
	-- there is no pidfile, we are number one
	local my_pid = mp.get_property_native("pid")
	save_pids{my_pid}
end

-- change the refresh rate when video fps changes
mp.observe_property("container-fps", "native", set_rate)

-- revert changes when the file ends
mp.register_event("shutdown", clean_shutdown)
