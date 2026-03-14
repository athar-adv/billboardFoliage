--!strict
--!native
--!optimize 2

local RunService = game:GetService("RunService")

local BYTES_PER_OBJ: number = 16
local INITIAL_CAP:   number = 256
local MAX_CHANGES:   number = 64
local UPDATE_HZ:     number = 20
local UPDATE_DT:     number = 1 / UPDATE_HZ

local BIT_ALIVE:   number = 0x01
local BIT_VISIBLE: number = 0x02

local DEFAULT_FAR: number = 1500

export type FrustumCuller = {
	Add:        (self: FrustumCuller, object: Instance, radius: number?) -> (),
	
	Remove:     (self: FrustumCuller, object: Instance) -> (),
	Destroy:    (self: FrustumCuller) -> (),
	
	SetCamera:  (self: FrustumCuller, camera: Camera) -> (),
	SetMaxChangesPerFrame: (self: FrustumCuller, n: number) -> (),
}

type Internal = {
	_camera:       Camera,
	
	_count:        number,
	_capacity:     number,
	
	_posBuf:       buffer,
	_flagBuf:      buffer,
	
	_objects:      { Instance? },
	
	_radii:        { number },
	
	_indexMap:     { [Instance]: number },
	
	_freeStack:    { number },
	_freeTop:      number,
	
	_onVisible:    ((Instance) -> ())?,
	_onHidden:     ((Instance) -> ())?,
	
	_accumulated:  number,
	_maxChanges:   number,
	
	_conn:         RBXScriptConnection?,
}

local FrustumCuller = {}
FrustumCuller.__index = FrustumCuller

local function _ensureCapacity(self: Internal, required: number)
	if required <= self._capacity then
		return
	end

	local newCap: number = math.max(required, self._capacity * 2)

	local newPos: buffer = buffer.create(newCap * BYTES_PER_OBJ)
	local newFlag: buffer = buffer.create(newCap)

	if self._capacity > 0 then
		buffer.copy(newPos,  0, self._posBuf,  0, self._capacity * BYTES_PER_OBJ)
		buffer.copy(newFlag, 0, self._flagBuf, 0, self._capacity)
	end

	self._posBuf   = newPos
	self._flagBuf  = newFlag
	self._capacity = newCap
end

local function _extractPlanes(camera: Camera): (
    number, number, number, number,
    number, number, number, number,
    number, number, number, number,
    number, number, number, number,
    number, number, number, number,
    number, number, number, number
    )

    local cf: CFrame  = camera.CFrame
    local vp: Vector2 = camera.ViewportSize

    local halfFov: number = camera.FieldOfView * 0.008726645

    local h2: number      = halfFov * halfFov
	
    local tanY: number    = halfFov * (1.0 - h2 / 15.0) / (1.0 - h2 * 0.4)
    local tanX: number    = tanY * (vp.X / math.max(vp.Y, 1))

    local ox: number = cf.Position.X
    local oy: number = cf.Position.Y
    local oz: number = cf.Position.Z

    local lx: number = cf.LookVector.X
    local ly: number = cf.LookVector.Y
    local lz: number = cf.LookVector.Z

    local rx: number = cf.RightVector.X
    local ry: number = cf.RightVector.Y
    local rz: number = cf.RightVector.Z

    local ux: number = cf.UpVector.X
    local uy: number = cf.UpVector.Y
    local uz: number = cf.UpVector.Z

    local lxtX: number = lx * tanX
    local lytX: number = ly * tanX
    local lztX: number = lz * tanX

    local lxtY: number = lx * tanY
    local lytY: number = ly * tanY
    local lztY: number = lz * tanY

    local nx: number
    local ny: number
    local nz: number
    local inv: number

    nx = rx + lxtX
    ny = ry + lytX
    nz = rz + lztX

    inv = 1 / math.sqrt(nx*nx + ny*ny + nz*nz)

    nx *= inv; ny *= inv; nz *= inv

    local ll0: number = nx
    local ll1: number = ny
    local ll2: number = nz
    local ll3: number = -(nx*ox + ny*oy + nz*oz)

    nx = -rx + lxtX
    ny = -ry + lytX
    nz = -rz + lztX

    inv = 1 / math.sqrt(nx*nx + ny*ny + nz*nz)

    nx *= inv; ny *= inv; nz *= inv

    local rl0: number = nx
    local rl1: number = ny
    local rl2: number = nz
    local rl3: number = -(nx*ox + ny*oy + nz*oz)

    nx = ux + lxtY
    ny = uy + lytY
    nz = uz + lztY

    inv = 1 / math.sqrt(nx*nx + ny*ny + nz*nz)

    nx *= inv; ny *= inv; nz *= inv

    local bl0: number = nx
    local bl1: number = ny
    local bl2: number = nz
    local bl3: number = -(nx*ox + ny*oy + nz*oz)

    nx = -ux + lxtY
    ny = -uy + lytY
    nz = -uz + lztY

    inv = 1 / math.sqrt(nx*nx + ny*ny + nz*nz)

    nx *= inv; ny *= inv; nz *= inv

    local tl0: number = nx
    local tl1: number = ny
    local tl2: number = nz
    local tl3: number = -(nx*ox + ny*oy + nz*oz)

    local camDot: number = lx*ox + ly*oy + lz*oz

    local nl0: number = lx
    local nl1: number = ly
    local nl2: number = lz
    local nl3: number = -camDot + camera.NearPlaneZ

    local fl0: number = -lx
    local fl1: number = -ly
    local fl2: number = -lz
    local fl3: number = camDot + DEFAULT_FAR

    return
        ll0, ll1, ll2, ll3,
        rl0, rl1, rl2, rl3,
        bl0, bl1, bl2, bl3,
        tl0, tl1, tl2, tl3,
        nl0, nl1, nl2, nl3,
        fl0, fl1, fl2, fl3
