--!native
--!optimize 2
--!strict

export type Rectangle = {
	Min: Vector2,
	Max: Vector2,

	Width: number,
	Height: number,

	Contains: (self: Rectangle, point: Vector2) -> boolean,
	Intersects: (self: Rectangle, other: Rectangle) -> boolean,
}

export type RectangleModule = {
	new: (min: Vector2, max: Vector2) -> Rectangle,
	
	fromXZRadius: (position: Vector3, radius: number) -> Rectangle,
}

local Rectangle = {}

local function contains(self: Rectangle, point: Vector2): boolean
	return point.X >= self.Min.X
		and point.Y >= self.Min.Y
		and point.X <= self.Max.X
		and point.Y <= self.Max.Y
end

local function intersects(self: Rectangle, other: Rectangle): boolean
	return self.Min.X <= other.Max.X
		and self.Max.X >= other.Min.X
		and self.Min.Y <= other.Max.Y
		and self.Max.Y >= other.Min.Y
end

function Rectangle.new(min: Vector2, max: Vector2): Rectangle
	local actualMin: Vector2 = Vector2.new(math.min(min.X, max.X), math.min(min.Y, max.Y))
	local actualMax: Vector2 = Vector2.new(math.max(min.X, max.X), math.max(min.Y, max.Y))

	return table.freeze({
		Min = actualMin,
		Max = actualMax,

		Width = actualMax.X - actualMin.X,
		Height = actualMax.Y - actualMin.Y,

		Contains = contains,
		Intersects = intersects,
	}) :: any
end

local xzRadiusRect: any = nil

function Rectangle.fromXZRadius(position: Vector3, radius: number): Rectangle
	if not xzRadiusRect then
		xzRadiusRect = {
			Min = { X = 0, Y = 0 },
			Max = { X = 0, Y = 0 },
			Width = 0,
			Height = 0,
			Contains = contains,
			Intersects = intersects,
		}
	end

	local diameter: number = radius * 2

	xzRadiusRect.Min.X = position.X - radius
	xzRadiusRect.Min.Y = position.Z - radius
	xzRadiusRect.Max.X = position.X + radius
	xzRadiusRect.Max.Y = position.Z + radius

	xzRadiusRect.Width = diameter
	xzRadiusRect.Height = diameter

	return xzRadiusRect
end

return table.freeze(Rectangle)
