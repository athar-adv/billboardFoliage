--!strict
--!native
--!optimize 2

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local b2 = require(script.b226)

local Signal = require(ReplicatedStorage.Modules.Utils.Signal)
local Thread = require(ReplicatedStorage.Modules.Utils.Thread)

local Butler = require(ReplicatedStorage.Modules.Utils.Butler)
local BufferFSM = require(script.BufferFSM)

local QuadTree = require(script.QuadTree)

local newSignal: () -> Signal.Signal = Signal.new
local QTRectangle: QuadTree.RectangleModule = QuadTree.ExportedRectangle

local MSG_OBJECT_ADD: number    = 0x01
local MSG_OBJECT_REMOVE: number = 0x02
local MSG_PROPERTY_DELTA: number = 0x03
local MSG_POSITION_DELTA: number = 0x04
local MSG_STATE_DELTA: number   = 0x05
local MSG_SERVER_EVENT: number  = 0x06
local MSG_CLIENT_EVENT: number  = 0x07
local MSG_TAG_ADD: number       = 0x08
local MSG_TAG_REMOVE: number    = 0x09

export type ObjectId = number

export type ObjectDescriptor = {
	class: string,
	tags: { string }?,
	name: string,

	position: Vector3?,

	replicateDistance: number?,
	viewDistance: number?,

	whitelist: { Player }?,
	properties: { [string]: any }?,

	states: { string }?,
	transitions: { [string]: { string } }?,
}

export type ObjectHandle = {
	oid: ObjectId,
	class: string,

	SetPosition:      (self: ObjectHandle, position: Vector3) -> (),
	SetProperty:      (self: ObjectHandle, key: string, value: any) -> (),
	GetProperty:      (self: ObjectHandle, key: string) -> any,
	AddTag:           (self: ObjectHandle, tag: string) -> (),
	RemoveTag:        (self: ObjectHandle, tag: string) -> (),
	HasTag:           (self: ObjectHandle, tag: string) -> boolean,
	GetTags:          (self: ObjectHandle) -> { string },

	SetState:         (self: ObjectHandle, stateName: string) -> boolean,
	GetState:         (self: ObjectHandle) -> string?,
	GetStateDuration: (self: ObjectHandle) -> number?,

	FireClient:       (self: ObjectHandle, player: Player, ...any) -> (),
	FireClients:      (self: ObjectHandle, ...any) -> (),
	OnClientEvent:    (self: ObjectHandle, callback: (player: Player, ...any) -> ()) -> any,
	OnDestroy:        (self: ObjectHandle, callback: () -> ()) -> any,

	GetButler:        (self: ObjectHandle) -> Butler.Butler,
	Destroy:          (self: ObjectHandle) -> (),
}

export type ClientObject = {
	oid: ObjectId,
	class: string,

	GetProperty:       (self: ClientObject, key: string) -> any,
	GetProperties:     (self: ClientObject) -> { [string]: any },
	GetPosition:       (self: ClientObject) -> Vector3?,
	GetState:          (self: ClientObject) -> string?,
	GetStateDuration:  (self: ClientObject) -> number?,
	GetAsset:          (self: ClientObject) -> Instance,
	HasTag:            (self: ClientObject, tag: string) -> boolean,
	GetTags:           (self: ClientObject) -> { string },

	OnPropertyChanged: (self: ClientObject, key: string, callback: (oldValue: any, newValue: any) -> ()) -> any,
	OnServerEvent:     (self: ClientObject, callback: (...any) -> ()) -> any,
	FireServer:        (self: ClientObject, ...any) -> (),
}

type ServerObjectRecord = {
	oid: ObjectId,

	onClientEventSignal: Signal.Signal,
	onDestroySignal: Signal.Signal,

	butler: Butler.Butler,

	states: { string }?,
	transitions: { [string]: { string } }?,

	stateMachine: BufferFSM.FSM?,
}

type ClientObjectRecord = {
	oid: ObjectId,

	class: string,
	tags: { [string]: true },
	name: string,

	position: Vector3?,

	replicateDistance: number?,
	viewDistance: number?,

	properties: { [string]: any },

	onPropertyChangedSignal: Signal.Signal,
	onServerEventSignal: Signal.Signal,

	states: { string }?,
	transitions: { [string]: { string } }?,

	stateMachine: BufferFSM.FSM?,
}

type ClientOptions = {
	remoteEvent: RemoteEvent?,
	remoteFunction: RemoteFunction?,

	viewUpdateRate: number?,
	maxViewDistance: number?,

	remote_event: RemoteEvent?,
	remote_function: RemoteFunction?,

	view_update_rate: number?,
	max_view_distance: number?,
}

type ServerOptions = {
	remoteEvent: RemoteEvent?,
	remoteFunction: RemoteFunction?,

	worldSize: number?,
	updateRate: number?,

	remote_event: RemoteEvent?,
	remote_function: RemoteFunction?,

	world_size: number?,
	update_rate: number?,
}

export type ServerNamespace = {
	init:                  (options: ServerOptions?) -> (),
	spawn:                 (descriptor: ObjectDescriptor) -> ObjectHandle,
	get:                   (oid: ObjectId) -> ObjectHandle?,

	updatePlayer:          (player: Player, position: Vector3?) -> (),

	queryClass:            (className: string) -> { ObjectHandle },
	queryTag:              (tag: string) -> { ObjectHandle },
	queryTags:             (...string) -> { ObjectHandle },
	queryNear:             (position: Vector3, radius: number) -> { ObjectHandle },

	ecs:                   () -> any,

	onClientEventForClass: (className: string, callback: (player: Player, object: ObjectHandle, ...any) -> ()) -> any,
	onClientEventForTag:   (tag: string,       callback: (player: Player, object: ObjectHandle, ...any) -> ()) -> any,

	_messageTypes:         { [string]: number },
}

export type ClientNamespace = {
	init:                  (options: ClientOptions?) -> (),
	get:                   (oid: ObjectId) -> ClientObject?,

	onEnter:               (className: string, callback: (viewButler: Butler.Butler, object: ClientObject) -> ()) -> any,
	onEnterWithTag:        (className: string, tag: string, callback: (viewButler: Butler.Butler, object: ClientObject) -> ()) -> any,

	onLeave:               (className: string, callback: (object: ClientObject) -> ()) -> any,
	onLeaveWithTag:        (className: string, tag: string, callback: (object: ClientObject) -> ()) -> any,

	onServerEventForClass: (className: string, callback: (object: ClientObject, ...any) -> ()) -> any,
	onServerEventForTag:   (tag: string,       callback: (object: ClientObject, ...any) -> ()) -> any,
}

export type SharedNamespace = {
	registerAsset: (className: string, assetInstance: Instance, nameOverride: string?) -> (),
	getAsset:      (className: string, name: string) -> Instance?,
}

export type ObjectWorldModule = {
	server:        ServerNamespace,
	client:        ClientNamespace,
	shared:        SharedNamespace,

	registerAsset: (className: string, assetInstance: Instance, nameOverride: string?) -> (),
	getAsset:      (className: string, name: string) -> Instance?,
}

--@Sovereignty's and Prof's

local function deepClone(value: any): any
	if type(value) ~= "table" then
		return value
	end

	local copy: { [any]: any } = {}

	for k: any, v: any in value do
		copy[k] = deepClone(v)
	end

	return copy
end

local function tagsSetToArray(tagsSet: any): { string }
	local tags: { string } = {}

	if type(tagsSet) ~= "table" then
		return tags
	end

	for tagName: any, present: any in tagsSet do
		if type(tagName) == "string" and present == true then
			table.insert(tags, tagName)
		end
	end

	table.sort(tags)

	return tags
