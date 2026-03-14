--!strict
--!native
--!optimize 2

local UserGameSettings = UserSettings():GetService("UserGameSettings")
local RunService       = game:GetService("RunService")

local BYTES_PER_ENTRY:     number        = 12  
local INITIAL_CAPACITY:    number        = 64

local MULT_MIN:            number        = 0.15
local MULT_MAX:            number        = 1.0

local LOD_UPDATE_INTERVAL: number        = 1 / 10

local TIER_RATIOS: { number }            = { 0.25, 0.5, 0.75, 1.0 }

export type Handle = {
    disconnect: (self: Handle) -> (),
}

export type TierSet = {
    high:   number,
    medium: number,
    low:    number,
    cull:   number,
}

export type LodLevel = number
type ScalarSub = {
    id:       number,
    base:     number,

    callback: (value: number) -> (),
}

type TierSub = {
    id:       number,
    base:     number,

    callback: (tiers: TierSet) -> (),
}

type LodEntry = {
    id:             number,
    slot:           number,

    getPosition:    () -> Vector3,

    baseDists:      { number },  
    scaledDists:    { number },   
    scaledDistsSq:  { number }, 

    level:          LodLevel,

    onChange:       (level: LodLevel) -> (),
}

local _quality:    number = 5
local _multiplier: number = 1.0
local _nextId:     number = 0
local _lodTimer:   number = 0

local _scalarSubs: { [number]: ScalarSub }  = {}
local _tierSubs:   { [number]: TierSub }    = {}
local _entryById:  { [number]: LodEntry }   = {}
local _entrySlots: { [number]: LodEntry? }  = table.create(INITIAL_CAPACITY) :: {LodEntry?}

local _count:      number                   = 0
local _capacity:   number                   = INITIAL_CAPACITY

local _buf:        buffer                   = buffer.create(INITIAL_CAPACITY * BYTES_PER_ENTRY)

local function _ensureCapacity(required: number)
    if required <= _capacity then return end

    local newCap: number = math.max(required, _capacity * 2)
    local newBuf: buffer = buffer.create(newCap * BYTES_PER_ENTRY)

    buffer.copy(newBuf, 0, _buf, 0, _count * BYTES_PER_ENTRY)

    _buf      = newBuf
    _capacity = newCap
end

local function _writePos(slot: number, pos: Vector3)
    local off: number = (slot - 1) * BYTES_PER_ENTRY

    buffer.writef32(_buf, off,     pos.X)
    buffer.writef32(_buf, off + 4, pos.Y)
    buffer.writef32(_buf, off + 8, pos.Z)
end

local function _readDistSq(slot: number, ox: number, oy: number, oz: number): number
    local off: number = (slot - 1) * BYTES_PER_ENTRY

    local dx: number  = buffer.readf32(_buf, off)     - ox
    local dy: number  = buffer.readf32(_buf, off + 4) - oy
    local dz: number  = buffer.readf32(_buf, off + 8) - oz

    return dx*dx + dy*dy + dz*dz
end

local function _computeMultiplier(q: number): number
    assert(q >= 1 and q <= 10, `LOD: quality must be in [1, 10], got {q}`)

    local t: number = (q - 1) / 9

    return MULT_MIN + t * t * (MULT_MAX - MULT_MIN)
end

local function _readQuality(): number
    local val: number = UserGameSettings.SavedQualityLevel.Value

    if val == 0 then
        local ok: boolean, resolved: any = pcall(function(): number
            return settings().Rendering.QualityLevel.Value
        end)

        if ok and type(resolved) == "number" and resolved > 0 then
            return math.clamp(resolved, 1, 10)
        end

        return 10 
    end
    
    return math.clamp(val, 1, 10)
end

local function _buildTiers(base: number, mult: number): TierSet
    return {
        high   = base * TIER_RATIOS[1] * mult,
        medium = base * TIER_RATIOS[2] * mult,
        low    = base * TIER_RATIOS[3] * mult,
        cull   = base * TIER_RATIOS[4] * mult,
    }
end

local function _rescaleEntry(entry: LodEntry)
    for i: number, base: number in entry.baseDists do
        local d: number         = base * _multiplier

        entry.scaledDists[i]   = d
        entry.scaledDistsSq[i] = d * d
    end
end

local function _broadcastQuality()
    for _, sub: ScalarSub in _scalarSubs do
        sub.callback(sub.base * _multiplier)
    end
    
    for _, sub: TierSub in _tierSubs do
        sub.callback(_buildTiers(sub.base, _multiplier))
    end

    for _, entry: LodEntry in _entryById do
        _rescaleEntry(entry)
    end
end

local function _refreshQuality()
    _quality    = _readQuality()
    _multiplier = _computeMultiplier(_quality)

    _broadcastQuality()
end

local function _makeHandle(onDisconnect: () -> ()): Handle
    local fired: boolean = false

    return {
        disconnect = function(_self: Handle)
            if fired then return end

            fired = true

            onDisconnect()
        end,
    }
end

local function _newId(): number
    _nextId += 1

    return _nextId
end

local LOD = {}

function LOD.getQuality(): number
    return _quality
end

function LOD.getMultiplier(): number
    return _multiplier
end

function LOD.scaleByQuality(base: number): number
    assert(type(base) == "number", `LOD.scaleByQuality: base must be number, got {type(base)}`)
    assert(base >= 0,              `LOD.scaleByQuality: base must be >= 0, got {base}`)

    return base * _multiplier
end

function LOD.generateTiers(base: number): TierSet
    assert(type(base) == "number", `LOD.generateTiers: base must be number, got {type(base)}`)
    assert(base > 0,               `LOD.generateTiers: base must be > 0, got {base}`)

    return _buildTiers(base, _multiplier)
