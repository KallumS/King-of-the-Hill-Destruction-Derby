--!strict
-- Closed Catmull-Rom spline with an arc-length lookup table.
-- The server uses it to lay the road and to drive the trailer at a constant
-- speed; clients use it for the minimap.

local TrackPath = {}
TrackPath.__index = TrackPath

export type TrackPath = typeof(setmetatable(
	{} :: {
		points: { Vector3 },
		distances: { number },
		totalLength: number,
	},
	TrackPath
))

local SUBDIVISIONS = 40

local function catmullRom(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local t2 = t * t
	local t3 = t2 * t
	return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
end

function TrackPath.new(controlPoints: { Vector3 }): TrackPath
	local count = #controlPoints
	assert(count >= 4, "TrackPath needs at least 4 control points")

	local points: { Vector3 } = {}
	local distances: { number } = {}
	local total = 0

	for i = 1, count do
		local p0 = controlPoints[((i - 2) % count) + 1]
		local p1 = controlPoints[i]
		local p2 = controlPoints[(i % count) + 1]
		local p3 = controlPoints[((i + 1) % count) + 1]
		for step = 0, SUBDIVISIONS - 1 do
			local point = catmullRom(p0, p1, p2, p3, step / SUBDIVISIONS)
			if #points > 0 then
				total += (point - points[#points]).Magnitude
			end
			table.insert(points, point)
			table.insert(distances, total)
		end
	end
	-- close the loop
	total += (points[1] - points[#points]).Magnitude

	return setmetatable({
		points = points,
		distances = distances,
		totalLength = total,
	}, TrackPath)
end

function TrackPath.Wrap(self: TrackPath, distance: number): number
	return distance % self.totalLength
end

-- Binary search for the polyline segment containing `distance`.
function TrackPath._segmentAt(self: TrackPath, distance: number): (number, number)
	distance = distance % self.totalLength
	local distances = self.distances
	local lo, hi = 1, #distances
	while lo < hi do
		local mid = (lo + hi + 1) // 2
		if distances[mid] <= distance then
			lo = mid
		else
			hi = mid - 1
		end
	end
	local nextIndex = (lo % #distances) + 1
	local segStart = distances[lo]
	local segEnd = if nextIndex == 1 then self.totalLength else distances[nextIndex]
	local alpha = if segEnd > segStart then (distance - segStart) / (segEnd - segStart) else 0
	return lo, alpha
end

function TrackPath.PositionAt(self: TrackPath, distance: number): Vector3
	local index, alpha = self:_segmentAt(distance)
	local a = self.points[index]
	local b = self.points[(index % #self.points) + 1]
	return a:Lerp(b, alpha)
end

function TrackPath.TangentAt(self: TrackPath, distance: number): Vector3
	local ahead = self:PositionAt(distance + 2)
	local behind = self:PositionAt(distance - 2)
	local dir = ahead - behind
	if dir.Magnitude < 1e-4 then
		return Vector3.zAxis
	end
	return dir.Unit
end

-- CFrame on the centreline facing along the direction of travel.
function TrackPath.CFrameAt(self: TrackPath, distance: number): CFrame
	local position = self:PositionAt(distance)
	return CFrame.lookAt(position, position + self:TangentAt(distance))
end

-- Signed curvature-ish turn rate (radians per stud) used for the trailer's banking.
function TrackPath.TurnRateAt(self: TrackPath, distance: number): number
	local a = self:TangentAt(distance - 6)
	local b = self:TangentAt(distance + 6)
	local cross = a:Cross(b).Y
	local angle = math.atan2(cross, a:Dot(b))
	return angle / 12
end

-- Track distance of the centreline point closest to `position` (XZ only).
function TrackPath.ClosestDistance(self: TrackPath, position: Vector3): (number, number)
	local flat = Vector3.new(position.X, 0, position.Z)
	local bestIndex, bestDist = 1, math.huge
	for i, point in self.points do
		local d = (Vector3.new(point.X, 0, point.Z) - flat).Magnitude
		if d < bestDist then
			bestDist = d
			bestIndex = i
		end
	end
	return self.distances[bestIndex], bestDist
end

return TrackPath
