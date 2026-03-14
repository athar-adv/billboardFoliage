--!native
--!optimize 2

local BufferFSM = {}
BufferFSM.__index = BufferFSM

local OFFSET_STATE: number = 0
local OFFSET_TIME: number = 1
local FSM_SIZE: number = 5

export type StateMap = { [string]: number }
export type TransitionTable = { [number]: { [number]: boolean } }

export type FSM = typeof(setmetatable({}, BufferFSM)) & {
	_buffer: buffer,
	_states: StateMap,
	_ids: { [number]: string },
	_transitions: TransitionTable,
}

function BufferFSM.new(states: {string}, transitions: { [string]: {string} }?): FSM
	local self = setmetatable({}, BufferFSM)

	self._states = {}
	self._ids = {}

	for i: number, name: string in ipairs(states) do
		local id: number = i - 1 

		self._states[name] = id
		self._ids[id] = name
	end

	self._transitions = {}

	if transitions then
		for fromName: string, toList: {string} in pairs(transitions) do
			local fromID: number = self._states[fromName]

			if fromID then
				self._transitions[fromID] = {}

				for _, toName: string in ipairs(toList) do
					local toID: number = self._states[toName]

					if toID then
						self._transitions[fromID][toID] = true
					end
				end
			end
		end
	end

	self._buffer = buffer.create(FSM_SIZE)

	buffer.writeu8(self._buffer, OFFSET_STATE, 0)
	buffer.writef32(self._buffer, OFFSET_TIME, os.clock())

	return self :: any
end

function BufferFSM:GetState(): string
	local id: number = buffer.readu8(self._buffer, OFFSET_STATE)

	return self._ids[id] or "Unknown"
end

function BufferFSM:GetStateID(): number
	return buffer.readu8(self._buffer, OFFSET_STATE)
end

function BufferFSM:GetDuration(): number
	local startTime: number = buffer.readf32(self._buffer, OFFSET_TIME)

	return os.clock() - startTime
end

function BufferFSM:SetState(targetStateName: string): boolean
	local targetID: any = self._states[targetStateName]
	if not targetID then return false end

	local currentID: number = buffer.readu8(self._buffer, OFFSET_STATE)

	if self._transitions[currentID] and not self._transitions[currentID][targetID] then
		return false
	end

	buffer.writeu8(self._buffer, OFFSET_STATE, targetID)
	buffer.writef32(self._buffer, OFFSET_TIME, os.clock())

	return true
end

function BufferFSM:Serialize(): string
	return buffer.tostring(self._buffer)
end

function BufferFSM:Deserialize(data: string): ...any
	if #data == FSM_SIZE then
		buffer.writestring(self._buffer, 0, data)
	end
end

function BufferFSM:Reset(): ...any
	buffer.writeu8(self._buffer, OFFSET_STATE, 0)
	buffer.writef32(self._buffer, OFFSET_TIME, os.clock())
end

return BufferFSM