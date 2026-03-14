--!native
--!optimize 2
--!strict

export type Node<T> = {
	Position: Vector2,
	Identifier: T,
	Data: any?,
}

export type QuadTree<T> = {
	Bounds: Rectangle,
	Node: Node<T>?,
	TopLeft: QuadTree<T>?,
	TopRight: QuadTree<T>?,
	BottomLeft: QuadTree<T>?,
	BottomRight: QuadTree<T>?,

	_depth: number,
	_maxDepth: number,

	Contains: (self: QuadTree<T>, point: Vector2) -> boolean,
	Insert: (self: QuadTree<T>, node: Node<T>) -> (boolean, string?),
	BulkInsert: (self: QuadTree<T>, nodes: {Node<T>}) -> (boolean, string?),
	Locate: (self: QuadTree<T>, point: Vector2) -> Node<T>?,
	QueryRange: (self: QuadTree<T>, Rectangle: Rectangle, predicate: ((Node<T>) -> boolean)?) -> {Node<T>},
	Remove: (self: QuadTree<T>, point: Vector2) -> boolean,
	Clear: (self: QuadTree<T>) -> (),
	GetDepth: (self: QuadTree<T>) -> number,
	Visualize: (self: QuadTree<T>) -> {Rectangle},
}

local Rectangle = require(script.Rect)

export type Rectangle = Rectangle.Rectangle
export type RectangleModule = Rectangle.RectangleModule

local UNIT_SIZE: number = 5
local MAX_DEPTH: number = 10
local MAX_NODES_PER_LEAF: number = 5

local QUADRANT_NAMES: {string} = table.freeze({ "TopLeft", "TopRight", "BottomLeft", "BottomRight" })

local insert: any
local splitLeafNode: any
local createSubtree: any

local function qtContains(self: any, point: Vector2): boolean
	local bounds: any = self.Bounds

	return point.X >= bounds.Min.X
		and point.Y >= bounds.Min.Y
		and point.X <= bounds.Max.X
		and point.Y <= bounds.Max.Y
end

local function qtLocate(self: any, point: Vector2): any
	if not qtContains(self, point) then
		return nil
	end

	if self.Node then
		return self.Node
	end

	local center: any = (self.Bounds.Min + self.Bounds.Max) * 0.5
	local quadrant: any = nil

	if point.X <= center.X then
		quadrant = point.Y <= center.Y and self.TopLeft or self.BottomLeft
	else
		quadrant = point.Y <= center.Y and self.TopRight or self.BottomRight
	end

	if quadrant then
		return qtLocate(quadrant, point)
	end

	return nil
end

local function qtQueryRange(self: any, rect: Rectangle, predicate: ((any) -> boolean)?): { any }
	local results: {any} = {}

	if not self.Bounds:Intersects(rect) then
		return results
	end

	if self.Node and self.Bounds:Contains(self.Node.Position) then
		if not predicate or predicate(self.Node) then
			table.insert(results, self.Node)
		end
	end

	for _, quadrantName: string in QUADRANT_NAMES do
		local subtree: any = self[quadrantName]

		if subtree then
			local subtreeResults: {any} = qtQueryRange(subtree, rect, predicate)

			for _, node: any in ipairs(subtreeResults) do
				table.insert(results, node)
			end
		end
	end

	return results
end

local function qtRemove(self: any, point: Vector2): boolean
	if not qtContains(self, point) then
		return false
	end

	if self.Node and self.Node.Position == point then
		self.Node = nil
		return true
	end

	local center: any = (self.Bounds.Min + self.Bounds.Max) * 0.5
	local quadrant: any = nil

	if point.X <= center.X then
		quadrant = point.Y <= center.Y and self.TopLeft or self.BottomLeft
	else
		quadrant = point.Y <= center.Y and self.TopRight or self.BottomRight
	end

	return quadrant and qtRemove(quadrant, point) or false
end

local function qtClear(self: any): ...any
	self.Node = nil

	for _, quadrantName: string in QUADRANT_NAMES do
		local child: any = self[quadrantName]

		if child then
			qtClear(child)
			self[quadrantName] = nil
		end
	end
