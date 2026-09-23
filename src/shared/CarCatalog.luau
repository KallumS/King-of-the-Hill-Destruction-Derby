--!strict
-- The five derby cars. They are purely cosmetic: every car shares the same
-- chassis hitbox and the same Config.Vehicle tuning, so the choice is style only.

export type CarDefinition = {
	Id: string,
	DisplayName: string,
	Tagline: string,
	BodyColor: Color3,
	AccentColor: Color3,
	Style: string,
}

local CarCatalog: { CarDefinition } = {
	{
		Id = "Rustbucket",
		DisplayName = "Rustbucket",
		Tagline = "A four-door sedan held together by rust and spite.",
		BodyColor = Color3.fromRGB(176, 92, 48),
		AccentColor = Color3.fromRGB(92, 58, 40),
		Style = "Sedan",
	},
	{
		Id = "Bulldog",
		DisplayName = "Bulldog",
		Tagline = "Farm pickup with a welded bull bar and nothing to lose.",
		BodyColor = Color3.fromRGB(40, 92, 170),
		AccentColor = Color3.fromRGB(220, 220, 220),
		Style = "Pickup",
	},
	{
		Id = "WagonQueen",
		DisplayName = "Wagon Queen",
		Tagline = "Grandma's station wagon. Built like a bank vault.",
		BodyColor = Color3.fromRGB(64, 140, 78),
		AccentColor = Color3.fromRGB(150, 110, 70),
		Style = "Wagon",
	},
	{
		Id = "Checker",
		DisplayName = "Checker",
		Tagline = "Retired taxi. Meter's still running.",
		BodyColor = Color3.fromRGB(240, 196, 25),
		AccentColor = Color3.fromRGB(20, 20, 20),
		Style = "Taxi",
	},
	{
		Id = "HotRod",
		DisplayName = "Hot Rod",
		Tagline = "Muscle car with a blower sticking out of the hood.",
		BodyColor = Color3.fromRGB(190, 30, 36),
		AccentColor = Color3.fromRGB(30, 30, 30),
		Style = "Muscle",
	},
}

local byId: { [string]: CarDefinition } = {}
for _, def in CarCatalog do
	byId[def.Id] = def
end

local module = {
	List = CarCatalog,
}

function module.Get(id: string?): CarDefinition?
	if id == nil then
		return nil
	end
	return byId[id]
end

function module.Random(): CarDefinition
	return CarCatalog[math.random(1, #CarCatalog)]
end

return module
