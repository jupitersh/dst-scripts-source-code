local function OnSink(inst)
	inst.components.submersible:Submerge()
end

local function OnLanded(inst)
	if inst.components.inventoryitem.owner == nil then
		local x, y, z = inst.Transform:GetWorldPosition()
		if TheWorld.Map:IsOceanAtPoint(x, y, z) then
			inst.components.submersible:Submerge()
		end
	end
end

local Submersible = Class(function(self, inst)
	self.inst = inst

	self.inst:ListenForEvent("onsink", OnSink)
	self.inst:ListenForEvent("on_landed", OnLanded)
end)

function Submersible:OnRemoveFromEntity()
	self.inst:RemoveEventCallback("onsink", Submerge)
	self.inst:RemoveEventCallback("on_landed", OnLanded)
end

function Submersible:GetUnderwaterObject()
	return self.inst.components.inventoryitem ~= nil and self.inst.components.inventoryitem:GetContainer() or nil
end

function Submersible:Submerge()
	local underwater_object = self:GetUnderwaterObject()
	if underwater_object ~= nil and underwater_object:IsValid() then
		return
	end
		
	underwater_object = SpawnPrefab("underwater_salvageable")
	if underwater_object ~= nil then
		local x, y, z = self.inst.Transform:GetWorldPosition()

		underwater_object.Transform:SetPosition(x, y, z)
		underwater_object.components.inventory:GiveItem(self.inst)

		self.inst:PushEvent("on_submerge", { underwater_object = underwater_object })
		
		SpawnPrefab("splash_green").Transform:SetPosition(x, y, z)
	end
end

return Submersible