end

local function qtGetDepth(self: any): number
	local maxDepth: number = 0

	for _, quadrantName: string in QUADRANT_NAMES do
		local subtree: any = self[quadrantName]

		if subtree then
			maxDepth = math.max(maxDepth, qtGetDepth(subtree))
		end
	end

	return maxDepth + 1
end

local function qtVisualize(self: any): { any }
	local rectangles: {any} = { self.Bounds }

	for _, quadrantName: string in QUADRANT_NAMES do
		local child: any = self[quadrantName]

		if child then
			local childRectangles: {any} = qtVisualize(child)

			for _, r: any in ipairs(childRectangles) do
				table.insert(rectangles, r)
			end
		end
	end

	return rectangles
end

local function qtBulkInsert(self: any, nodes: { any }): (boolean, string?)
    table.sort(nodes, function(a: any, b: any): boolean
        local ax: number = (a.Position.X * 100) // 1
        local ay: number = (a.Position.Y * 100) // 1
        local bx: number = (b.Position.X * 100) // 1
        local by: number = (b.Position.Y * 100) // 1

		ax = ax % 0x10000
        ay = ay % 0x10000
        bx = bx % 0x10000
        by = by % 0x10000

        local x: number = bit32.band(ax, 0xFFFF)
        local y: number = bit32.band(ay, 0xFFFF)

        x = bit32.band(bit32.bor(x, bit32.lshift(x, 8)), 0x00FF00FF)
        x = bit32.band(bit32.bor(x, bit32.lshift(x, 4)), 0x0F0F0F0F)
        x = bit32.band(bit32.bor(x, bit32.lshift(x, 2)), 0x33333333)
        x = bit32.band(bit32.bor(x, bit32.lshift(x, 1)), 0x55555555)

        y = bit32.band(bit32.bor(y, bit32.lshift(y, 8)), 0x00FF00FF)
        y = bit32.band(bit32.bor(y, bit32.lshift(y, 4)), 0x0F0F0F0F)
        y = bit32.band(bit32.bor(y, bit32.lshift(y, 2)), 0x33333333)
        y = bit32.band(bit32.bor(y, bit32.lshift(y, 1)), 0x55555555)

        local mortonA: number = bit32.bor(x, bit32.lshift(y, 1))

        x = bit32.band(bx, 0xFFFF)
        y = bit32.band(by, 0xFFFF)

        x = bit32.band(bit32.bor(x, bit32.lshift(x, 8)), 0x00FF00FF)
        x = bit32.band(bit32.bor(x, bit32.lshift(x, 4)), 0x0F0F0F0F)
        x = bit32.band(bit32.bor(x, bit32.lshift(x, 2)), 0x33333333)
        x = bit32.band(bit32.bor(x, bit32.lshift(x, 1)), 0x55555555)

        y = bit32.band(bit32.bor(y, bit32.lshift(y, 8)), 0x00FF00FF)
        y = bit32.band(bit32.bor(y, bit32.lshift(y, 4)), 0x0F0F0F0F)
        y = bit32.band(bit32.bor(y, bit32.lshift(y, 2)), 0x33333333)
        y = bit32.band(bit32.bor(y, bit32.lshift(y, 1)), 0x55555555)

        local mortonB: number = bit32.bor(x, bit32.lshift(y, 1))

        return mortonA < mortonB
    end)

    for _, node: any in ipairs(nodes) do
        local success: any, err: any = insert(self, node)
		
        if not success then
            return false, err
        end
    end

    return true
end

createSubtree = function(parentSelf: any, min: Vector2, max: Vector2): any
	return {
		Bounds = Rectangle.new(min, max),
		Node = nil,
		TopLeft = nil,
		TopRight = nil,
		BottomLeft = nil,
		BottomRight = nil,
		_depth = parentSelf._depth + 1,
		_maxDepth = parentSelf._maxDepth,
		_nodes = nil,
		Contains = qtContains,
		Insert = insert,
		BulkInsert = qtBulkInsert,
		Locate = qtLocate,
		QueryRange = qtQueryRange,
		Remove = qtRemove,
		Clear = qtClear,
		GetDepth = qtGetDepth,
		Visualize = qtVisualize,
	}
