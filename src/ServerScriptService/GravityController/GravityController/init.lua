local RunService = game:GetService("RunService")

local Utility = script:WaitForChild("Utility")
local CharacterModules = script:WaitForChild("CharacterModules")

local Maid = require(Utility:WaitForChild("Maid"))
local Camera = require(CharacterModules:WaitForChild("Camera"))
local Control = require(CharacterModules:WaitForChild("Control"))
local Collider = require(script:WaitForChild("Collider"))

-- CONSTANTS

local TRANSITION = 0.15
local WALK_FORCE = 200 / 3

local ZERO3 = Vector3.new(0, 0, 0)
local UNIT_Y = Vector3.new(0, 1, 0)

-- Class

local GravityControllerClass = {}
GravityControllerClass.__index = GravityControllerClass
GravityControllerClass.ClassName = "GravityController"

-- Public Constructors

function GravityControllerClass.new(player)
	local self = setmetatable({}, GravityControllerClass)

	self.Player = player
	self.Character = player.Character
	self.Humanoid = player.Character:WaitForChild("Humanoid")
	self.HRP = self.Humanoid.RootPart

	self._gravityUp = UNIT_Y
	self._characterMass = 0

	self._camera = Camera.new(self)
	self._control = Control.new(self)
	self._collider = Collider.new(self)

	self.Maid = Maid.new()

	init(self)

	return self
end

-- Private Methods

local function getRotationBetween(u, v, axis)
	local dot, uxv = u:Dot(v), u:Cross(v)
	if dot < -0.99999 then return CFrame.fromAxisAngle(axis, math.pi) end
	return CFrame.new(0, 0, 0, uxv.x, uxv.y, uxv.z, 1 + dot)
end

local function getModelMass(model)
	local mass = 0
	for _, part in pairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			mass = mass + part:GetMass()
		end
	end
	return mass
end

local function onGravityStep(self, dt)
	local camCF = workspace.CurrentCamera.CFrame

	-- update the gravity vector
	local oldGravity = self._gravityUp
	local newGravity = self:GetGravityUp(oldGravity)

	local sphericalArc = getRotationBetween(oldGravity, newGravity, camCF.XVector)
	local lerpedArc = CFrame.new():Lerp(sphericalArc, TRANSITION)

	self._gravityUp = lerpedArc * oldGravity

	-- get world move vector
	local fDot = camCF.ZVector:Dot(newGravity)
	local cForward = math.abs(fDot) > 0.5 and math.sign(fDot)*camCF.YVector or -camCF.ZVector
	
	local left = -cForward:Cross(newGravity).Unit
	local forward = -left:Cross(newGravity).Unit

	local move = self._control:GetMoveVector()
	local worldMove = forward*move.z - left*move.x
	
	local isInputMoving = false
	local length = worldMove.Magnitude
	if length > 0 then
		isInputMoving = true
		worldMove = worldMove / length
	end

	-- get the desired character cframe
	local hrpLook = -self.HRP.CFrame.ZVector
	local charForward = hrpLook:Dot(forward)*forward + hrpLook:Dot(left)*left
	local charRight = charForward:Cross(newGravity).Unit

	local newCharRotation = CFrame.new()
	local newCharCF = CFrame.fromMatrix(ZERO3, charRight, newGravity, -charForward)

	if isInputMoving then
		newCharRotation = newCharRotation:Lerp(getRotationBetween(
			charForward,
			worldMove,
			newGravity
		), 0.7)
	end

	-- calculate forces
	local g = workspace.Gravity
	local gForce = g * self._characterMass * (UNIT_Y - newGravity)

	local cVelocity = self.HRP.Velocity
	local tVelocity = self.Humanoid.WalkSpeed * worldMove
	local gVelocity = cVelocity:Dot(newGravity)*newGravity
	local hVelocity = cVelocity - gVelocity

	if hVelocity:Dot(hVelocity) < 1 then
		hVelocity = ZERO3
	end

	local dVelocity = tVelocity - hVelocity
	local dVelocityM = dVelocity.Magnitude

	local walkForceM = math.min(10000, WALK_FORCE * self._characterMass * dVelocityM / (dt*60))
	local walkForce = walkForceM > 0 and (dVelocity / dVelocityM)*walkForceM or ZERO3

	local charRotation = newCharRotation * newCharCF

	self._collider:Update(walkForce + gForce, charRotation)
end

function init(self)
	self.Maid:Mark(self._camera)
	self.Maid:Mark(self._control)
	self.Maid:Mark(self._collider)

	self._characterMass = getModelMass(self.Character)
	self.Maid:Mark(self.Character.AncestryChanged:Connect(function()
		self._characterMass = getModelMass(self.Character)
	end))

	self.Humanoid.PlatformStand = true

	RunService:BindToRenderStep("GravityStep", Enum.RenderPriority.Camera.Value + 1, function(dt)
		onGravityStep(self, dt)
	end)
end

-- Public Methods

function GravityControllerClass:GetGravityUp(oldGravity)
	return oldGravity
end

function GravityControllerClass:Destroy()
	RunService:UnbindFromRenderStep("GravityStep")
	self.Maid:Sweep()
	self.Humanoid.PlatformStand = false
end

--

return GravityControllerClass