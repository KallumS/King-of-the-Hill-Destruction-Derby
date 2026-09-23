--!strict
-- All 2D UI, built in code: lobby panel, car select, race HUD (timer, ramp
-- status, health, speed, drift charge, parking progress), kill feed,
-- off-screen trailer arrow, spectate bar, results banner and touch controls.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CarCatalog = require(Shared:WaitForChild("CarCatalog"))
local CarBuilder = require(Shared:WaitForChild("CarBuilder"))

local Client = script.Parent
local CarController = require(Client:WaitForChild("CarController"))
local InputState = require(Client:WaitForChild("InputState"))

local player = Players.LocalPlayer

local Hud = {}

local COLORS = {
	panel = Color3.fromRGB(20, 20, 26),
	accent = Color3.fromRGB(255, 196, 0),
	danger = Color3.fromRGB(230, 60, 50),
	good = Color3.fromRGB(80, 210, 110),
	text = Color3.fromRGB(245, 245, 245),
	muted = Color3.fromRGB(170, 170, 180),
}

local function new(className: string, props: { [string]: any }, children: { Instance }?): any
	local instance = Instance.new(className)
	for key, value in props do
		if key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if props.Parent then
		instance.Parent = props.Parent
	end
	return instance
end

local function corner(radius: number): UICorner
	return new("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function stroke(thickness: number, color: Color3?): UIStroke
	return new("UIStroke", {
		Thickness = thickness,
		Color = color or Color3.new(0, 0, 0),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function label(props: { [string]: any }): TextLabel
	local defaults: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextColor3 = COLORS.text,
		TextScaled = true,
		TextStrokeTransparency = 0.6,
	}
	for key, value in props do
		defaults[key] = value
	end
	return new("TextLabel", defaults)
end

local function formatTime(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- UI references
local gui: ScreenGui
local gameState: Folder
local selectRemote: RemoteEvent

local topBar: Frame
local phaseLabel: TextLabel
local timerLabel: TextLabel
local rampLabel: TextLabel
local aliveLabel: TextLabel
local alertLabel: TextLabel

local centerLabel: TextLabel
local subCenterLabel: TextLabel
local centerUntil = 0

local lobbyPanel: Frame
local lobbyStatus: TextLabel

local selectPanel: Frame
local selectTimer: TextLabel
local lockButton: TextButton
local cards: { [string]: { frame: Frame, model: Model, viewport: ViewportFrame } } = {}
local selectedId: string? = nil
local locked = false

local drivePanel: Frame
local healthFill: Frame
local healthText: TextLabel
local speedText: TextLabel
local driftFill: Frame
local driftFrame: Frame
local flipHint: TextLabel

local parkFrame: Frame
local parkFill: Frame
local parkText: TextLabel

local spectateFrame: Frame
local spectateName: TextLabel

local feedFrame: Frame

local arrow: Frame
local arrowDistance: TextLabel

local resultsPanel: Frame
local resultsTitle: TextLabel
local resultsSub: TextLabel

local touchFrame: Frame?

-- State pushed in from Main
local ownCar: Model? = nil
local spectatingModel: Model? = nil
local spectatingLabel: string? = nil

function Hud.SetOwnCar(model: Model?)
	ownCar = model
end

function Hud.SetSpectating(model: Model?, text: string?)
	spectatingModel = model
	spectatingLabel = text
end

function Hud.ShowCenter(text: string, sub: string?, duration: number, color: Color3?)
	centerLabel.Text = text
	centerLabel.TextColor3 = color or COLORS.accent
	subCenterLabel.Text = sub or ""
	centerUntil = os.clock() + duration
end

local function buildTopBar()
	topBar = new("Frame", {
		Name = "TopBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(420, 64),
		BackgroundColor3 = COLORS.panel,
		BackgroundTransparency = 0.25,
		Parent = gui,
	}, { corner(12) })
	phaseLabel = label({
		Size = UDim2.new(1, -20, 0, 18),
		Position = UDim2.fromOffset(10, 6),
		TextColor3 = COLORS.muted,
		Text = "",
		Parent = topBar,
	})
	timerLabel = label({
		Size = UDim2.new(0.5, -10, 0, 32),
		Position = UDim2.fromOffset(10, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.FredokaOne,
		Text = "",
		Parent = topBar,
	})
	rampLabel = label({
		Size = UDim2.new(0.5, -10, 0, 24),
		Position = UDim2.new(0.5, 0, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "",
		Parent = topBar,
	})
	aliveLabel = label({
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.new(0, 200, 0, 20),
		Position = UDim2.new(0.5, 0, 1, 6),
		TextColor3 = COLORS.text,
		Text = "",
		Parent = topBar,
	})
	alertLabel = label({
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.new(0, 520, 0, 28),
		Position = UDim2.new(0.5, 0, 1, 30),
		TextColor3 = COLORS.danger,
		Font = Enum.Font.FredokaOne,
		TextStrokeTransparency = 0,
		Text = "",
		Parent = topBar,
	})
end

local function buildCenter()
	centerLabel = label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.33),
		Size = UDim2.new(0.8, 0, 0, 90),
		Font = Enum.Font.FredokaOne,
		TextStrokeTransparency = 0,
		Text = "",
		Parent = gui,
	})
	subCenterLabel = label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.33, 50),
		Size = UDim2.new(0.7, 0, 0, 32),
		TextStrokeTransparency = 0.2,
		Text = "",
		Parent = gui,
	})