end

local function getPlayerPosition(player: Player): Vector3?
	local character: Model? = player.Character

	if not character then
		return nil
	end

	local rootPart: BasePart? = character:FindFirstChild("HumanoidRootPart") :: BasePart?

	if rootPart and rootPart:IsA("BasePart") then
		return rootPart.Position
	end

	if character.PrimaryPart then
		return character.PrimaryPart.Position
	end

	return nil
end

local function toXZ(position: Vector3): Vector2
	return Vector2.new(position.X, position.Z)
end

local registeredAssets: { [string]: Instance } = {}

local function getAssetKey(className: string, name: string): string
	return `{className}\0{name}`
end

local function registerAsset(className: string, assetInstance: Instance, nameOverride: string?)
	local name: string = nameOverride or assetInstance.Name

	registeredAssets[getAssetKey(className, name)] = assetInstance
end

local function getAsset(className: string, name: string): Instance?
	local key: string = getAssetKey(className, name)
	local direct: Instance? = registeredAssets[key]

	if direct then
		return direct
	end

	local assetsFolder: Folder? = ReplicatedStorage:FindFirstChild("Assets") :: Folder?

	if not assetsFolder then
		return nil
	end

	local classFolder: Instance? = assetsFolder:FindFirstChild(className)

	if classFolder then
		local from: Instance? = classFolder:FindFirstChild(name)

		if from then
			return from
		end
	end

	local pluralFolder: Instance? = assetsFolder:FindFirstChild(className .. "s")

	if pluralFolder then
		local from: Instance? = pluralFolder:FindFirstChild(name)

		if from then
			return from
		end
	end

	return assetsFolder:FindFirstChild(name)
end

local serverInitialized: boolean = false
local serverRemoteEvent: RemoteEvent? = nil
local serverRemoteFunction: RemoteFunction? = nil
local serverWorldSize: number = 16384
local serverUpdateRate: number = 0.25

local serverEcs: any = nil
local PositionComponent: number = 0
local ClassComponent: number = 0
local TagsComponent: number = 0
local NameComponent: number = 0
local ReplicateDistanceComponent: number = 0
local ViewDistanceComponent: number = 0
local PropertiesComponent: number = 0
local StateComponent: number = 0
local WhitelistComponent: number = 0
local ServerRecordComponent: number = 0
local ServerHandleComponent: number = 0

local serverReplicatedByPlayer: { [Player]: { [ObjectId]: true } } = {}
local serverPlayersByObject: { [ObjectId]: { [Player]: true } } = {}

local serverQuadTree: any = nil
local serverQuadTreePositions: { [ObjectId]: Vector2 } = {}
local serverAlwaysReplicatedObjects: { [ObjectId]: true } = {}
local serverWhitelistObjects: { [ObjectId]: true } = {}
local serverMaxReplicateDistance: number = 0

local serverSpawningObjects: { [ObjectId]: true } = {}
local serverDestroyingObjects: { [ObjectId]: true } = {}

local serverClassTagEntities: { [string]: number } = {}
local serverTagTagEntities: { [string]: number } = {}

local serverClientEventByClass: { [string]: Signal.Signal } = {}
local serverClientEventByTag: { [string]: Signal.Signal } = {}

local function getClassServerSignal(className: string): Signal.Signal
	local s: Signal.Signal = serverClientEventByClass[className]

	if not s then
		s = newSignal()

		serverClientEventByClass[className] = s
	end

	return s
end

local function getTagServerSignal(tag: string): Signal.Signal
	local s: Signal.Signal = serverClientEventByTag[tag]

	if not s then
		s = newSignal()

		serverClientEventByTag[tag] = s
	end

	return s
end

local function getOrCreateClassTagEntity(className: string): number
	local e: number = serverClassTagEntities[className]

	if not e then
		e = serverEcs.entity()

		serverClassTagEntities[className] = e
	end

	return e
end

local function getOrCreateTagTagEntity(tag: string): number
	local e: number = serverTagTagEntities[tag]

	if not e then
		e = serverEcs.entity()

		serverTagTagEntities[tag] = e
	end

	return e
end

local function gridRemoveObject(oid: ObjectId)
	local oldPosition: Vector2? = serverQuadTreePositions[oid]

	if not oldPosition then
		return
	end

	if serverQuadTree then
		serverQuadTree:Remove(oldPosition)
	end

	serverQuadTreePositions[oid] = nil
end

local function gridInsertObject(oid: ObjectId, position: Vector3)
	local newPos2D: Vector2 = toXZ(position)
	local oldPos2D: Vector2? = serverQuadTreePositions[oid]

	if oldPos2D and oldPos2D == newPos2D then
		return
	end

	if oldPos2D then
		gridRemoveObject(oid)
	end

	if serverQuadTree then
		serverQuadTree:Insert(QuadTree.NewNode(newPos2D, oid))
		serverQuadTreePositions[oid] = newPos2D
	end
end

local function recomputeMaxReplicateDistance()
	local maxDistance: number = 0

	if serverEcs then
		for _, distance: any in serverEcs.query(ReplicateDistanceComponent):entities() do
			if type(distance) == "number" and distance > maxDistance then
				maxDistance = distance :: number
			end
		end
	end

	serverMaxReplicateDistance = maxDistance
end

local function refreshObjectReplicationBuckets(oid: ObjectId)
	serverAlwaysReplicatedObjects[oid] = nil
	serverWhitelistObjects[oid] = nil

	if not serverEcs or not serverEcs.contains(oid) then
		return
	end

	local position: any = serverEcs.get(oid, PositionComponent)
	local replicateDistance: any = serverEcs.get(oid, ReplicateDistanceComponent)

	if typeof(position) == "Vector3" and type(replicateDistance) == "number" then
		if replicateDistance > serverMaxReplicateDistance then
			serverMaxReplicateDistance = replicateDistance
		end

		return
	end

	local whitelist: any = serverEcs.get(oid, WhitelistComponent)

	if type(whitelist) == "table" then
		serverWhitelistObjects[oid] = true
	else
		serverAlwaysReplicatedObjects[oid] = true
	end
end

local function sendToPlayer(player: Player, messageType: number, ...: any)
	if serverRemoteEvent and player.Parent == Players then
		serverRemoteEvent:FireClient(player, messageType, ...)
	end
end

local function isPlayerReplicatingObject(player: Player, oid: ObjectId): boolean
	local replicated: { [ObjectId]: true }? = serverReplicatedByPlayer[player]

	return replicated ~= nil and replicated[oid] == true
end

local function tryGetServerRecord(oid: ObjectId): ServerObjectRecord?
	if not serverEcs or not serverEcs.contains(oid) then
		return nil
	end

	local record: any = serverEcs.get(oid, ServerRecordComponent)

	if type(record) ~= "table" then
		return nil
	end

	return record :: ServerObjectRecord
end

local function createObjectSnapshot(oid: ObjectId): { [string]: any }?
	local record: ServerObjectRecord? = tryGetServerRecord(oid)

	if record == nil then
		return nil
	end

	local tags: { string } = tagsSetToArray(serverEcs.get(oid, TagsComponent))

	local snapshot: { [string]: any } = {
		oid = oid,
		class = serverEcs.get(oid, ClassComponent),
		tags = if #tags > 0 then tags else nil,
		name = serverEcs.get(oid, NameComponent),
		position = serverEcs.get(oid, PositionComponent),
		replicateDistance = serverEcs.get(oid, ReplicateDistanceComponent),
		viewDistance = serverEcs.get(oid, ViewDistanceComponent),
		properties = deepClone(serverEcs.get(oid, PropertiesComponent) or {}),
		states = record.states and deepClone(record.states) or nil,
		transitions = record.transitions and deepClone(record.transitions) or nil,
	}

	if record.stateMachine then
		snapshot.fsmData = record.stateMachine:Serialize()
	end

	return snapshot
