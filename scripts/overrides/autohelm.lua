local InventoryFunctions = require "util/inventoryfunctions"

local UpdateRateInFrames = 5
-- local EPIC_TAGS = { "epic" }

-- local function IsNearBoss()
--     local x, y, z = ThePlayer.Transform:GetWorldPosition()
--     return #TheSim:FindEntities(x, y, z, 30, EPIC_TAGS) > 0
-- end

local function IsSleeping(target)
    return target.AnimState:IsCurrentAnimation("sleep_pre")
        or target.AnimState:IsCurrentAnimation("sleep_loop")
        or target.AnimState:IsCurrentAnimation("sleep_pst")
end

local function IsInCombat()
    local x, y, z = ThePlayer.Transform:GetWorldPosition()
    local ents = TheSim:FindEntities(x, y, z, 30, {"_combat"})

    for i = 1, #ents do
        if ents[i].replica and ents[i].replica.combat then
            if ents[i].replica.combat:GetTarget() == ThePlayer and not IsSleeping(ents[i]) then
                return true
            end
        end
    end

    -- @TODO Could be better
    -- return IsNearBoss()
end

local function EquipHelm()
    InventoryFunctions:Equip(
        ThePlayer.components.actioncontroller:GetItemFromCategory("ARMORHAT"),
        true
    )
end

local function UnEquipHelm()
    local item = InventoryFunctions:GetEquippedItem(EQUIPSLOTS.HEAD)

    if not item then
        return
    end

    SendRPCToServer(RPC.ControllerUseItemOnSelfFromInvTile, ACTIONS.UNEQUIP.code, item)
end

local function IsWearingHelm()
    return InventoryFunctions:GetEquippedItem(EQUIPSLOTS.HEAD) == ThePlayer.components.actioncontroller:GetItemFromCategory("ARMORHAT")
end

local function Init()
    if not ThePlayer then
        return
    end

    local trigger = nil
    local oldHelm = nil

    StartThread(function()
        while ThePlayer do
            if not IsWearingHelm() and IsInCombat() then
                oldHelm = InventoryFunctions:GetEquippedItem(EQUIPSLOTS.HEAD)
                EquipHelm()
                trigger = true
            elseif trigger and not IsInCombat() and IsWearingHelm() then
                if oldHelm then
                    InventoryFunctions:Equip(oldHelm)
                elseif InventoryFunctions:HasFreeSlot() then
                    UnEquipHelm()
                end
                oldHelm = nil
                trigger = false
            end
            Sleep(UpdateRateInFrames * FRAMES)
        end
    end, "AutoHelmThread")
end

return Init