end

local function buildLobby()
	lobbyPanel = new("Frame", {
		Name = "Lobby",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromOffset(560, 380),
		BackgroundColor3 = COLORS.panel,
		BackgroundTransparency = 0.15,
		Parent = gui,
	}, {
		corner(16),
		new("UISizeConstraint", { MaxSize = Vector2.new(560, 380) }),
	})
	label({
		Size = UDim2.new(1, -30, 0, 44),
		Position = UDim2.fromOffset(15, 14),
		Font = Enum.Font.FredokaOne,
		TextColor3 = COLORS.accent,
		Text = "KING OF THE HILL",
		Parent = lobbyPanel,
	})
	label({
		Size = UDim2.new(1, -30, 0, 22),
		Position = UDim2.fromOffset(15, 58),
		TextColor3 = COLORS.text,
		Text = "DESTRUCTION DERBY",
		Parent = lobbyPanel,
	})
	lobbyStatus = label({
		Size = UDim2.new(1, -30, 0, 26),
		Position = UDim2.fromOffset(15, 92),
		TextColor3 = COLORS.good,
		Text = "",
		Parent = lobbyPanel,
	})
	local help = label({
		Size = UDim2.new(1, -40, 0, 230),
		Position = UDim2.fromOffset(20, 130),
		TextScaled = false,
		TextSize = 16,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Font = Enum.Font.Gotham,
		TextStrokeTransparency = 1,
		RichText = true,
		Parent = lobbyPanel,
	})
	help.Text = table.concat({
		"<b>Goal:</b> catch the flatbed truck, drive up its ramp and park inside the yellow bay. "
			.. "Hold it there — lined up, facing the cab, moving with the truck — until the bar fills. First to park wins.",
		"",
		"<b>The catch:</b> the tailgate stays up for the first "
			.. Config.Match.RampLockTime
			.. "s, the truck brake-checks and sways, and everyone else is trying to wreck you.",
		"",
		"<b>Drive:</b> W/S or triggers  ·  <b>Steer:</b> A/D or stick",
		"<b>Drift:</b> hold Space / A — release after a long drift for a boost",
		"<b>Flip:</b> R / Y  ·  <b>Spectate:</b> Q / E when wrecked",
		"Hit rivals with your front bumper — side and rear hits hurt more.",
	}, "\n")
end

local function selectCar(id: string, lock: boolean)
	if locked then
		return
	end
	selectedId = id
	selectRemote:FireServer(id, lock)
	if lock then
		locked = true
	end
	for carId, card in cards do
		local strokeObject = card.frame:FindFirstChildOfClass("UIStroke")
		if strokeObject then
			strokeObject.Color = if carId == selectedId then COLORS.accent else Color3.fromRGB(60, 60, 70)
			strokeObject.Thickness = if carId == selectedId then 4 else 2
		end
	end
end