end

splitLeafNode = function(self: any)
	if self.TopLeft ~= nil then return end

	local center: any = (self.Bounds.Min + self.Bounds.Max) * 0.5

	self.TopLeft = createSubtree(self, self.Bounds.Min, center)

	self.TopRight = createSubtree(self,
		Vector2.new(center.X, self.Bounds.Min.Y),
		Vector2.new(self.Bounds.Max.X, center.Y)
	)

	self.BottomLeft = createSubtree(self,
		Vector2.new(self.Bounds.Min.X, center.Y),
		Vector2.new(center.X, self.Bounds.Max.Y)
	)

	self.BottomRight = createSubtree(self, center, self.Bounds.Max)

	if self.Node then
		local node: any = self.Node

		self.Node = nil

		insert(self, node)
	end

	if self._nodes then
		for _, node: any in ipairs(self._nodes) do
			insert(self, node)
		end

		self._nodes = nil
	end
end

insert = function(self: any, node: any): (boolean, string?)
	if not qtContains(self, node.Position) then
		return false, "Node position outside quadtree bounds"
	end

	if self.Node and not self.TopLeft then
		if not self._nodes then
			self._nodes = { self.Node }
			self.Node = nil
		end

		table.insert(self._nodes, node)

		if #self._nodes > MAX_NODES_PER_LEAF then
			splitLeafNode(self)
		end

		return true
	end

	if (self.Bounds.Width <= UNIT_SIZE and self.Bounds.Height <= UNIT_SIZE)
		or (self._depth >= self._maxDepth) then

		if self.Node then
			return false, "Position already occupied in quadtree"
		end

		self.Node = node

		return true
	end

	local center: any = (self.Bounds.Min + self.Bounds.Max) * 0.5
	local quadrant: "TopLeft" | "TopRight" | "BottomLeft" | "BottomRight"

	if node.Position.X <= center.X then
		if node.Position.Y <= center.Y then
			quadrant = "TopLeft"
		else
			quadrant = "BottomLeft"
		end
	else
		if node.Position.Y <= center.Y then
			quadrant = "TopRight"
		else
			quadrant = "BottomRight"
		end
	end

	if not self[quadrant] then
		local min: any, max: any

		if quadrant == "TopLeft" then
			min = self.Bounds.Min
			max = center
		elseif quadrant == "TopRight" then
			min = Vector2.new(center.X, self.Bounds.Min.Y)
			max = Vector2.new(self.Bounds.Max.X, center.Y)
		elseif quadrant == "BottomLeft" then
			min = Vector2.new(self.Bounds.Min.X, center.Y)
			max = Vector2.new(center.X, self.Bounds.Max.Y)
		else
			min = center
			max = self.Bounds.Max
		end

		self[quadrant] = createSubtree(self, min, max)
	end

	return insert(self[quadrant], node)
end

local QuadTree = {}
QuadTree.ExportedRectangle = Rectangle

function QuadTree.new<T>(point1: Vector2, point2: Vector2, maxDepth: number?): QuadTree<T>
	local depth: number = maxDepth or MAX_DEPTH

	return {
		Bounds = Rectangle.new(point1, point2),
		Node = nil,
		TopLeft = nil,
		TopRight = nil,
		BottomLeft = nil,
		BottomRight = nil,
		_depth = 0,
		_maxDepth = depth,
		_nodes = nil,
		Contains = qtContains,
		Insert = insert,
		BulkInsert = qtBulkInsert,
		Locate = qtLocate,
		QueryRange = qtQueryRange,
		Remove = qtRemove,
		Clear = qtClear,
		GetDepth = qtGetDepth,
		Visualize = qtVisualize,
	} :: any
end

function QuadTree.NewNode<T>(position: Vector2, identifier: T, data: any?): Node<T>
	return table.freeze({
		Position = position,
		Identifier = identifier,
		Data = data,
	})
end

return table.freeze(QuadTree)