end

local function addObjectToPlayerReplication(player: Player, oid: ObjectId)
	local record: ServerObjectRecord? = tryGetServerRecord(oid)

	if not record then
		return
	end

	local playerSet: { [ObjectId]: true } = serverReplicatedByPlayer[player]

	if playerSet == nil then
		playerSet = {}

		serverReplicatedByPlayer[player] = playerSet
	end

	if playerSet[oid] then
		return
	end

	playerSet[oid] = true

	local objectSet: { [Player]: true } = serverPlayersByObject[oid]

	if objectSet == nil then
		objectSet = {}

		serverPlayersByObject[oid] = objectSet
	end

	objectSet[player] = true

	local snapshot: { [string]: any }? = createObjectSnapshot(oid)

	if snapshot then
		sendToPlayer(player, MSG_OBJECT_ADD, snapshot)
	end
end

local function removeObjectFromPlayerReplication(player: Player, oid: ObjectId)
	local playerSet: { [ObjectId]: true }? = serverReplicatedByPlayer[player]

	if playerSet and playerSet[oid] then
		playerSet[oid] = nil
	end

	local objectSet: { [Player]: true }? = serverPlayersByObject[oid]

	if objectSet and objectSet[player] then
		objectSet[player] = nil

		if next(objectSet) == nil then
			serverPlayersByObject[oid] = nil
		end
	end

	sendToPlayer(player, MSG_OBJECT_REMOVE, oid)
end

local function removeObjectFromAllPlayers(oid: ObjectId)
	local objectSet: { [Player]: true }? = serverPlayersByObject[oid]

	if objectSet == nil then
		return
	end

	for player: Player in objectSet do
		removeObjectFromPlayerReplication(player, oid)
	end
end

local function broadcastToReplicatedPlayers(oid: ObjectId, messageType: number, ...: any)
	local objectSet: { [Player]: true }? = serverPlayersByObject[oid]

	if objectSet == nil then
		return
	end

	for player: Player in objectSet do
		sendToPlayer(player, messageType, ...)
	end
end

local function shouldReplicateObjectToPlayer(player: Player, oid: ObjectId, playerPosition: Vector3?): boolean
	if tryGetServerRecord(oid) == nil then
		return false
	end

	local position: any = serverEcs.get(oid, PositionComponent)
	local replicateDistance: any = serverEcs.get(oid, ReplicateDistanceComponent)

	if typeof(position) == "Vector3" and type(replicateDistance) == "number" then
		local refPos: Vector3? = playerPosition or getPlayerPosition(player)

		if refPos == nil then
			return false
		end

		return (refPos - (position :: Vector3)).Magnitude <= (replicateDistance :: number)
	end

	local whitelist: any = serverEcs.get(oid, WhitelistComponent)

	if type(whitelist) == "table" then
		return table.find(whitelist :: { Player }, player) ~= nil
	end

	return true
end

local function collectCandidateObjects(position: Vector3?): { [ObjectId]: true }
	local candidates: { [ObjectId]: true } = {}

	for oid: ObjectId in serverAlwaysReplicatedObjects do
		candidates[oid] = true
	end

	for oid: ObjectId in serverWhitelistObjects do
		candidates[oid] = true
	end

	if position and serverMaxReplicateDistance > 0 and serverQuadTree then
		local nodes: { QuadTree.Node<ObjectId> } = serverQuadTree:QueryRange(QTRectangle.fromXZRadius(position, serverMaxReplicateDistance))

		for _, node: QuadTree.Node<ObjectId> in nodes do
			candidates[node.Identifier] = true
		end
	end

	return candidates
end

local function updateAllPlayersForObject(oid: ObjectId)
	for _, player: Player in Players:GetPlayers() do
		local playerPosition: Vector3? = getPlayerPosition(player)
		local shouldReplicate: boolean = shouldReplicateObjectToPlayer(player, oid, playerPosition)
		local currentlyReplicated: boolean = isPlayerReplicatingObject(player, oid)

		if shouldReplicate and not currentlyReplicated then
			addObjectToPlayerReplication(player, oid)
		elseif not shouldReplicate and currentlyReplicated then
			removeObjectFromPlayerReplication(player, oid)
		end
	end
end

local function getServerRecord(oid: ObjectId): ServerObjectRecord
	local record: ServerObjectRecord? = tryGetServerRecord(oid)

	assert(record, `Object {oid} does not exist`)

	return record
end

local function getObjectTagsSet(oid: ObjectId): { [string]: true }
	local tags: any = serverEcs.get(oid, TagsComponent)

	if type(tags) ~= "table" then
		return {}
	end

	return tags :: { [string]: true }
end

local ServerObjectHandle: { [string]: any } = {}

function ServerObjectHandle:SetPosition(position: Vector3)
	local oid: ObjectId = (self :: any).oid
	local record: ServerObjectRecord = getServerRecord(oid)

	if not serverEcs or not serverEcs.contains(record.oid) then
		return
	end

	serverEcs.set(record.oid, PositionComponent, position)

	broadcastToReplicatedPlayers(record.oid, MSG_POSITION_DELTA, record.oid, position)
end

function ServerObjectHandle:SetProperty(key: string, value: any)
	local oid: ObjectId = (self :: any).oid
	local record: ServerObjectRecord = getServerRecord(oid)

	if not serverEcs or not serverEcs.contains(record.oid) then
		return
	end

	local oldProperties: any = serverEcs.get(record.oid, PropertiesComponent)
	local properties: { [string]: any } = if type(oldProperties) == "table" then deepClone(oldProperties) else {}

	properties[key] = value

	serverEcs.set(record.oid, PropertiesComponent, properties)

	broadcastToReplicatedPlayers(record.oid, MSG_PROPERTY_DELTA, record.oid, key, value)
end

function ServerObjectHandle:GetProperty(key: string): any
	local oid: ObjectId = (self :: any).oid
	local record: ServerObjectRecord = getServerRecord(oid)

	if not serverEcs or not serverEcs.contains(record.oid) then
		return nil
	end

	local properties: any = serverEcs.get(record.oid, PropertiesComponent)

	if type(properties) ~= "table" then
		return nil
	end

	return properties[key]
end

function ServerObjectHandle:AddTag(tag: string)
	local oid: ObjectId = (self :: any).oid
	local record: ServerObjectRecord = getServerRecord(oid)

	if not serverEcs or not serverEcs.contains(record.oid) or type(tag) ~= "string" or tag == "" then
		return
	end

	local oldTags: { [string]: true } = getObjectTagsSet(record.oid)

	if oldTags[tag] == true then
		return
	end

	local tags: { [string]: true } = deepClone(oldTags)
	tags[tag] = true

	serverEcs.set(record.oid, TagsComponent, tags)
	serverEcs.add(record.oid, getOrCreateTagTagEntity(tag))

	broadcastToReplicatedPlayers(record.oid, MSG_TAG_ADD, record.oid, tag)
end

function ServerObjectHandle:RemoveTag(tag: string)
	local oid: ObjectId = (self :: any).oid
	local record: ServerObjectRecord = getServerRecord(oid)

	if not serverEcs or not serverEcs.contains(record.oid) or type(tag) ~= "string" or tag == "" then
		return
	end

	local oldTags: { [string]: true } = getObjectTagsSet(record.oid)

	if oldTags[tag] ~= true then
		return
	end

	local tags: { [string]: true } = deepClone(oldTags)
	tags[tag] = nil

	serverEcs.set(record.oid, TagsComponent, tags)

	local tagEntity: number? = serverTagTagEntities[tag]

	if tagEntity then
		serverEcs.remove(record.oid, tagEntity)
	end

	broadcastToReplicatedPlayers(record.oid, MSG_TAG_REMOVE, record.oid, tag)