local function buildCarSelect()
	selectPanel = new("Frame", {
		Name = "CarSelect",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.new(0.94, 0, 0, 380),
		BackgroundColor3 = COLORS.panel,
		BackgroundTransparency = 0.1,
		Visible = false,
		Parent = gui,
	}, {
		corner(16),
		new("UISizeConstraint", { MaxSize = Vector2.new(1100, 380) }),
	})
	label({
		Size = UDim2.new(1, -30, 0, 36),
		Position = UDim2.fromOffset(15, 10),
		Font = Enum.Font.FredokaOne,
		TextColor3 = COLORS.accent,
		Text = "PICK YOUR DERBY CAR",
		Parent = selectPanel,
	})
	label({
		Size = UDim2.new(1, -30, 0, 18),
		Position = UDim2.fromOffset(15, 46),
		TextColor3 = COLORS.muted,
		Font = Enum.Font.Gotham,
		Text = "Every car has identical speed and handling — pick your style.",
		Parent = selectPanel,
	})
	selectTimer = label({
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(80, 30),
		Position = UDim2.new(1, -15, 0, 12),
		Font = Enum.Font.FredokaOne,
		Text = "",
		Parent = selectPanel,
	})

	local row = new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(15, 76),
		Size = UDim2.new(1, -30, 0, 230),
		Parent = selectPanel,
	}, {
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	for index, def in CarCatalog.List do
		local card = new("TextButton", {
			Name = def.Id,
			LayoutOrder = index,
			Size = UDim2.new(0.2, -8, 1, 0),
			BackgroundColor3 = Color3.fromRGB(34, 34, 42),
			AutoButtonColor = true,
			Text = "",
			Parent = row,
		}, { corner(12), stroke(2, Color3.fromRGB(60, 60, 70)) })

		local viewport = new("ViewportFrame", {
			Size = UDim2.new(1, -10, 0, 140),
			Position = UDim2.fromOffset(5, 5),
			BackgroundColor3 = def.BodyColor:Lerp(Color3.new(0, 0, 0), 0.7),
			Ambient = Color3.fromRGB(170, 170, 170),
			LightColor = Color3.fromRGB(255, 255, 255),
			LightDirection = Vector3.new(-1, -2, -1),
			Parent = card,
		}, { corner(10) })
		local model = CarBuilder.BuildPreview(def)
		model.Parent = viewport
		local camera = new("Camera", {
			FieldOfView = 40,
			CFrame = CFrame.lookAt(Vector3.new(20, 10, -24), Vector3.new(0, 1, 0)),
			Parent = viewport,
		})
		viewport.CurrentCamera = camera

		label({
			Size = UDim2.new(1, -10, 0, 26),
			Position = UDim2.fromOffset(5, 150),
			Font = Enum.Font.FredokaOne,
			TextColor3 = def.BodyColor:Lerp(Color3.new(1, 1, 1), 0.35),
			Text = def.DisplayName,
			Parent = card,
		})
		label({
			Size = UDim2.new(1, -14, 0, 44),
			Position = UDim2.fromOffset(7, 178),
			Font = Enum.Font.Gotham,
			TextScaled = false,
			TextSize = 13,
			TextWrapped = true,
			TextColor3 = COLORS.muted,
			TextStrokeTransparency = 1,
			Text = def.Tagline,
			Parent = card,
		})

		card.Activated:Connect(function()
			selectCar(def.Id, false)
		end)
		cards[def.Id] = { frame = card, model = model, viewport = viewport }
	end

	lockButton = new("TextButton", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(240, 48),
		BackgroundColor3 = COLORS.accent,
		Font = Enum.Font.FredokaOne,
		TextScaled = true,
		TextColor3 = Color3.fromRGB(20, 20, 20),
		Text = "LOCK IN",
		Parent = selectPanel,
	}, { corner(10), new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }) })
	lockButton.Activated:Connect(function()
		if not selectedId then
			selectCar(CarCatalog.List[1].Id, false)
		end
		if selectedId then
			selectCar(selectedId, true)
		end
	end)
end