end

local function _update(self: Internal)
	local camera = self._camera

	if not camera then
		return
	end

	local count: number = self._count

	if count == 0 then
		return
	end

	local posBuf: buffer   = self._posBuf
	local flagBuf: buffer  = self._flagBuf

	local objects: {Instance?}  = self._objects

	local l0: number, l1: number, l2: number, l3: number,
	r0: number, r1: number, r2: number, r3: number,
	b0: number, b1: number, b2: number, b3: number,
	t0: number, t1: number, t2: number, t3: number,
	n0: number, n1: number, n2: number, n3: number,
	f0: number, f1: number, f2: number, f3: number = _extractPlanes(camera)

	local changesLeft: number = self._maxChanges

	local onVisible: ((Instance) -> ())?   = self._onVisible
	local onHidden: ((Instance) -> ())?    = self._onHidden

	for i = 0, count - 1 do
		local flags: number = buffer.readu8(flagBuf, i)

		if bit32.band(flags, BIT_ALIVE) == 0 then
			continue
		end

		local base: number = i * BYTES_PER_OBJ

		local x: number    = buffer.readf32(posBuf, base)
		local y: number    = buffer.readf32(posBuf, base + 4)
		local z: number    = buffer.readf32(posBuf, base + 8)

		local rad: number  = buffer.readf32(posBuf, base + 12)

		local visible: boolean =
			(l0 * x + l1 * y + l2 * z + l3) >= -rad and
			(r0 * x + r1 * y + r2 * z + r3) >= -rad and
			(b0 * x + b1 * y + b2 * z + b3) >= -rad and
			(t0 * x + t1 * y + t2 * z + t3) >= -rad and
			(n0 * x + n1 * y + n2 * z + n3) >= -rad and
			(f0 * x + f1 * y + f2 * z + f3) >= -rad

		local wasVisible: boolean = bit32.band(flags, BIT_VISIBLE) ~= 0

		if visible == wasVisible then
			continue
		end

		if changesLeft <= 0 then
			continue
		end

		changesLeft -= 1

		local obj: Instance? = objects[i + 1]

		if not obj then
			continue
		end

		if visible then
			buffer.writeu8(flagBuf, i, bit32.bor(flags, BIT_VISIBLE))

			if onVisible then
				onVisible(obj)
			end
		else
			buffer.writeu8(flagBuf, i, bit32.band(flags, bit32.bnot(BIT_VISIBLE)))

			if onHidden then
				onHidden(obj)
			end
		end
	end

	for i = 0, count - 1 do
		local flags: number = buffer.readu8(flagBuf, i)

		if bit32.band(flags, BIT_ALIVE) == 0 then
			continue
		end

		local obj = objects[i + 1]

		if not obj then
			continue
		end

		local pos: Vector3?

		if obj:IsA("BasePart") then
			pos = (obj :: BasePart).Position
		elseif obj:IsA("Model") then
			local root: BasePart? = (obj :: Model).PrimaryPart

			pos = root and root.Position
		elseif obj:IsA("ParticleEmitter") or obj:IsA("Beam") or obj:IsA("Trail") then
			local parent: Instance? = obj.Parent

			if parent and parent:IsA("BasePart") then
				pos = (parent :: BasePart).Position
			end
		elseif obj:IsA("Attachment") then
			pos = (obj :: Attachment).WorldPosition
		end

		if pos then
			local base: number = i * BYTES_PER_OBJ

			buffer.writef32(posBuf, base,     pos.X)
			buffer.writef32(posBuf, base + 4, pos.Y)
			buffer.writef32(posBuf, base + 8, pos.Z)
		end
	end