end

function LOD.subscribe(base: number, callback: (value: number) -> ()): Handle
    assert(type(base)     == "number",   `LOD.subscribe: base must be number, got {type(base)}`)
    assert(type(callback) == "function", `LOD.subscribe: callback must be function`)
    assert(base >= 0,                    `LOD.subscribe: base must be >= 0, got {base}`)

    local id: number     = _newId()

    _scalarSubs[id]      = { id = id, base = base, callback = callback }

    callback(base * _multiplier)

    return _makeHandle(function()
        _scalarSubs[id] = nil
    end)
end

function LOD.subscribeTiers(base: number, callback: (tiers: TierSet) -> ()): Handle
    assert(type(base)     == "number",   `LOD.subscribeTiers: base must be number, got {type(base)}`)
    assert(type(callback) == "function", `LOD.subscribeTiers: callback must be function`)
    assert(base > 0,                     `LOD.subscribeTiers: base must be > 0, got {base}`)

    local id: number   = _newId()

    _tierSubs[id]      = { id = id, base = base, callback = callback }

    callback(_buildTiers(base, _multiplier))

    return _makeHandle(function()
        _tierSubs[id] = nil
    end)
end

function LOD.register(
    getPosition: () -> Vector3,
    baseDists:   { number },
    onChange:    (level: LodLevel) -> ()
): Handle
    assert(type(getPosition) == "function", `LOD.register: getPosition must be function`)
    assert(type(baseDists)   == "table",    `LOD.register: baseDists must be table`)
    assert(type(onChange)    == "function", `LOD.register: onChange must be function`)
    assert(#baseDists >= 1,                 `LOD.register: baseDists needs at least 1 entry, got {#baseDists}`)

    for i: number, d: number in baseDists do
        assert(type(d) == "number" and d > 0,
            `LOD.register: baseDists[{i}] must be a positive number, got {tostring(d)}`)
            
        if i > 1 then
            assert(d > baseDists[i - 1],
                `LOD.register: baseDists must be ascending; [{i-1}]={baseDists[i-1]} >= [{i}]={d}`)
        end
    end

    _count += 1

    _ensureCapacity(_count)

    local slot: number    = _count
    local id: number      = _newId()
    local n: number       = #baseDists

    local scaled: { number }   = table.create(n) :: {number}
    local scaledSq: { number } = table.create(n) :: {number}

    for i: number, d: number in baseDists do
        local sd: number  = d * _multiplier

        scaled[i]         = sd
        scaledSq[i]       = sd * sd
    end

    local entry: LodEntry = {
        id             = id,
        slot           = slot,
        getPosition    = getPosition,
        baseDists      = table.clone(baseDists),
        scaledDists    = scaled,
        scaledDistsSq  = scaledSq,
        level          = 0,
        onChange       = onChange,
    }

    _entrySlots[slot] = entry
    _entryById[id]    = entry

    _writePos(slot, getPosition())

    return _makeHandle(function()
        local e: LodEntry? = _entryById[id]
        if not e then return end

        local s: number    = e.slot
        local last: number = _count

        if s ~= last then
            local lastEntry: LodEntry = _entrySlots[last] :: LodEntry

            _entrySlots[s]  = lastEntry

            lastEntry.slot  = s

            buffer.copy(
                _buf, (s - 1)    * BYTES_PER_ENTRY,
                _buf, (last - 1) * BYTES_PER_ENTRY,
                BYTES_PER_ENTRY
            )
        end

        _entrySlots[last] = nil
        _entryById[id]    = nil

        _count           -= 1
    end)
end

function LOD.registerWithGeneratedTiers(
    getPosition: () -> Vector3,
    base:        number,
    onChange:    (level: LodLevel) -> ()
): (Handle, TierSet)
    assert(type(getPosition) == "function", `LOD.registerWithGeneratedTiers: getPosition must be function`)
    assert(type(base)        == "number",   `LOD.registerWithGeneratedTiers: base must be number, got {type(base)}`)
    assert(type(onChange)    == "function", `LOD.registerWithGeneratedTiers: onChange must be function`)
    assert(base > 0,                        `LOD.registerWithGeneratedTiers: base must be > 0, got {base}`)

    local t: TierSet = _buildTiers(base, MULT_MAX)

    local handle: Handle = LOD.register(getPosition, {
        t.high,
        t.medium,
        t.low,
        t.cull,
    }, onChange)

    return handle, _buildTiers(base, _multiplier)
end

UserGameSettings:GetPropertyChangedSignal("SavedQualityLevel"):Connect(_refreshQuality)

RunService.Heartbeat:Connect(function(dt: number)
    if _count == 0 then return end

    _lodTimer += dt

    if _lodTimer < LOD_UPDATE_INTERVAL then return end

    _lodTimer -= LOD_UPDATE_INTERVAL

    local camPos: Vector3 = workspace.CurrentCamera.CFrame.Position

    local ox: number      = camPos.X
    local oy: number      = camPos.Y
    local oz: number      = camPos.Z

    for slot: number = 1, _count do
        local entry: LodEntry? = _entrySlots[slot]
        if not entry then continue end

        _writePos(slot, entry.getPosition())

        local distSq: number  = _readDistSq(slot, ox, oy, oz)
        local newLevel: LodLevel = #entry.scaledDistsSq + 1

        for i: number, threshSq: number in entry.scaledDistsSq do
            if distSq <= threshSq then
                newLevel = i

                break
            end
        end

        if newLevel ~= entry.level then
            entry.level = newLevel

            entry.onChange(newLevel)
        end
    end
end)

_refreshQuality()

return LOD