local function buildDrivePanel()
	drivePanel = new("Frame", {
		Name = "Drive",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -16),
		Size = UDim2.fromOffset(280, 110),
		BackgroundColor3 = COLORS.panel,
		BackgroundTransparency = 0.3,
		Visible = false,
		Parent = gui,
	}, { corner(12) })
	speedText = label({
		Size = UDim2.new(1, -20, 0, 40),
		Position = UDim2.fromOffset(10, 6),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.FredokaOne,
		Text = "0 mph",
		Parent = drivePanel,
	})
	local healthBack = new("Frame", {
		Position = UDim2.fromOffset(10, 52),
		Size = UDim2.new(1, -20, 0, 20),
		BackgroundColor3 = Color3.fromRGB(50, 50, 55),
		Parent = drivePanel,
	}, { corner(6) })
	healthFill = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = COLORS.good,
		Parent = healthBack,
	}, { corner(6) })
	healthText = label({
		Size = UDim2.fromScale(1, 1),
		Text = "HEALTH 100",
		TextStrokeTransparency = 0.3,
		ZIndex = 2,
		Parent = healthBack,
	})
	driftFrame = new("Frame", {
		Position = UDim2.fromOffset(10, 80),
		Size = UDim2.new(1, -20, 0, 14),
		BackgroundColor3 = Color3.fromRGB(50, 50, 55),
		Parent = drivePanel,
	}, { corner(6) })
	driftFill = new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.fromRGB(80, 170, 255),
		Parent = driftFrame,
	}, { corner(6) })
	label({
		Size = UDim2.fromScale(1, 1),
		Text = "DRIFT BOOST",
		TextStrokeTransparency = 0.3,
		ZIndex = 2,
		Parent = driftFrame,
	})
	flipHint = label({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 0, -6),
		Size = UDim2.new(1, 0, 0, 22),
		TextColor3 = COLORS.accent,
		Text = "Press R / Y to flip your car",
		Visible = false,
		Parent = drivePanel,
	})
end

local function buildParkBar()
	parkFrame = new("Frame", {
		Name = "Parking",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -150),
		Size = UDim2.fromOffset(360, 44),
		BackgroundColor3 = COLORS.panel,
		BackgroundTransparency = 0.2,
		Visible = false,
		Parent = gui,
	}, { corner(10) })
	local back = new("Frame", {
		Position = UDim2.fromOffset(8, 24),
		Size = UDim2.new(1, -16, 0, 12),
		BackgroundColor3 = Color3.fromRGB(50, 50, 55),
		Parent = parkFrame,
	}, { corner(6) })
	parkFill = new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = COLORS.accent,
		Parent = back,
	}, { corner(6) })
	parkText = label({
		Position = UDim2.fromOffset(8, 3),
		Size = UDim2.new(1, -16, 0, 18),
		Text = "PARKING",
		Parent = parkFrame,
	})
end

local function buildSpectate()
	spectateFrame = new("Frame", {
		Name = "Spectate",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(420, 54),
		BackgroundColor3 = COLORS.panel,
		BackgroundTransparency = 0.2,
		Visible = false,
		Parent = gui,
	}, { corner(12) })
	local function arrowButton(text: string, x: number, anchor: number, direction: number)
		local button = new("TextButton", {
			AnchorPoint = Vector2.new(anchor, 0.5),
			Position = UDim2.new(x, if anchor == 0 then 6 else -6, 0.5, 0),
			Size = UDim2.fromOffset(60, 42),
			BackgroundColor3 = Color3.fromRGB(50, 50, 60),
			Font = Enum.Font.FredokaOne,
			TextScaled = true,
			TextColor3 = COLORS.text,
			Text = text,
			Parent = spectateFrame,
		}, { corner(8) })
		button.Activated:Connect(function()
			InputState.FireCycle(direction)
		end)
	end
	arrowButton("◀ Q", 0, 0, -1)
	arrowButton("E ▶", 1, 1, 1)
	spectateName = label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -150, 0, 30),
		Text = "",
		Parent = spectateFrame,
	})
end

local function buildFeed()
	feedFrame = new("Frame", {
		Name = "Feed",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 90),
		Size = UDim2.fromOffset(320, 200),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		new("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			Padding = UDim.new(0, 4),
		}),
	})
end

local function buildArrow()
	arrow = new("Frame", {
		Name = "TrailerArrow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(56, 56),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	label({
		Name = "Glyph",
		Size = UDim2.fromScale(1, 1),
		Font = Enum.Font.GothamBlack,
		TextColor3 = COLORS.accent,
		TextStrokeTransparency = 0,
		Text = "▲",
		Parent = arrow,
	})
	arrowDistance = label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.fromOffset(120, 20),
		Text = "",
		TextStrokeTransparency = 0,
		Parent = gui,
	})
	arrowDistance.Visible = false
end