end

function ServerObjectHandle:HasTag(tag: string): boolean
	local oid: ObjectId = (self :: any).oid
	local record: ServerObjectRecord = getServerRecord(oid)

	if not serverEcs or not serverEcs.contains(record.oid) or type(tag) ~= "string" or tag == "" then
		return false
	end

	local tags: { [string]: true } = getObjectTagsSet(record.oid)

	return tags[tag] == true
end

function ServerObjectHandle:GetTags(): { string }
	local oid: ObjectId = (self :: any).oid
	local record: ServerObjectRecord = getServerRecord(oid)

	if not serverEcs or not serverEcs.contains(record.oid) then
		return {}
	end

	return tagsSetToArray(getObjectTagsSet(record.oid))
end

function ServerObjectHandle:SetState(stateName: string): boolean
	local oid: ObjectId = (self :: any).oid
	local record: ServerObjectRecord = getServerRecord(oid)

	local stateMachine: BufferFSM.FSM? = record.stateMachine

	if stateMachine == nil then
		return false
	end

	local changed: boolean = stateMachine:SetState(stateName)

	if changed then
		broadcastToReplicatedPlayers(record.oid, MSG_STATE_DELTA, record.oid, stateMachine:Serialize())
	end

	return changed
end

function ServerObjectHandle:GetState(): string?
	local oid: ObjectId = (self :: any).oid
	local record: ServerObjectRecord = getServerRecord(oid)

	if record.stateMachine == nil then
		return nil
	end

	return record.stateMachine:GetState()
end

function ServerObjectHandle:GetStateDuration(): number?
	local oid: ObjectId = (self :: any).oid
	local record: ServerObjectRecord = getServerRecord(oid)

	if record.stateMachine == nil then
		return nil
	end

	return record.stateMachine:GetDuration()
end

function ServerObjectHandle:FireClient(player: Player, ...: any)
	local oid: ObjectId = (self :: any).oid

	if not isPlayerReplicatingObject(player, oid) then
		return
	end

	sendToPlayer(player, MSG_SERVER_EVENT, oid, ...)
end

function ServerObjectHandle:FireClients(...: any)
	broadcastToReplicatedPlayers((self :: any).oid, MSG_SERVER_EVENT, (self :: any).oid, ...)
end

function ServerObjectHandle:OnClientEvent(callback: (player: Player, ...any) -> ())
	local record: ServerObjectRecord = getServerRecord((self :: any).oid)

	return record.onClientEventSignal:Connect(callback)
end

function ServerObjectHandle:OnDestroy(callback: () -> ())
	local record: ServerObjectRecord = getServerRecord((self :: any).oid)

	return record.onDestroySignal:Connect(callback)
end

function ServerObjectHandle:GetButler(): Butler.Butler
	local record: ServerObjectRecord = getServerRecord((self :: any).oid)

	return record.butler
end

local function destroyServerObject(oid: ObjectId)
	local record: ServerObjectRecord? = tryGetServerRecord(oid)

	if not record then
		return
	end

	serverDestroyingObjects[oid] = true

	removeObjectFromAllPlayers(oid)

	if serverEcs and serverEcs.contains(oid) then
		serverEcs.clear(oid, true)
	end

	serverDestroyingObjects[oid] = nil

	gridRemoveObject(oid)
	serverAlwaysReplicatedObjects[oid] = nil
	serverWhitelistObjects[oid] = nil
	serverPlayersByObject[oid] = nil

	record.onDestroySignal:Fire()
	record.onDestroySignal:Destroy()
	record.onClientEventSignal:Destroy()
	record.butler:Destroy()

	recomputeMaxReplicateDistance()
end

function ServerObjectHandle:Destroy()
	destroyServerObject((self :: any).oid)
end

local function getServerHandle(oid: ObjectId): ObjectHandle
	assert(serverEcs and serverEcs.contains(oid), `Object {oid} does not exist`)

	local handle: any = serverEcs.get(oid, ServerHandleComponent)

	if handle ~= nil then
		return handle :: ObjectHandle
	end

	local className: any = serverEcs.get(oid, ClassComponent)

	assert(type(className) == "string", `Object {oid} is missing class data`)

	local instance: ObjectHandle = table.freeze({
		oid = oid,
		class = className,

		SetPosition      = ServerObjectHandle.SetPosition,
		SetProperty      = ServerObjectHandle.SetProperty,
		GetProperty      = ServerObjectHandle.GetProperty,
		AddTag           = ServerObjectHandle.AddTag,
		RemoveTag        = ServerObjectHandle.RemoveTag,
		HasTag           = ServerObjectHandle.HasTag,
		GetTags          = ServerObjectHandle.GetTags,
		SetState         = ServerObjectHandle.SetState,
		GetState         = ServerObjectHandle.GetState,
		GetStateDuration = ServerObjectHandle.GetStateDuration,
		FireClient       = ServerObjectHandle.FireClient,
		FireClients      = ServerObjectHandle.FireClients,
		OnClientEvent    = ServerObjectHandle.OnClientEvent,
		OnDestroy        = ServerObjectHandle.OnDestroy,
		GetButler        = ServerObjectHandle.GetButler,
		Destroy          = ServerObjectHandle.Destroy,
	}) :: any

	serverEcs.set(oid, ServerHandleComponent, instance)

	return instance
end

local function serverUpdatePlayer(player: Player, position: Vector3?)
	if not serverInitialized then
		return
	end

	if player.Parent ~= Players then
		return
	end

	local referencePosition: Vector3? = position or getPlayerPosition(player)

	local candidates: { [ObjectId]: true } = collectCandidateObjects(referencePosition)

	local currentSet: { [ObjectId]: true } = serverReplicatedByPlayer[player]

	if currentSet == nil then
		currentSet = {}
		serverReplicatedByPlayer[player] = currentSet
	end

	local nextSet: { [ObjectId]: true } = {}

	for oid: ObjectId in candidates do
		if shouldReplicateObjectToPlayer(player, oid, referencePosition) then
			nextSet[oid] = true

			if not currentSet[oid] then
				addObjectToPlayerReplication(player, oid)
			end
		end
	end

	local toRemove: { ObjectId } = {}

	for oid: ObjectId in currentSet do
		if not nextSet[oid] then
			table.insert(toRemove, oid)
		end
	end

	for _, oid: ObjectId in toRemove do
		removeObjectFromPlayerReplication(player, oid)
	end
end

local function serverGet(oid: ObjectId): ObjectHandle?
	if tryGetServerRecord(oid) == nil then
		return nil
	end

	return getServerHandle(oid)
end

local function ensureServerInitialized()
	assert(serverInitialized, "ObjectWorld.server.init must be called first")
end

local function serverQueryClass(className: string): { ObjectHandle }
	ensureServerInitialized()

	local tagEntity: number? = serverClassTagEntities[className]

	if not tagEntity or not serverEcs then
		return {}
	end

	local collection: { ObjectHandle } = {}

	for oid: any in serverEcs.query(tagEntity):entities() do
		if tryGetServerRecord(oid) then
			table.insert(collection, getServerHandle(oid))
		end
	end

	return collection
end

local function serverQueryTag(tag: string): { ObjectHandle }
	ensureServerInitialized()

	if not serverEcs then
		return {}
	end

	local tagEntity: number? = serverTagTagEntities[tag]

	if not tagEntity then
		return {}
	end

	local collection: { ObjectHandle } = {}

	for oid: any in serverEcs.query(tagEntity):entities() do
		if tryGetServerRecord(oid) then
			table.insert(collection, getServerHandle(oid))
		end
	end

	return collection
