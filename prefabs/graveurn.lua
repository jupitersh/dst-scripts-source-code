local assets =
{
	Asset("ANIM", "anim/graveurn.zip"),
	Asset("INV_IMAGE", "graveurn"),
	Asset("INV_IMAGE", "graveurn_empty"),
}

local function on_deployed(inst, pt, deployer)
    local gravestone = (inst._grave_record ~= nil and SpawnSaveRecord(inst._grave_record))
        or SpawnPrefab("gravestone")
    gravestone.Transform:SetPosition(pt:Get())
    gravestone.AnimState:PlayAnimation("grave"..gravestone.random_stone_choice.."_place")
    gravestone.AnimState:PushAnimation("grave"..gravestone.random_stone_choice)

    if deployer.SoundEmitter then
        deployer.SoundEmitter:PlaySound("meta5/wendy/place_gravestone")
    end

    inst:Remove()
end

local function shared_onuse(inst)
    inst.components.inventoryitem:ChangeImageName("graveurn")

    local deployable = inst:AddComponent("deployable")
    deployable.ondeploy = on_deployed

    inst:RemoveComponent("gravedigger")
end

local function OnGravediggerUsed(inst, user, target)
    local tx, ty, tz = target.Transform:GetWorldPosition()

    local target_upgradeable = target.components.upgradeable
    if target_upgradeable and target_upgradeable:GetStage() > 1 then
        target_upgradeable:SetStage(1)
        for _ = 1, TUNING.WENDYSKILL_GRAVESTONE_DECORATECOUNT do
            if math.random() > 0.5 then
                local petals = SpawnPrefab("petals")
                petals.Transform:SetPosition(tx, ty, tz)
                Launch(petals, inst, 1.5)
            end
        end
    end
    inst._grave_record = target:GetSaveRecord()

    SpawnPrefab("attune_out_fx").Transform:SetPosition(tx, ty, tz)

    shared_onuse(inst)
end

--
local function get_status(inst)
    return (inst._grave_record ~= nil and "HAS_SPIRIT")
        or nil
end

--
local function topocket(inst, owner)
    inst.components.timer:StopTimer("idle")
end

local function toground(inst)
    inst.components.timer:StartTimer("idle", 7 + 5 * math.random())
end

--
local function timerdone(inst, data)
    if data.name == "idle" then
        if inst.components.deployable then
            local anim_type = math.random(3)
            if anim_type == 1 then
                inst.AnimState:PlayAnimation("idle_pre")
                inst.AnimState:PushAnimation("idle", false)
                inst.AnimState:PushAnimation("idle_pst", false)
                inst.AnimState:PushAnimation("idle_empty")
            elseif anim_type == 2 then
                inst.AnimState:PlayAnimation("idle_2_pre")
                inst.AnimState:PushAnimation("idle_2", false)
                inst.AnimState:PushAnimation("idle_2_pst", false)
                inst.AnimState:PushAnimation("idle_empty")
            elseif anim_type == 3 then
                inst.AnimState:PlayAnimation("idle_3")
                inst.AnimState:PushAnimation("idle_empty")
            end
        end
        inst.components.timer:StartTimer("idle", 7 + 5 * math.random())
    end
end

-- Save/Load
local function OnSave(inst, data)
    data.grave_record = inst._grave_record
end

local function OnLoad(inst, data)
    if data and data.grave_record then
        inst._grave_record = data.grave_record
        shared_onuse(inst)
    end
end

--
local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()

    MakeInventoryPhysics(inst)
    MakeInventoryFloatable(inst, "small", 0.2, 0.75)

    inst.AnimState:SetBank("graveurn")
    inst.AnimState:SetBuild("graveurn")
    inst.AnimState:PlayAnimation("idle_empty")

    inst:AddTag("graveplanter")

    inst.entity:SetPristine()
    if not TheWorld.ismastersim then
        return inst
    end

    --
    local gravedigger = inst:AddComponent("gravedigger")
    gravedigger.onused = OnGravediggerUsed

    --
    local inspectable = inst:AddComponent("inspectable")
    inspectable.getstatus = get_status

    --
    local inventoryitem = inst:AddComponent("inventoryitem")
    inventoryitem:ChangeImageName("graveurn_empty")

    --
    inst:AddComponent("timer")

    --
    inst:ListenForEvent("onputininventory", topocket)
    inst:ListenForEvent("ondropped", toground)
    inst:ListenForEvent("timerdone", timerdone)

    --
    inst.OnSave = OnSave
    inst.OnLoad = OnLoad

    return inst
end

--
local function graveurn_placer_postinit(inst)
    inst.AnimState:Hide("flower")
end

return Prefab("graveurn", fn, assets),
    MakePlacer(
        "graveurn_placer", "gravestone", "gravestones", "grave1",
        nil, nil, nil, nil, nil, nil, graveurn_placer_postinit
    )