local function buildResults()
	resultsPanel = new("Frame", {
		Name = "Results",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 110),
		Size = UDim2.fromOffset(620, 120),
		BackgroundColor3 = COLORS.panel,
		BackgroundTransparency = 0.15,
		Visible = false,
		Parent = gui,
	}, { corner(16), new("UISizeConstraint", { MaxSize = Vector2.new(620, 120) }) })
	resultsTitle = label({
		Size = UDim2.new(1, -30, 0, 56),
		Position = UDim2.fromOffset(15, 10),
		Font = Enum.Font.FredokaOne,
		TextColor3 = COLORS.accent,
		Text = "",
		Parent = resultsPanel,
	})
	resultsSub = label({
		Size = UDim2.new(1, -30, 0, 26),
		Position = UDim2.fromOffset(15, 74),
		TextColor3 = COLORS.text,
		Text = "",
		Parent = resultsPanel,
	})
end

local function buildTouch()
	if not UserInputService.TouchEnabled then
		return
	end
	local frame = new("Frame", {
		Name = "Touch",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	touchFrame = frame

	local function button(text: string, position: UDim2, size: number, field: string?, onPress: (() -> ())?)
		local b = new("TextButton", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = position,
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = Color3.fromRGB(30, 30, 36),
			BackgroundTransparency = 0.35,
			Font = Enum.Font.FredokaOne,
			TextScaled = true,
			TextColor3 = COLORS.text,
			Text = text,
			AutoButtonColor = false,
			Parent = frame,
		}, {
			corner(size // 2),
			new("UIPadding", {
				PaddingTop = UDim.new(0, 12),
				PaddingBottom = UDim.new(0, 12),
				PaddingLeft = UDim.new(0, 8),
				PaddingRight = UDim.new(0, 8),
			}),
		})
		b.InputBegan:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseButton1
			then
				if field then
					(InputState.touch :: any)[field] = true
				end
				b.BackgroundTransparency = 0.1
				if onPress then
					onPress()
				end
			end
		end)
		b.InputEnded:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseButton1
			then
				if field then
					(InputState.touch :: any)[field] = false
				end
				b.BackgroundTransparency = 0.35
			end
		end)
	end

	button("◀", UDim2.new(0, 70, 1, -90), 96, "left")
	button("▶", UDim2.new(0, 180, 1, -90), 96, "right")
	button("GAS", UDim2.new(1, -80, 1, -110), 110, "gas")
	button("BRAKE", UDim2.new(1, -200, 1, -70), 84, "brake")
	button("DRIFT", UDim2.new(1, -190, 1, -180), 84, "drift")
	button("FLIP", UDim2.new(1, -70, 1, -240), 64, nil, function()
		InputState.FireFlip()
	end)
end

function Hud.PushFeed(text: string, color: Color3?)
	for _, child in feedFrame:GetChildren() do
		if child:IsA("GuiObject") then
			child.LayoutOrder += 1
			if child.LayoutOrder > 5 then
				child:Destroy()
			end
		end
	end
	local entry = label({
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 0.35,
		BackgroundColor3 = COLORS.panel,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = color or COLORS.text,
		Text = text .. "  ",
		Parent = feedFrame,
	})
	corner(6).Parent = entry
	task.delay(7, function()
		if entry.Parent then
			entry:Destroy()
		end
	end)
end

local function phaseTitle(phase: string): string
	if phase == "Lobby" then
		return "LOBBY"
	elseif phase == "CarSelect" then
		return "CAR SELECT"
	elseif phase == "Countdown" then
		return "GET READY"
	elseif phase == "Racing" then
		return "CATCH THE TRAILER"
	elseif phase == "Results" then
		return "MATCH OVER"
	end
	return phase
end

local function findTrailerBay(): BasePart?
	local trailer = Workspace:FindFirstChild("Trailer")
	local bay = trailer and trailer:FindFirstChild("ParkingBay")
	if bay and bay:IsA("BasePart") then
		return bay
	end
	return nil
end