end

local function serverQueryTags(...: string): { ObjectHandle }
	ensureServerInitialized()

	local count: number = select("#", ...)

	if not serverEcs or count == 0 then
		return {}
	end

	local tagEntities: { number } = {}
	local seenTagEntities: { [number]: true } = {}

	for i: number = 1, count do
		local tagName: any = select(i, ...)

		if type(tagName) ~= "string" then
			return {}
		end

		local tagEntity: number? = serverTagTagEntities[tagName]

		if not tagEntity then
			return {}
		end

		if seenTagEntities[tagEntity] ~= true then
			seenTagEntities[tagEntity] = true
			table.insert(tagEntities, tagEntity)
		end
	end

	if #tagEntities == 0 then
		return {}
	end

	local collection: { ObjectHandle } = {}

	for oid: any in serverEcs.query(table.unpack(tagEntities, 1, #tagEntities)):entities() do
		if tryGetServerRecord(oid) then
			table.insert(collection, getServerHandle(oid))
		end
	end

	return collection
end

local function serverQueryNear(position: Vector3, radius: number): { ObjectHandle }
	ensureServerInitialized()

	local radiusSquared: number = radius * radius
	local result: { ObjectHandle } = {}

	if not serverQuadTree then
		return result
	end

	local nodes: { QuadTree.Node<ObjectId> } = serverQuadTree:QueryRange(QTRectangle.fromXZRadius(position, radius))

	for _, node: QuadTree.Node<ObjectId> in nodes do
		local oid: ObjectId = node.Identifier

		if tryGetServerRecord(oid) then
			local objectPosition: any = serverEcs.get(oid, PositionComponent)

			if typeof(objectPosition) == "Vector3" then
				local delta: Vector3 = (objectPosition :: Vector3) - position

				if delta.X * delta.X + delta.Y * delta.Y + delta.Z * delta.Z <= radiusSquared then
					table.insert(result, getServerHandle(oid))
				end
			end
		end
	end

	return result
end

local function serverEcsAccessor(): any
	ensureServerInitialized()

	return serverEcs
end

local function serverOnClientEventForClass(className: string, callback: (player: Player, object: ObjectHandle, ...any) -> ())
	ensureServerInitialized()

	return getClassServerSignal(className):Connect(callback)
end

local function serverOnClientEventForTag(tag: string, callback: (player: Player, object: ObjectHandle, ...any) -> ())
	ensureServerInitialized()

	return getTagServerSignal(tag):Connect(callback)
end

local function serverSpawn(descriptor: ObjectDescriptor): ObjectHandle
	ensureServerInitialized()

	assert(type(descriptor.class) == "string" and descriptor.class ~= "", "Object descriptor requires class")
	assert(type(descriptor.name)  == "string" and descriptor.name  ~= "", "Object descriptor requires name")

	local oid: ObjectId = serverEcs.entity()

	serverSpawningObjects[oid] = true

	local record: ServerObjectRecord = {
		oid = oid,

		onClientEventSignal = newSignal(),
		onDestroySignal     = newSignal(),

		butler              = Butler.new(),

		states              = nil,
		transitions         = nil,

		stateMachine        = nil :: any,
	} :: any

	serverEcs.set(oid, ServerRecordComponent, record)
	serverEcs.set(oid, ClassComponent, descriptor.class)
	serverEcs.add(oid, getOrCreateClassTagEntity(descriptor.class))
	serverEcs.set(oid, NameComponent, descriptor.name)

	local tags: { [string]: true } = {}

	if descriptor.tags ~= nil then
		for _, tag: any in descriptor.tags do
			if type(tag) == "string" and tag ~= "" and tags[tag] ~= true then
				tags[tag] = true
				serverEcs.add(oid, getOrCreateTagTagEntity(tag))
			end
		end
	end

	serverEcs.set(oid, TagsComponent, tags)

	if descriptor.position ~= nil then
		serverEcs.set(oid, PositionComponent, descriptor.position)
	end

	if descriptor.replicateDistance ~= nil then
		serverEcs.set(oid, ReplicateDistanceComponent, descriptor.replicateDistance)
	end

	if descriptor.viewDistance ~= nil then
		serverEcs.set(oid, ViewDistanceComponent, descriptor.viewDistance)
	end

	if descriptor.whitelist ~= nil then
		serverEcs.set(oid, WhitelistComponent, deepClone(descriptor.whitelist))
	end

	serverEcs.set(oid, PropertiesComponent, deepClone(descriptor.properties or {}))

	if descriptor.states ~= nil and #descriptor.states > 0 then
		record.states = deepClone(descriptor.states)
		record.transitions = descriptor.transitions and deepClone(descriptor.transitions) or nil
		record.stateMachine = BufferFSM.new(record.states :: { string }, record.transitions)

		serverEcs.set(oid, StateComponent, record.stateMachine)
	end

	serverSpawningObjects[oid] = nil

	refreshObjectReplicationBuckets(oid)

	updateAllPlayersForObject(oid)

	return getServerHandle(oid)
end

local function serverInit(options: ServerOptions?)
	if serverInitialized then
		return
	end

	local opts: ServerOptions = options or {}

	serverRemoteEvent    = opts.remoteEvent    or opts.remote_event
	serverRemoteFunction = opts.remoteFunction or opts.remote_function
	serverWorldSize      = opts.worldSize      or opts.world_size      or 16384
	serverUpdateRate     = opts.updateRate     or opts.update_rate     or 0.25

	assert(serverRemoteEvent,    "ObjectWorld.server.init requires remoteEvent")
	assert(serverRemoteFunction, "ObjectWorld.server.init requires remoteFunction")

	serverQuadTree = QuadTree.new(
		Vector2.new(-serverWorldSize, -serverWorldSize),
		Vector2.new( serverWorldSize,  serverWorldSize)
	)

	serverEcs = b2.ecs(false)

	PositionComponent          = serverEcs.component()
	ClassComponent             = serverEcs.component()
	TagsComponent              = serverEcs.component()
	NameComponent              = serverEcs.component()
	ReplicateDistanceComponent = serverEcs.component()
	ViewDistanceComponent      = serverEcs.component()
	PropertiesComponent        = serverEcs.component()
	StateComponent             = serverEcs.component()
	WhitelistComponent         = serverEcs.component()
	ServerRecordComponent      = serverEcs.component()
	ServerHandleComponent      = serverEcs.component()

	local function onPositionChange(entity: ObjectId, _id: number, value: Vector3)
		if typeof(value) == "Vector3" then
			gridInsertObject(entity, value)
		end

		refreshObjectReplicationBuckets(entity)

		if not serverSpawningObjects[entity] and not serverDestroyingObjects[entity] then
			broadcastToReplicatedPlayers(entity, MSG_POSITION_DELTA, entity, value)
			updateAllPlayersForObject(entity)
		end
	end

	local function onPositionRemove(entity: ObjectId)
		gridRemoveObject(entity)
		refreshObjectReplicationBuckets(entity)

		if not serverSpawningObjects[entity] and not serverDestroyingObjects[entity] then
			broadcastToReplicatedPlayers(entity, MSG_POSITION_DELTA, entity, nil)
			updateAllPlayersForObject(entity)
		end
	end

	local function onReplicateDistanceChange(entity: ObjectId)
		refreshObjectReplicationBuckets(entity)
		recomputeMaxReplicateDistance()

		if not serverSpawningObjects[entity] and not serverDestroyingObjects[entity] then
			updateAllPlayersForObject(entity)
		end
	end

	local function onWhitelistChange(entity: ObjectId)
		refreshObjectReplicationBuckets(entity)

		if not serverSpawningObjects[entity] and not serverDestroyingObjects[entity] then
			updateAllPlayersForObject(entity)
		end
	end

	serverEcs.set(PositionComponent,          b2.OnAdd,    onPositionChange)
	serverEcs.set(PositionComponent,          b2.OnChange, onPositionChange)
	serverEcs.set(PositionComponent,          b2.OnRemove, onPositionRemove)

	serverEcs.set(ReplicateDistanceComponent, b2.OnAdd,    onReplicateDistanceChange)
	serverEcs.set(ReplicateDistanceComponent, b2.OnChange, onReplicateDistanceChange)
	serverEcs.set(ReplicateDistanceComponent, b2.OnRemove, onReplicateDistanceChange)

	serverEcs.set(WhitelistComponent,         b2.OnAdd,    onWhitelistChange)
	serverEcs.set(WhitelistComponent,         b2.OnChange, onWhitelistChange)
	serverEcs.set(WhitelistComponent,         b2.OnRemove, onWhitelistChange)

	serverRemoteFunction.OnServerInvoke = function(player: Player): any
		local playerPosition: Vector3? = getPlayerPosition(player)

		serverUpdatePlayer(player, playerPosition)

		local collection: { any } = {}
		local replicatedSet: { [ObjectId]: true }? = serverReplicatedByPlayer[player]

		if replicatedSet then
			for oid: ObjectId in replicatedSet do
				local snapshot: { [string]: any }? = createObjectSnapshot(oid)

				if snapshot then
					table.insert(collection, snapshot)
				end
			end
		end

		return collection
	end

	serverRemoteEvent.OnServerEvent:Connect(function(player: Player, messageType: number, ...: any)
		if messageType ~= MSG_CLIENT_EVENT then
			return
		end

		local oid: any = ...

		if type(oid) ~= "number" then
			return
		end

		if not isPlayerReplicatingObject(player, oid) then
			return
		end

		local record: ServerObjectRecord? = tryGetServerRecord(oid)

		if not record then
			return
		end

		record.onClientEventSignal:Fire(player, select(2, ...))

		local handle: ObjectHandle = getServerHandle(oid)
		local objectClass: any = serverEcs.get(oid, ClassComponent)

		if type(objectClass) == "string" then
			local cs: Signal.Signal? = serverClientEventByClass[objectClass]

			if cs then
				cs:Fire(player, handle, select(2, ...))
			end
		end

		local objectTags: any = serverEcs.get(oid, TagsComponent)

		if type(objectTags) == "table" then
			for objectTag: any, present: any in objectTags do
				if type(objectTag) == "string" and present == true then
					local ts: Signal.Signal? = serverClientEventByTag[objectTag]

					if ts then
						ts:Fire(player, handle, select(2, ...))
					end
				end
			end
		end
	end)

	local function onPlayerAdded(player: Player)
		serverReplicatedByPlayer[player] = {}

		serverUpdatePlayer(player, getPlayerPosition(player))
	end

	local function onPlayerRemoving(player: Player)
		local replicated: { [ObjectId]: true }? = serverReplicatedByPlayer[player]

		if replicated then
			local toRemove: { ObjectId } = {}

			for oid: ObjectId in replicated do
				table.insert(toRemove, oid)
			end

			for _, oid: ObjectId in toRemove do
				removeObjectFromPlayerReplication(player, oid)
			end
		end

		serverReplicatedByPlayer[player] = nil
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	for _, player: Player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	local elapsed: number = 0

	RunService.Heartbeat:Connect(function(deltaTime: number)
		elapsed += deltaTime

		if elapsed < serverUpdateRate then
			return
		end

		elapsed = 0

		for _, player: Player in Players:GetPlayers() do
			serverUpdatePlayer(player, getPlayerPosition(player))
		end
	end)

	serverInitialized = true
end

local clientInitialized: boolean = false

local clientRemoteEvent: RemoteEvent? = nil
local clientRemoteFunction: RemoteFunction? = nil

local clientViewUpdateRate: number = 0.25
local clientMaxViewDistance: number = 1000

local clientObjectRecords: { [ObjectId]: ClientObjectRecord } = {}
local clientObjectHandles: { [ObjectId]: ClientObject } = {}

local clientQuadTree: QuadTree.QuadTree<number> = QuadTree.new(Vector2.new(-16384, -16384), Vector2.new(16384, 16384))

local clientQuadTreePositions: { [ObjectId]: Vector2 } = {}
local clientViewButlers: { [ObjectId]: Butler.Butler } = {}

local clientServerEventByClass: { [string]: Signal.Signal } = {}
local clientServerEventByTag: { [string]: Signal.Signal } = {}

local clientViewEnterSignal: Signal.Signal = newSignal()
local clientViewLeaveSignal: Signal.Signal = newSignal()

local function getClientClassSignal(className: string): Signal.Signal
	local s: Signal.Signal = clientServerEventByClass[className]

	if not s then
		s = newSignal()

		clientServerEventByClass[className] = s
	end

	return s
end

local function getClientTagSignal(tag: string): Signal.Signal
	local s: Signal.Signal = clientServerEventByTag[tag]

	if not s then
		s = newSignal()

		clientServerEventByTag[tag] = s
	end

	return s
end

local function getClientRecord(oid: ObjectId): ClientObjectRecord
	local record: ClientObjectRecord? = clientObjectRecords[oid]

	assert(record, `Object {oid} is not replicated`)

	return record
end

local ClientObjectHandle: { [string]: any } = {}

local function getClientHandle(oid: ObjectId): ClientObject
	local handle: ClientObject? = clientObjectHandles[oid]

	if handle then
		return handle
	end

	local record: ClientObjectRecord = clientObjectRecords[oid]

	assert(record, `Object {oid} is not replicated`)

	local instance: ClientObject = table.freeze({
		oid = oid,
		class = record.class,

		GetProperty       = ClientObjectHandle.GetProperty,
		GetProperties     = ClientObjectHandle.GetProperties,
		GetPosition       = ClientObjectHandle.GetPosition,
		GetState          = ClientObjectHandle.GetState,
		GetStateDuration  = ClientObjectHandle.GetStateDuration,
		GetAsset          = ClientObjectHandle.GetAsset,
		HasTag            = ClientObjectHandle.HasTag,
		GetTags           = ClientObjectHandle.GetTags,
		OnPropertyChanged = ClientObjectHandle.OnPropertyChanged,
		OnServerEvent     = ClientObjectHandle.OnServerEvent,
		FireServer        = ClientObjectHandle.FireServer,
	}) :: any

	clientObjectHandles[oid] = instance

	return instance
end

function ClientObjectHandle:GetProperty(key: string): any
	return getClientRecord((self :: any).oid).properties[key]
end

function ClientObjectHandle:GetProperties(): { [string]: any }
	return getClientRecord((self :: any).oid).properties
end

function ClientObjectHandle:GetPosition(): Vector3?
	return getClientRecord((self :: any).oid).position
end

function ClientObjectHandle:GetState(): string?
	local record: ClientObjectRecord = getClientRecord((self :: any).oid)

	if record.stateMachine == nil then
		return nil
	end

	return record.stateMachine:GetState()
end

function ClientObjectHandle:GetStateDuration(): number?
	local record: ClientObjectRecord = getClientRecord((self :: any).oid)

	if record.stateMachine == nil then
		return nil
	end

	return record.stateMachine:GetDuration()
end

function ClientObjectHandle:GetAsset(): Instance
	local record: ClientObjectRecord = getClientRecord((self :: any).oid)

	local asset: Instance? = getAsset(record.class, record.name)

	assert(asset, `No asset found for {record.class}:{record.name}`)

	return asset
end

function ClientObjectHandle:HasTag(tag: string): boolean
	if type(tag) ~= "string" or tag == "" then
		return false
	end

	local record: ClientObjectRecord = getClientRecord((self :: any).oid)

	return record.tags[tag] == true
end

function ClientObjectHandle:GetTags(): { string }
	local record: ClientObjectRecord = getClientRecord((self :: any).oid)

	return tagsSetToArray(record.tags)
end

function ClientObjectHandle:OnPropertyChanged(key: string, callback: (oldValue: any, newValue: any) -> ())
	local record: ClientObjectRecord = getClientRecord((self :: any).oid)

	return record.onPropertyChangedSignal:Connect(function(changedKey: string, oldValue: any, newValue: any)
		if changedKey == key then
			callback(oldValue, newValue)
		end
	end)
end

function ClientObjectHandle:OnServerEvent(callback: (...any) -> ()): ...any
	return getClientRecord((self :: any).oid).onServerEventSignal:Connect(callback)
end

function ClientObjectHandle:FireServer(...: any): ...any
	if not clientRemoteEvent then
		return
	end

	clientRemoteEvent:FireServer(MSG_CLIENT_EVENT, (self :: any).oid, ...)
end

local function clientGet(oid: ObjectId): ClientObject?
	if clientObjectRecords[oid] == nil then
		return nil
	end

	return getClientHandle(oid)
end

local function removeClientObject(oid: ObjectId)
	local record: ClientObjectRecord? = clientObjectRecords[oid]

	if not record then
		return
	end

	local viewButler: Butler.Butler? = clientViewButlers[oid]

	if viewButler then
		clientViewLeaveSignal:Fire(oid, getClientHandle(oid), record)

		viewButler:Destroy()

		clientViewButlers[oid] = nil
	end

	local oldPos: Vector2? = clientQuadTreePositions[oid]

	if oldPos then
		clientQuadTree:Remove(oldPos)

		clientQuadTreePositions[oid] = nil
	end

	record.onPropertyChangedSignal:Destroy()
	record.onServerEventSignal:Destroy()

	clientObjectRecords[oid] = nil
	clientObjectHandles[oid] = nil
end

local function upsertClientObject(snapshot: { [string]: any })
	local oid: any = snapshot.oid

	if type(oid) ~= "number" then
		return
	end

	if clientObjectRecords[oid] ~= nil then
		removeClientObject(oid)
	end

	local properties: any = snapshot.properties

	if type(properties) ~= "table" then
		properties = {}
	end

	local tags: { [string]: true } = {}
	local snapshotTags: any = snapshot.tags

	if type(snapshotTags) == "table" then
		for _, tagName: any in snapshotTags do
			if type(tagName) == "string" and tagName ~= "" then
				tags[tagName] = true
			end
		end
	end

	local record: ClientObjectRecord = {
		oid = oid,

		class = tostring(snapshot.class or "Unknown"),
		tags = tags,

		name = tostring(snapshot.name or ""),

		position = if typeof(snapshot.position) == "Vector3"
			then snapshot.position
			else nil,

		replicateDistance = if type(snapshot.replicateDistance) == "number"
			then snapshot.replicateDistance
			else nil,

		viewDistance = if type(snapshot.viewDistance) == "number"
			then snapshot.viewDistance
			else nil,

		properties = deepClone(properties),

		onPropertyChangedSignal = newSignal(),
		onServerEventSignal     = newSignal(),

		states = if type(snapshot.states) == "table"
			then deepClone(snapshot.states)
			else nil,

		transitions = if type(snapshot.transitions) == "table"
			then deepClone(snapshot.transitions)
			else nil,

		stateMachine = nil,
	}

	if record.states ~= nil and #record.states > 0 then
		record.stateMachine = BufferFSM.new(record.states, record.transitions)

		if type(snapshot.fsmData) == "string" and record.stateMachine then
			record.stateMachine:Deserialize(snapshot.fsmData)
		end
	end

	clientObjectRecords[oid] = record

	getClientHandle(oid)

	if record.position then
		local pos2D: Vector2 = toXZ(record.position)

		clientQuadTree:Insert(QuadTree.NewNode(pos2D, oid))

		clientQuadTreePositions[oid] = pos2D
	end
end

local function evaluateClientView()
	local localPlayer: Player? = Players.LocalPlayer

	if not localPlayer then
		return
	end

	local playerPosition: Vector3? = getPlayerPosition(localPlayer)

	if not playerPosition then
		for oid: number, viewButler: Butler.Butler in clientViewButlers do
			local record: ClientObjectRecord = clientObjectRecords[oid]
			local handle: ClientObject = clientObjectHandles[oid]

			if record and handle then
				clientViewLeaveSignal:Fire(oid, handle, record)
			end

			viewButler:Destroy()

			clientViewButlers[oid] = nil
		end

		return
	end

	local foundInView: { [ObjectId]: true } = {}

	local queryNodes: { QuadTree.Node<ObjectId> } = clientQuadTree:QueryRange(QTRectangle.fromXZRadius(playerPosition, clientMaxViewDistance))

	for _, queryNode: QuadTree.Node<ObjectId> in queryNodes do
		local oid: ObjectId = queryNode.Identifier
		local record: ClientObjectRecord = clientObjectRecords[oid]

		if not record or not record.position then
			continue
		end

		local viewDistance: any = record.viewDistance

		if type(viewDistance) ~= "number" then
			continue
		end

		local delta: Vector3 = record.position - playerPosition
		local distSq: number = delta.X * delta.X + delta.Y * delta.Y + delta.Z * delta.Z

		if distSq <= (viewDistance :: number) * (viewDistance :: number) then
			foundInView[oid] = true

			if clientViewButlers[oid] == nil then
				local viewButler: Butler.Butler = Butler.new()

				clientViewButlers[oid] = viewButler

				clientViewEnterSignal:Fire(oid, getClientHandle(oid), record, viewButler)
			end
		end
	end

	for oid: number, viewButler: Butler.Butler in clientViewButlers do
		if not foundInView[oid] then
			local record: ClientObjectRecord = clientObjectRecords[oid]
			local handle: ClientObject = clientObjectHandles[oid]

			if record and handle then
				clientViewLeaveSignal:Fire(oid, handle, record)
			end

			viewButler:Destroy()

			clientViewButlers[oid] = nil
		end
	end
end

local function onClientMessage(messageType: number, ...: any)
	if messageType == MSG_OBJECT_ADD then
		local snapshot: any = ...

		if type(snapshot) == "table" then
			upsertClientObject(snapshot)
		end

		evaluateClientView()

		return
	end

	if messageType == MSG_OBJECT_REMOVE then
		local oid: any = ...

		if type(oid) == "number" then
			removeClientObject(oid)
		end

		return
	end

	if messageType == MSG_PROPERTY_DELTA then
		local oid: any  = ...
		local key: any  = select(2, ...)
		local value: any = select(3, ...)

		if type(oid) ~= "number" or type(key) ~= "string" then
			return
		end

		local record: ClientObjectRecord = clientObjectRecords[oid]

		if not record then
			return
		end

		local oldValue: any = record.properties[key]

		record.properties[key] = value

		record.onPropertyChangedSignal:Fire(key, oldValue, value)

		return
	end

	if messageType == MSG_POSITION_DELTA then
		local oid: any        = ...
		local newPosition: any = select(2, ...)

		if type(oid) ~= "number" then
			return
		end

		local record: ClientObjectRecord = clientObjectRecords[oid]

		if not record then
			return
		end

		if typeof(newPosition) == "Vector3" then
			record.position = newPosition

			local oldPos: Vector2? = clientQuadTreePositions[oid]

			if oldPos then
				clientQuadTree:Remove(oldPos)
			end

			local newPos2D: Vector2 = toXZ(newPosition)

			clientQuadTree:Insert(QuadTree.NewNode(newPos2D, oid))

			clientQuadTreePositions[oid] = newPos2D
		else
			record.position = nil

			local oldPos: Vector2? = clientQuadTreePositions[oid]

			if oldPos then
				clientQuadTree:Remove(oldPos)

				clientQuadTreePositions[oid] = nil
			end
		end

		evaluateClientView()

		return
	end

	if messageType == MSG_STATE_DELTA then
		local oid: any          = ...
		local serializedData: any = select(2, ...)

		if type(oid) ~= "number" or type(serializedData) ~= "string" then
			return
		end

		local record: ClientObjectRecord = clientObjectRecords[oid]

		if not record then
			return
		end

		if record.stateMachine == nil and record.states ~= nil and #record.states > 0 then
			record.stateMachine = BufferFSM.new(record.states, record.transitions)
		end

		if record.stateMachine then
			record.stateMachine:Deserialize(serializedData)
		end

		return
	end

	if messageType == MSG_TAG_ADD then
		local oid: any = ...
		local tagName: any = select(2, ...)

		if type(oid) ~= "number" or type(tagName) ~= "string" then
			return
		end

		local record: ClientObjectRecord = clientObjectRecords[oid]

		if not record or tagName == "" then
			return
		end

		record.tags[tagName] = true

		return
	end

	if messageType == MSG_TAG_REMOVE then
		local oid: any = ...
		local tagName: any = select(2, ...)

		if type(oid) ~= "number" or type(tagName) ~= "string" then
			return
		end

		local record: ClientObjectRecord = clientObjectRecords[oid]

		if not record or tagName == "" then
			return
		end

		record.tags[tagName] = nil

		return
	end

	if messageType == MSG_SERVER_EVENT then
		local oid: any = ...

		if type(oid) ~= "number" then
			return
		end

		local record: ClientObjectRecord = clientObjectRecords[oid]

		if not record then
			return
		end

		local handle: ClientObject = getClientHandle(oid)

		record.onServerEventSignal:Fire(select(2, ...))

		local cs: Signal.Signal? = clientServerEventByClass[record.class]

		if cs then
			cs:Fire(handle, select(2, ...))
		end

		for recordTag: any, present: any in record.tags do
			if type(recordTag) == "string" and present == true then
				local ts: Signal.Signal? = clientServerEventByTag[recordTag]

				if ts then
					ts:Fire(handle, select(2, ...))
				end
			end
		end
	end
end

local function clientOnEnter(className: string, callback: (viewButler: Butler.Butler, object: ClientObject) -> ()): any
	return clientViewEnterSignal:Connect(function(_oid: ObjectId, handle: ClientObject, record: ClientObjectRecord, viewButler: Butler.Butler)
		if record.class == className then
			Thread.spawn(callback, viewButler, handle)
		end
	end)
end

local function clientOnEnterWithTag(className: string, tag: string, callback: (viewButler: Butler.Butler, object: ClientObject) -> ()): any
	return clientViewEnterSignal:Connect(function(_oid: ObjectId, handle: ClientObject, record: ClientObjectRecord, viewButler: Butler.Butler)
		if record.class == className and record.tags[tag] == true then
			Thread.spawn(callback, viewButler, handle)
		end
	end)
end

local function clientOnLeave(className: string, callback: (object: ClientObject) -> ()): any
	return clientViewLeaveSignal:Connect(function(_oid: ObjectId, handle: ClientObject, record: ClientObjectRecord)
		if record.class == className then
			Thread.spawn(callback, handle)
		end
	end)
end

local function clientOnLeaveWithTag(className: string, tag: string, callback: (object: ClientObject) -> ()): any
	return clientViewLeaveSignal:Connect(function(_oid: ObjectId, handle: ClientObject, record: ClientObjectRecord)
		if record.class == className and record.tags[tag] == true then
			Thread.spawn(callback, handle)
		end
	end)
end

local function clientOnServerEventForClass(className: string, callback: (object: ClientObject, ...any) -> ()): any
	return getClientClassSignal(className):Connect(callback)
end

local function clientOnServerEventForTag(tag: string, callback: (object: ClientObject, ...any) -> ()): any
	return getClientTagSignal(tag):Connect(callback)
end

local function clientInit(options: ClientOptions?)
	if clientInitialized then
		return
	end

	local opts: ClientOptions = options or {}

	clientRemoteEvent     = opts.remoteEvent      or opts.remote_event
	clientRemoteFunction  = opts.remoteFunction   or opts.remote_function
	clientViewUpdateRate  = opts.viewUpdateRate   or opts.view_update_rate   or 0.25
	clientMaxViewDistance = opts.maxViewDistance  or opts.max_view_distance  or 1000

	assert(clientRemoteEvent,    "ObjectWorld.client.init requires remoteEvent")
	assert(clientRemoteFunction, "ObjectWorld.client.init requires remoteFunction")

	clientRemoteEvent.OnClientEvent:Connect(function(messageType: number, ...: any)
		onClientMessage(messageType, ...)
	end)

	local snapshots: any = clientRemoteFunction:InvokeServer()

	if type(snapshots) == "table" then
		for _, snapshot: any in snapshots do
			if type(snapshot) == "table" then
				upsertClientObject(snapshot)
			end
		end
	end

	evaluateClientView()

	local elapsed: number = 0

	RunService.Heartbeat:Connect(function(deltaTime: number)
		elapsed += deltaTime

		if elapsed < clientViewUpdateRate then
			return
		end

		elapsed = 0

		evaluateClientView()
	end)

	clientInitialized = true
end

return table.freeze({
	server = table.freeze({
		init                  = serverInit,
		spawn                 = serverSpawn,
		get                   = serverGet,

		updatePlayer          = serverUpdatePlayer,

		queryClass            = serverQueryClass,
		queryTag              = serverQueryTag,
		queryTags             = serverQueryTags,
		queryNear             = serverQueryNear,

		ecs                   = serverEcsAccessor,

		onClientEventForClass = serverOnClientEventForClass,
		onClientEventForTag   = serverOnClientEventForTag,

		_messageTypes         = table.freeze({
			OBJECT_ADD      = MSG_OBJECT_ADD,
			OBJECT_REMOVE   = MSG_OBJECT_REMOVE,
			PROPERTY_DELTA  = MSG_PROPERTY_DELTA,
			POSITION_DELTA  = MSG_POSITION_DELTA,
			STATE_DELTA     = MSG_STATE_DELTA,
			SERVER_EVENT    = MSG_SERVER_EVENT,
			CLIENT_EVENT    = MSG_CLIENT_EVENT,
			TAG_ADD         = MSG_TAG_ADD,
			TAG_REMOVE      = MSG_TAG_REMOVE,
		}),
	}) :: ServerNamespace,

	client = table.freeze({
		init                 = clientInit,
		get                  = clientGet,

		onEnter              = clientOnEnter,
		onEnterWithTag       = clientOnEnterWithTag,

		onLeave              = clientOnLeave,
		onLeaveWithTag       = clientOnLeaveWithTag,

		onServerEventForClass = clientOnServerEventForClass,
		onServerEventForTag  = clientOnServerEventForTag,
	}) :: ClientNamespace,

	shared = table.freeze({
		registerAsset = registerAsset,
		getAsset      = getAsset,
	}) :: SharedNamespace,

	registerAsset = registerAsset,
	getAsset      = getAsset,
}) :: ObjectWorldModule