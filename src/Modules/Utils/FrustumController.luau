--!strict
--!native

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FrustumCulling = require(ReplicatedStorage.Modules.Optimisations.FrustumCuller)

export type CullingController = {
	_frustumCulling: FrustumCulling.FrustumCuller?,
	_instanceCallbacks : any,

	_onInstanceEnterView: (self: CullingController, instance: Instance) -> (),
	_onInstanceExitView:  (self: CullingController, instance: Instance) -> (),

	addInstance:    (self: CullingController, instance: Instance, callback: (inView: boolean) -> ()) -> (),
	removeInstance: (self: CullingController, instance: Instance) -> (),

	_Init: (self: CullingController) -> (),
}

local CullingController = {} :: CullingController

CullingController._frustumCulling = nil
CullingController._instanceCallbacks = table.create(20)

function CullingController:_onInstanceEnterView(instance: Instance)
	local callback: (boolean) -> ()? = self._instanceCallbacks[instance]

	if callback then
		callback(true)
	end
end

function CullingController:_onInstanceExitView(instance: Instance)
	local callback: (boolean) -> ()? = self._instanceCallbacks[instance]

	if callback then
		callback(false)
	end
end

function CullingController:addInstance(instance: Instance, callback: (inView: boolean) -> ())
	self._instanceCallbacks[instance] = callback

	if self._frustumCulling then
		self._frustumCulling:Add(instance)
	end
end

function CullingController:removeInstance(instance: Instance)
	if self._frustumCulling then
		self._frustumCulling:Remove(instance)
	end

	self._instanceCallbacks[instance] = nil
end

function CullingController:_Init()
	assert(workspace.CurrentCamera, "Camera must exist before initializing CullingController")

	self._frustumCulling = FrustumCulling.new(
		workspace.CurrentCamera,

		function(instance: Instance) 
            self:_onInstanceEnterView(instance) 
        end,

		function(instance: Instance) 
            self:_onInstanceExitView(instance)
         end
	)
end

return CullingController