local function updateArrow(visible: boolean)
	local bay = findTrailerBay()
	local camera = Workspace.CurrentCamera
	if not visible or not bay or not camera then
		arrow.Visible = false
		arrowDistance.Visible = false
		return
	end
	local viewport = camera.ViewportSize
	local screenPoint, onScreen = camera:WorldToViewportPoint(bay.Position)
	local distance = (bay.Position - camera.CFrame.Position).Magnitude
	if onScreen and screenPoint.Z > 0 then
		arrow.Visible = false
		arrowDistance.Visible = false
		return
	end
	-- Project direction onto the screen plane and pin to an ellipse near the edge
	local relative = camera.CFrame:PointToObjectSpace(bay.Position)
	local direction = Vector2.new(relative.X, -relative.Y)
	if direction.Magnitude < 1e-3 then
		direction = Vector2.new(0, 1)
	end
	direction = direction.Unit
	local center = viewport / 2
	local radius = Vector2.new(viewport.X / 2 - 60, viewport.Y / 2 - 70)
	local position = center + Vector2.new(direction.X * radius.X, direction.Y * radius.Y)
	arrow.Position = UDim2.fromOffset(position.X, position.Y)
	arrow.Rotation = math.deg(math.atan2(direction.Y, direction.X)) + 90
	arrow.Visible = true
	arrowDistance.Position = UDim2.fromOffset(position.X, position.Y + 30)
	arrowDistance.Text = string.format("TRAILER %dm", math.floor(distance * 0.28))
	arrowDistance.Visible = true
end