end

function FrustumCuller.new(
	camera:    Camera,
	
	onVisible: ((Instance) -> ())?,
	onHidden:  ((Instance) -> ())?
): FrustumCuller

	local self: Internal = setmetatable({}, FrustumCuller) :: any

	self._camera      = camera

	self._count       = 0
	self._capacity    = INITIAL_CAP

	self._posBuf      = buffer.create(INITIAL_CAP * BYTES_PER_OBJ)
	self._flagBuf     = buffer.create(INITIAL_CAP)

	self._objects     = table.create(INITIAL_CAP) :: {Instance?}
	self._radii       = table.create(INITIAL_CAP) :: {number}

	self._indexMap    = {}

	self._freeStack   = table.create(64) :: {number}

	self._freeTop     = 0

	self._onVisible   = onVisible
	self._onHidden    = onHidden

	self._accumulated = 0

	self._maxChanges  = MAX_CHANGES

	self._conn = RunService.Heartbeat:Connect(function(dt: number)
		self._accumulated += dt

		if self._accumulated < UPDATE_DT then
			return
		end

		self._accumulated -= UPDATE_DT

		_update(self)
	end)

	return self :: any
end

function FrustumCuller:Add(object: Instance, radius: number?)
	local self: Internal = self :: any

	if self._indexMap[object] then
		return
	end

	local idx: number

	if self._freeTop > 0 then
		idx = self._freeStack[self._freeTop]

		self._freeStack[self._freeTop] = nil
		self._freeTop -= 1
	else
		self._count += 1
		idx = self._count

		_ensureCapacity(self, self._count)
	end

	buffer.writeu8(self._flagBuf, idx - 1, 0)

	local r: number = radius or 4

	local pos: Vector3 = Vector3.zero

	if object:IsA("BasePart") then
		pos = (object :: BasePart).Position

		if not radius then
			local sz: Vector3 = (object :: BasePart).Size

			r = math.max(sz.X, sz.Y, sz.Z) * 0.5
		end
	elseif object:IsA("Model") then
		local root: BasePart? = (object :: Model).PrimaryPart

		if root then
			pos = root.Position
		end

		if not radius then
			local cf: CFrame, sz: Vector3 = (object :: Model):GetBoundingBox()

			r = math.max(sz.X, sz.Y, sz.Z) * 0.5
			pos = cf.Position
		end
	elseif object:IsA("Attachment") then
		pos = (object :: Attachment).WorldPosition
	end

	local bufIdx: number = idx - 1
	local base: number   = bufIdx * BYTES_PER_OBJ

	buffer.writef32(self._posBuf, base,      pos.X)
	buffer.writef32(self._posBuf, base + 4,  pos.Y)
	buffer.writef32(self._posBuf, base + 8,  pos.Z)
	buffer.writef32(self._posBuf, base + 12, r)
	buffer.writeu8 (self._flagBuf, bufIdx,   BIT_ALIVE)

	self._objects[idx]     = object
    
	self._radii[idx]       = r
	self._indexMap[object] = idx
end

function FrustumCuller:Pause()
	local self: Internal = self :: any

	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
end

function FrustumCuller:Resume()
	local self: Internal = self :: any

	if self._conn then
		return
	end

	self._accumulated = 0

	self._conn = RunService.Heartbeat:Connect(function(dt: number)
		self._accumulated += dt

		if self._accumulated < UPDATE_DT then
			return
		end

		self._accumulated -= UPDATE_DT

		_update(self)
	end)
end

function FrustumCuller:Remove(object: Instance)
	local self: Internal = self :: any

	local idx: number = self._indexMap[object]

	if not idx then
		return
	end

	local bufIdx: number = idx - 1
	local flags: number  = buffer.readu8(self._flagBuf, bufIdx)

	if bit32.band(flags, BIT_VISIBLE) ~= 0 and self._onHidden then
		self._onHidden(object)
	end

	buffer.writeu8(self._flagBuf, bufIdx, 0)

	self._objects[idx]     = nil
	self._indexMap[object] = nil

	self._freeTop += 1
	self._freeStack[self._freeTop] = idx
end

function FrustumCuller:SetCamera(camera: Camera)
	(self :: any)._camera = camera
end

function FrustumCuller:SetMaxChangesPerFrame(n: number)
	(self :: any)._maxChanges = n
end

function FrustumCuller:Destroy()
	local self: Internal = self :: any

	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end

	table.clear(self._objects)
	table.clear(self._indexMap)
	table.clear(self._freeStack)
	table.clear(self._radii)

	self._count = 0
end

return FrustumCuller