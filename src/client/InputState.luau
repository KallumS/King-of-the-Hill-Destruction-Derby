--!strict
-- Merges keyboard, gamepad and on-screen touch buttons into one set of
-- driving inputs that CarController reads every physics step.
--
-- Keyboard:  W/S or Up/Down = throttle/brake, A/D or Left/Right = steer,
--            Space = handbrake (drift), R = flip car, Q/E = cycle spectate
-- Gamepad:   RT/LT = throttle/brake, left stick = steer, A/B = handbrake,
--            Y = flip, L1/R1 = cycle spectate

local UserInputService = game:GetService("UserInputService")

local InputState = {
	throttle = 0,
	steer = 0,
	handbrake = false,
	-- Touch buttons write into these; they are merged with keys each frame.
	touch = {
		gas = false,
		brake = false,
		left = false,
		right = false,
		drift = false,
	},
}

local gamepadThrottle = 0
local gamepadBrake = 0
local gamepadSteer = 0

local flipListeners: { () -> () } = {}
local cycleListeners: { (direction: number) -> () } = {}

local DEADZONE = 0.15

local function key(code: Enum.KeyCode): boolean
	return UserInputService:IsKeyDown(code)
end

function InputState.Update()
	if UserInputService:GetFocusedTextBox() then
		InputState.throttle = 0
		InputState.steer = 0
		InputState.handbrake = false
		return
	end

	local touch = InputState.touch
	local forward = (key(Enum.KeyCode.W) or key(Enum.KeyCode.Up) or touch.gas) and 1 or 0
	local back = (key(Enum.KeyCode.S) or key(Enum.KeyCode.Down) or touch.brake) and 1 or 0
	local left = (key(Enum.KeyCode.A) or key(Enum.KeyCode.Left) or touch.left) and 1 or 0
	local right = (key(Enum.KeyCode.D) or key(Enum.KeyCode.Right) or touch.right) and 1 or 0

	local throttle = math.clamp(forward - back + gamepadThrottle - gamepadBrake, -1, 1)
	local steer = math.clamp(right - left + gamepadSteer, -1, 1)

	InputState.throttle = throttle
	InputState.steer = steer
	InputState.handbrake = key(Enum.KeyCode.Space)
		or key(Enum.KeyCode.LeftShift)
		or touch.drift
		or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonA)
		or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonB)
end

function InputState.OnFlip(callback: () -> ())
	table.insert(flipListeners, callback)
end

function InputState.OnCycleSpectate(callback: (direction: number) -> ())
	table.insert(cycleListeners, callback)
end

function InputState.FireFlip()
	for _, callback in flipListeners do
		task.spawn(callback)
	end
end

function InputState.FireCycle(direction: number)
	for _, callback in cycleListeners do
		task.spawn(callback, direction)
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	local code = input.KeyCode
	if code == Enum.KeyCode.R or code == Enum.KeyCode.ButtonY then
		InputState.FireFlip()
	elseif code == Enum.KeyCode.Q or code == Enum.KeyCode.ButtonL1 then
		InputState.FireCycle(-1)
	elseif code == Enum.KeyCode.E or code == Enum.KeyCode.ButtonR1 then
		InputState.FireCycle(1)
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.Gamepad1 then
		return
	end
	if input.KeyCode == Enum.KeyCode.Thumbstick1 then
		local x = input.Position.X
		gamepadSteer = if math.abs(x) > DEADZONE then x else 0
	elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
		gamepadThrottle = input.Position.Z
	elseif input.KeyCode == Enum.KeyCode.ButtonL2 then
		gamepadBrake = input.Position.Z
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.Gamepad1 then
		return
	end
	if input.KeyCode == Enum.KeyCode.Thumbstick1 then
		gamepadSteer = 0
	elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
		gamepadThrottle = 0
	elseif input.KeyCode == Enum.KeyCode.ButtonL2 then
		gamepadBrake = 0
	end
end)

return InputState