-- Called every frame by Main
function Hud.Update()
	local phase = (gameState:GetAttribute("Phase") :: string?) or "Lobby"
	local endsAt = (gameState:GetAttribute("PhaseEndsAt") :: number?) or 0
	local serverNow = Workspace:GetServerTimeNow()
	local remaining = endsAt - serverNow
	local inMatch = player:GetAttribute("InMatch") == true

	phaseLabel.Text = phaseTitle(phase)
	timerLabel.Text = if endsAt > 0 then formatTime(remaining) else "--:--"

	-- Ramp status
	if phase == "Racing" then
		local unlockAt = (gameState:GetAttribute("RampUnlockAt") :: number?) or 0
		if serverNow < unlockAt then
			rampLabel.Text = "RAMP LOCKED " .. formatTime(unlockAt - serverNow)
			rampLabel.TextColor3 = COLORS.danger
		else
			rampLabel.Text = "RAMP OPEN"
			rampLabel.TextColor3 = COLORS.good
		end
		aliveLabel.Text = string.format(
			"%d / %d cars running",
			(gameState:GetAttribute("Alive") :: number?) or 0,
			(gameState:GetAttribute("Participants") :: number?) or 0
		)
	elseif phase == "Lobby" then
		rampLabel.Text = string.format(
			"%d / %d players",
			(gameState:GetAttribute("Waiting") :: number?) or 0,
			Config.Match.MaxPlayers
		)
		rampLabel.TextColor3 = COLORS.text
		aliveLabel.Text = ""
	else
		rampLabel.Text = ""
		aliveLabel.Text = ""
	end

	-- Who is close to parking? Everyone should know so they can go ram them.
	local leaderName: string? = nil
	local leaderProgress = 0
	local cars = Workspace:FindFirstChild("Cars")
	if cars and phase == "Racing" then
		for _, model in cars:GetChildren() do
			local progress = (model:GetAttribute("ParkProgress") :: number?) or 0
			if progress > leaderProgress then
				leaderProgress = progress
				leaderName = model:GetAttribute("OwnerName") :: string?
			end
		end
	end
	if leaderName and leaderProgress > 0.25 then
		alertLabel.Text =
			string.format("⚠ %s IS PARKING — %d%% ⚠", string.upper(leaderName), leaderProgress * 100)
	else
		alertLabel.Text = ""
	end

	-- Lobby
	lobbyPanel.Visible = phase == "Lobby"
	if phase == "Lobby" then
		local waiting = (gameState:GetAttribute("Waiting") :: number?) or 0
		local minPlayers = (gameState:GetAttribute("MinPlayers") :: number?) or 1
		if endsAt > 0 then
			lobbyStatus.Text = "Match starting in " .. math.max(0, math.ceil(remaining)) .. "s"
		else
			lobbyStatus.Text = string.format("Waiting for players (%d/%d needed)", waiting, minPlayers)
		end
	end

	-- Car select
	local showSelect = phase == "CarSelect" and inMatch
	if showSelect and not selectPanel.Visible then
		locked = false
		selectedId = player:GetAttribute("SelectedCar") :: string?
		if selectedId then
			selectCar(selectedId, false)
		end
	end
	selectPanel.Visible = showSelect
	if showSelect then
		selectTimer.Text = tostring(math.max(0, math.ceil(remaining)))
		lockButton.Text = if locked then "LOCKED IN ✓" else "LOCK IN"
		lockButton.BackgroundColor3 = if locked then COLORS.good else COLORS.accent
		for _, card in cards do
			card.model:PivotTo(CFrame.Angles(0, os.clock() * 0.6, 0))
		end
	end
	if phase == "CarSelect" and not inMatch then
		subCenterLabel.Text = "Match is full — you'll spectate this round"
	end

	-- Countdown
	if phase == "Countdown" then
		local n = math.ceil(remaining)
		if n > 0 then
			centerLabel.Text = tostring(n)
			centerLabel.TextColor3 = COLORS.accent
			subCenterLabel.Text = "Catch the trailer!"
			centerUntil = os.clock() + 0.2
		end
	end

	-- Own car HUD
	local car = ownCar
	local alive = car ~= nil and car.Parent ~= nil and car:GetAttribute("Destroyed") ~= true
	local driving = alive and (phase == "Racing" or phase == "Countdown")
	drivePanel.Visible = driving
	if driving and car then
		local health = (car:GetAttribute("Health") :: number?) or 0
		local maxHealth = (car:GetAttribute("MaxHealth") :: number?) or 100
		local ratio = math.clamp(health / maxHealth, 0, 1)
		healthFill.Size = UDim2.fromScale(ratio, 1)
		healthFill.BackgroundColor3 = if ratio > 0.55
			then COLORS.good
			elseif ratio > 0.25 then COLORS.accent
			else COLORS.danger
		healthText.Text = "HEALTH " .. math.ceil(health)
		local state = CarController.State
		speedText.Text = string.format("%d mph", math.floor(state.speed * 0.68))
		driftFill.Size = UDim2.fromScale(state.driftCharge, 1)
		driftFill.BackgroundColor3 = if state.boosting
			then Color3.fromRGB(255, 120, 40)
			elseif state.driftCharge >= 1 then COLORS.accent
			else Color3.fromRGB(80, 170, 255)
		flipHint.Visible = state.canFlip
	end
	if touchFrame then
		touchFrame.Visible = alive and phase == "Racing"
	end

	-- Parking progress for whoever we are watching
	local watched = if alive then car else spectatingModel
	local progress = if watched and phase == "Racing" then (watched:GetAttribute("ParkProgress") :: number?) or 0 else 0
	parkFrame.Visible = progress > 0.01
	if progress > 0.01 then
		parkFill.Size = UDim2.fromScale(progress, 1)
		parkText.Text = string.format("PARKING %d%% — HOLD IT STEADY!", progress * 100)
	end

	-- Spectating
	spectateFrame.Visible = spectatingLabel ~= nil and (phase == "Racing" or phase == "Countdown")
	if spectatingLabel then
		spectateName.Text = spectatingLabel
	end

	-- Trailer pointer
	updateArrow(phase == "Racing" or phase == "Countdown")

	-- Results
	resultsPanel.Visible = phase == "Results"
	if phase == "Results" then
		local winner = (gameState:GetAttribute("WinnerName") :: string?) or ""
		local reason = (gameState:GetAttribute("EndReason") :: string?) or ""
		if winner ~= "" then
			local isMe = gameState:GetAttribute("WinnerUserId") == player.UserId
			resultsTitle.Text = if isMe then "YOU PARKED IT! YOU WIN!" else string.upper(winner) .. " WINS!"
			resultsSub.Text = "Parked on the trailer. Next match in " .. math.max(0, math.ceil(remaining)) .. "s"
		else
			resultsTitle.Text = if reason == "wiped" then "TOTAL CARNAGE" else "TIME'S UP"
			resultsSub.Text = (if reason == "wiped" then "Every car was wrecked." else "Nobody managed to park.")
				.. " Next match in "
				.. math.max(0, math.ceil(remaining))
				.. "s"
		end
	end

	-- Fade out center text
	if os.clock() > centerUntil then
		centerLabel.Text = ""
		if not (phase == "CarSelect" and not inMatch) then
			subCenterLabel.Text = ""
		end
	end
end

function Hud.Init()
	gameState = ReplicatedStorage:WaitForChild("GameState") :: Folder
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	selectRemote = remotes:WaitForChild("SelectCar") :: RemoteEvent

	gui = new("ScreenGui", {
		Name = "DerbyHud",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})

	buildTopBar()
	buildCenter()
	buildLobby()
	buildCarSelect()
	buildDrivePanel()
	buildParkBar()
	buildSpectate()
	buildFeed()
	buildArrow()
	buildResults()
	buildTouch()
end

return Hud
