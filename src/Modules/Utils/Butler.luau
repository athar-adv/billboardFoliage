--!optimize 2
--!strict

--Sovereignty

type CleanHandler<T> = (task: T) -> ()

type TypeHandlers = {
	Instance: CleanHandler<Instance>,
	RBXScriptConnection: CleanHandler<RBXScriptConnection>,
	thread: CleanHandler<thread>,
	["function"]: CleanHandler<(...any) -> ...any>,
	table: CleanHandler<{ [any]: any }>,
}

type ButlerData = {
	destroyed: boolean,
	n: number,
	[number]: any,
}

export type Butler = {
	Add: (self: Butler, task: any) -> any?,
	Clean: (self: Butler) -> (),
	FastClean: (self: Butler) -> (),
	Destroy: (self: Butler) -> (),
	IsDestroyed: (self: Butler) -> boolean,
	_: ButlerData,
}

local Butler: Butler & { [string]: any } = {} :: { [string]: any } & Butler

local taskCancel: (thread) -> () = task.cancel

local cleanSingle: (task: any) -> ()

local function isInstanceDestroyed(obj: Instance): boolean
	if obj.Parent == nil then
		local _, err = pcall(function()
			obj.Parent = UserSettings() :: any
		end)

		return err ~= "Not allowed to add that under settings"
	end

	return false
end

local typeHandlers: TypeHandlers = table.freeze({
	Instance = function(t: Instance): ()
		if not isInstanceDestroyed(t) then
			t:Destroy()
		end
	end,

	RBXScriptConnection = function(t: RBXScriptConnection)
		t:Disconnect()
	end,

	thread = function(t: thread)
		pcall(taskCancel, t)
	end,

	["function"] = function(t: (...any) -> ...any)
		t()
	end,

	table = function(t: { [any]: any })
		local method: any = t.disconnect or t.Disconnect
			or t.destroy or t.Destroy

		if method then
			method(t)

			return
		end

		if getmetatable(t :: any) then
			setmetatable(t, nil)

			table.clear(t :: any)
		else
			for _, v: any in t do
				cleanSingle(v)
			end
		end
	end,
})

function cleanSingle(t: any)
	local handler: CleanHandler<any>? = (typeHandlers :: any)[typeof(t)]

	if handler then
		handler(t)
	end
end

local function add(self: Butler, addTask: any): any
	if addTask == nil then
		return nil
	end

	local data: ButlerData = self._
	if data.destroyed then
		warn("[Butler] Attempting to add to a destroyed Butler.")
		return nil
	end

	local n: number = data.n + 1

	data.n = n
	data[n] = addTask

	return addTask
end

local function fastClean(self: Butler)
	local data: ButlerData = self._

	for i = data.n, 1, -1 do
		local t: any = data[i]

		data[i] = nil

		cleanSingle(t)
	end

	data.n = 0
end

local function clean(self: Butler)
	local data: ButlerData = self._

	for i = 1, data.n do
		local t: any = data[i]

		data[i] = nil

		cleanSingle(t)
	end

	data.n = 0
end

local function destroy(self: Butler)
	local data: ButlerData = self._
	
	if data.destroyed then
		return
	end

	fastClean(self)

	data.destroyed = true
end

local function isDestroyed(self: Butler): boolean
	return self._.destroyed
end

function Butler.new(size: number?): Butler
	local data: ButlerData = (if size then table.create(size) else {}) :: ButlerData

	data.n = 0
	data.destroyed = false

	local instance: Butler = {
		_ = data,

		Add = add,
		Clean = clean,
		FastClean = fastClean,
		Destroy = destroy,
		IsDestroyed = isDestroyed,
	} :: any

	return table.freeze(instance) :: any
end

return Butler