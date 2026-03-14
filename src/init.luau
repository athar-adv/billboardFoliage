--!strict
local GuiService = game:GetService("GuiService")

export type SubBillboard = {
	Transform: CFrame,
	Object: BasePart?,
	SurfaceGui: SurfaceGui?,
}

export type BillboardGroup = {
	Size: UDim2,
	WorldPosition: Vector3,
	DistanceFromScreen: number,
	CurrentWorldCFrame: CFrame,
	KeepConstantSize: boolean,
	SubBillboards: {SubBillboard},

	Update: (BillboardGroup, dt: number) -> (),
	AddBillboard: (BillboardGroup, transform: CFrame) -> SubBillboard,
	Allocate: (BillboardGroup) -> (),
	Reuse: (BillboardGroup) -> (),
}

local function getscreensize(): vector
	local camera = workspace.CurrentCamera
	local rawSize = camera.ViewportSize
	local inset = GuiService:GetGuiInset()
	local sizev2 = rawSize - inset
	return vector.create(sizev2.X, sizev2.Y)
end

local BillboardGroup = {}

function BillboardGroup.Update(self: BillboardGroup, dt: number)
	local camera = workspace.CurrentCamera
	local camcf = camera.CFrame
	local camlook = vector.normalize(camcf.LookVector)
	local camup = camcf.UpVector
	local screenSize = getscreensize()

	local camPos = camcf.Position
	local toTarget = self.WorldPosition - camPos
	local depth = vector.dot(toTarget, camlook)

	local scale = self.DistanceFromScreen / depth
	local billboardPos = camPos + toTarget * scale
	local fovRadians = math.rad(camera.FieldOfView)
	local viewHeight = 2 * self.DistanceFromScreen * math.tan(fovRadians / 2)
	local viewWidth = viewHeight * (screenSize.x / screenSize.y)

	local groupCF = CFrame.lookAlong(billboardPos, -camlook :: any, camup)
	self.CurrentWorldCFrame = groupCF

	local worldSizeX: number
	local worldSizeY: number
	if not self.KeepConstantSize then
		local size = self.Size
		local pixelSize = Vector2.new(
			size.X.Scale * screenSize.x + size.X.Offset,
			size.Y.Scale * screenSize.y + size.Y.Offset
		)
		worldSizeX = (pixelSize.X / screenSize.x) * viewWidth
		worldSizeY = (pixelSize.Y / screenSize.y) * viewHeight
	else
		local s = self.DistanceFromScreen / depth
		worldSizeX = self.Size.X.Offset * s
		worldSizeY = self.Size.Y.Offset * s
	end

	local sharedSize = Vector3.new(worldSizeX, worldSizeY, 0.001)

	for _, sub in self.SubBillboards do
		if not sub.Object then continue end
		local worldPos = self.WorldPosition + sub.Transform.Position
		local toSub = worldPos - camPos
		local subDepth = vector.dot(toSub, camlook)
		local subScale = self.DistanceFromScreen / subDepth
		local subBillboardPos = camPos + toSub * subScale

		sub.Object.CFrame = CFrame.lookAlong(subBillboardPos, -camlook :: any, camup)
		sub.Object.Size = sharedSize
	end
end

function BillboardGroup.AddBillboard(self: BillboardGroup, transform: CFrame): SubBillboard
	local sub: SubBillboard = {
		Transform = transform,
		Object = nil,
		SurfaceGui = nil,
	}
	table.insert(self.SubBillboards, sub)
	return sub
end

type PoolEntry = { object: BasePart, surfaceGui: SurfaceGui }

local objectPool: {PoolEntry} = {}
local reuseQueue: {PoolEntry} = {}
local objectPoolMin = 20
local objectPoolTarget = 80

local function createPoolEntry(gui: GuiObject): PoolEntry
	local object3d = Instance.new("Part")
	object3d.Name = "BillboardGroupPart"
	object3d.Anchored = true
	object3d.Transparency = 1
	object3d.CanCollide = false
	object3d.CanTouch = false
	object3d.CanQuery = false
	object3d.Parent = workspace.CurrentCamera

	local surfaceUi = Instance.new("SurfaceGui")
	surfaceUi.Name = "BillboardGui"
	surfaceUi.AlwaysOnTop = true
	surfaceUi.ClipsDescendants = false
	surfaceUi.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	surfaceUi.Enabled = true
	surfaceUi.ResetOnSpawn = false
	surfaceUi.Face = Enum.NormalId.Front
	surfaceUi.Adornee = object3d
	surfaceUi.Parent = game.Players.LocalPlayer.PlayerGui
	gui.Parent = surfaceUi

	return { object = object3d, surfaceGui = surfaceUi }
end

local function refillPool(gui: GuiObject)
	local needed = objectPoolTarget - #objectPool
	for i = 1, needed do
		objectPool[#objectPool + 1] = createPoolEntry(gui:Clone())
	end
end

local function flushReuseQueue()
	for i = #reuseQueue, 1, -1 do
		objectPool[#objectPool + 1] = reuseQueue[i]
		reuseQueue[i] = nil
	end
end

local function takeFromPool(gui: GuiObject): PoolEntry
	if #objectPool < objectPoolMin then
		flushReuseQueue()
	end
	if #objectPool == 0 then
		refillPool(gui)
	end
	if #objectPool < objectPoolMin then
		refillPool(gui)
	end

	local entry = objectPool[#objectPool]
	objectPool[#objectPool] = nil
	return entry
end

function BillboardGroup.Allocate(self: BillboardGroup, gui: GuiObject)
	for _, sub in self.SubBillboards do
		if sub.Object then continue end
		local entry = takeFromPool(gui)
		sub.Object = entry.object
		sub.SurfaceGui = entry.surfaceGui
		entry.surfaceGui.Enabled = true
	end
end

function BillboardGroup.Reuse(self: BillboardGroup)
	for _, sub in self.SubBillboards do
		if not sub.Object then continue end
		local entry: PoolEntry = {object = sub.Object :: BasePart, surfaceGui = sub.SurfaceGui :: SurfaceGui}
		entry.surfaceGui.Enabled = false
		reuseQueue[#reuseQueue + 1] = entry
		sub.Object = nil
		sub.SurfaceGui = nil
	end
end

local function newBillboardGroup(): BillboardGroup
	return {
		Size = UDim2.fromScale(0, 0),
		WorldPosition = Vector3.zero,
		KeepConstantSize = false,
		DistanceFromScreen = 1,
		CurrentWorldCFrame = CFrame.identity,
		SubBillboards = {},

		Update = BillboardGroup.Update,
		AddBillboard = BillboardGroup.AddBillboard,
		Allocate = BillboardGroup.Allocate,
		Reuse = BillboardGroup.Reuse,
	} :: BillboardGroup
end

return {
	newGroup = newBillboardGroup,
	fillObjectPool = refillPool,
	flushReuseQueue = flushReuseQueue,
}