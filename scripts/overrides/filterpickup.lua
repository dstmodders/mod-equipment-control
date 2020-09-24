local InventoryFunctions = require "util/inventoryfunctions"
local KeybindService = MOD_EQUIPMENT_CONTROL.KEYBINDSERVICE
local FileSystem = require "util/filesystem"
local Say = require "util/say"

-- 
-- Config
-- 

local PRIOTIZE_VALUABLE_ITEMS = GetModConfigData("PRIOTIZE_VALUABLE_ITEMS", MOD_EQUIPMENT_CONTROL.MODNAME)
local Filter_File = "mod_equipment_control_pickup_filter.txt"
local PriotizedPickups =
{
    deerclops_eyeball = 2,
    minotaurhorn = 1,
    hivehat = 2,
    dragon_scales = 1,
    bearger_fur = 1,
    klaussackkey = 2,
    shadowheart = 1,
    skeletonhat = 3,
    armorskeleton = 3,
    shroom_skin = 1,
    ["Blue Funcap Blueprint"] = 3,
    ["Green Funcap Blueprint"] = 3,
    ["Red Funcap Blueprint"] = 3,
    ["Mushlight Blueprint"] = 3,
    ["Glowcap Blueprint"] = 3,
    ["Scaled Furnace Blueprint"] = 2,
    ["Bundling Wrap Blueprint"] = 3,
    ["Winged Sail Kit Blueprint"] = 3,
    ["Feathery Canvas Blueprint"] = 3,
    ["The Lazy Deserter Blueprint"] = 1,
    ["Strident Trident Blueprint"] = 3,
}

local PickupFilter =
{
    tags = {},
    prefabs = {},
}

local function AddFilteredPrefab(prefab)
    PickupFilter.prefabs[prefab] = true
end

local function AddFilteredTag(tag)
    table.insert(PickupFilter.tags, tag)
end

if GetModConfigData("PICKUP_IGNORE_FLOWERS", MOD_EQUIPMENT_CONTROL.MODNAME) then
    AddFilteredTag("flower")
end

if GetModConfigData("PICKUP_IGNORE_FERNS", MOD_EQUIPMENT_CONTROL.MODNAME) then
    AddFilteredPrefab("cave_fern")
    AddFilteredPrefab("stalker_fern")
end

if GetModConfigData("PICKUP_IGNORE_SUCCULENTS", MOD_EQUIPMENT_CONTROL.MODNAME) then
    AddFilteredPrefab("succulent_plant")
end

if GetModConfigData("PICKUP_IGNORE_MARSH_BUSH", MOD_EQUIPMENT_CONTROL.MODNAME) then
    AddFilteredPrefab("marsh_bush")
end

local function SavePickupFilter()
    local t = {}

    for prefab in pairs(PickupFilter) do
        t[#t + 1] = prefab
    end

    FileSystem:SaveFile(Filter_File, t)
end

local function IsFiltered(ent)
    for i = 1, #PickupFilter.tags do
        if ent:HasTag(PickupFilter.tags[i]) then
            return true
        end
    end

    return PickupFilter.prefabs[ent.prefab]
end

local function AddToFilter(ent)
    PickupFilter.prefabs[ent.prefab] = not IsFiltered(ent) or nil
    SavePickupFilter()
    return PickupFilter.prefabs[ent.prefab]
end

local function LoadPickupFilter()
    local t = FileSystem:LoadFile(Filter_File)
    for i = 1, #t do
        PickupFilter.prefabs[t[i]] = true
    end
end

local function GetPriority(ent)
    return ent.prefab == "blueprint" and PriotizedPickups[ent.name]
        or PriotizedPickups[ent.prefab] 
        or 0
end

local function GetModifiedEnts(self, exclude, tags)
    local x, y, z = self.inst.Transform:GetWorldPosition()
    local ents = TheSim:FindEntities(x, y, z, self.directwalking and 3 or 6, nil, exclude, tags)

    if PRIOTIZE_VALUABLE_ITEMS then
        local prio = {}
        for _, ent in pairs(ents) do
            prio[#prio + 1] =
            {
                ent = ent,
                priority = GetPriority(ent),
            }
        end

        table.sort(prio, function(a, b)
            return a.priority > b.priority
        end)

        ents = {}
        for i = 1, #prio do
            ents[#ents + 1] = prio[i].ent
        end
    end

    return ents
end

local function Init()
    local PlayerController = ThePlayer and ThePlayer.components.playercontroller

    if not PlayerController then
        return
    end

    if GetModConfigData("PICKUP_FILTER", MOD_EQUIPMENT_CONTROL.MODNAME) then
        LoadPickupFilter()
    end

    local function ValidateHaunt(target)
        return target:HasActionComponent("hauntable")
    end

    local function ValidateBugNet(target)
        return not target.replica.health:IsDead()
    end

    local function ValidateUnsaddler(target)
        return not target.replica.health:IsDead()
    end

    local function ValidateCorpseReviver(target, inst)
        --V2C: revivablecorpse is on clients as well
        return target.components.revivablecorpse:CanBeRevivedBy(inst)
    end

    local function GetPickupAction(self, target, tool)
        if target:HasTag("smolder") then
            return ACTIONS.SMOTHER
        elseif tool ~= nil then
            for k, v in pairs(TOOLACTIONS) do
                if target:HasTag(k.."_workable") then
                    if tool:HasTag(k.."_tool") then
                        return ACTIONS[k]
                    end
                    break
                end
            end
        end

        if target:HasTag("quagmireharvestabletree") and not target:HasTag("fire") then
            return ACTIONS.HARVEST_TREE
        elseif target:HasTag("trapsprung") then
            return ACTIONS.CHECKTRAP
        elseif target:HasTag("minesprung") and not target:HasTag("mine_not_reusable") then
            return ACTIONS.RESETMINE
        elseif target:HasTag("inactive") then
            return (not target:HasTag("wall") or self.inst:IsNear(target, 2.5)) and ACTIONS.ACTIVATE or nil
        elseif target.replica.inventoryitem ~= nil and
            target.replica.inventoryitem:CanBePickedUp() and
            not (target:HasTag("heavy") or target:HasTag("fire") or target:HasTag("catchable")) then
            return (self:HasItemSlots() or target.replica.equippable ~= nil) and ACTIONS.PICKUP or nil
        elseif target:HasTag("pickable") and not target:HasTag("fire") then
            return ACTIONS.PICK
        elseif target:HasTag("harvestable") then
            return ACTIONS.HARVEST
        elseif target:HasTag("readyforharvest") or
            (target:HasTag("notreadyforharvest") and target:HasTag("withered")) then
            return ACTIONS.HARVEST
        elseif target:HasTag("tapped_harvestable") and not target:HasTag("fire") then
            return ACTIONS.HARVEST
        elseif target:HasTag("dried") and not target:HasTag("burnt") then
            return ACTIONS.HARVEST
        elseif target:HasTag("donecooking") and not target:HasTag("burnt") then
            return ACTIONS.HARVEST
        elseif tool ~= nil and tool:HasTag("unsaddler") and target:HasTag("saddled") and (not target.replica.health or not target.replica.health:IsDead()) then
            return ACTIONS.UNSADDLE
        elseif tool ~= nil and tool:HasTag("brush") and target:HasTag("brushable") and (not target.replica.health or not target.replica.health:IsDead()) then
            return ACTIONS.BRUSH
        elseif self.inst.components.revivablecorpse ~= nil and target:HasTag("corpse") and ValidateCorpseReviver(target, self.inst) then
            return ACTIONS.REVIVE_CORPSE
        end
        --no action found
    end

    local TARGET_EXCLUDE_TAGS = { "FX", "NOCLICK", "DECOR", "INLIMBO" }
    local PICKUP_TARGET_EXCLUDE_TAGS = { "catchable", "mineactive", "intense" }
    local HAUNT_TARGET_EXCLUDE_TAGS = { "haunted", "catchable" }
    for i, v in ipairs(TARGET_EXCLUDE_TAGS) do
        table.insert(PICKUP_TARGET_EXCLUDE_TAGS, v)
        table.insert(HAUNT_TARGET_EXCLUDE_TAGS, v)
    end

    local CATCHABLE_TAGS = { "catchable" }
    local PINNED_TAGS = { "pinned" }
    local CORPSE_TAGS = { "corpse" }
    local PlayerControllerGetActionButtonAction = PlayerController.GetActionButtonAction
    function PlayerController:GetActionButtonAction(force_target)
        --Don't want to spam the action button before the server actually starts the buffered action
        --Also check if playercontroller is enabled
        --Also check if force_target is still valid
        if (not self.ismastersim and (self.remote_controls[CONTROL_ACTION] or 0) > 0) or
            not self:IsEnabled() or
            self:IsBusy() or
            (force_target ~= nil and (not force_target.entity:IsVisible() or force_target:HasTag("INLIMBO") or force_target:HasTag("NOCLICK"))) then
            --"DECOR" should never change, should be safe to skip that check
            return

        elseif self.actionbuttonoverride ~= nil then
            local buffaction, usedefault = self.actionbuttonoverride(self.inst, force_target)
            if not usedefault or buffaction ~= nil then
                return buffaction
            end

        elseif self.inst.replica.inventory:IsHeavyLifting()
            and not (self.inst.replica.rider ~= nil and self.inst.replica.rider:IsRiding()) then
            --hands are full!
            return

        elseif not self:IsDoingOrWorking() then
            local force_target_distsq = force_target ~= nil and self.inst:GetDistanceSqToInst(force_target) or nil

            if self.inst:HasTag("playerghost") then
                --haunt
                if force_target == nil then
                    local target = FindEntity(self.inst, self.directwalking and 3 or 6, ValidateHaunt, nil, HAUNT_TARGET_EXCLUDE_TAGS)
                    if CanEntitySeeTarget(self.inst, target) then
                        return BufferedAction(self.inst, target, ACTIONS.HAUNT)
                    end
                elseif force_target_distsq <= (self.directwalking and 9 or 36) and
                    not (force_target:HasTag("haunted") or force_target:HasTag("catchable")) and
                    ValidateHaunt(force_target) then
                    return BufferedAction(self.inst, force_target, ACTIONS.HAUNT)
                end
                return
            end

            local tool = self.inst.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)

            --bug catching (has to go before combat)
            if tool ~= nil and tool:HasTag(ACTIONS.NET.id.."_tool") then
                if force_target == nil then
                    local target = FindEntity(self.inst, 5, ValidateBugNet, { "_health", ACTIONS.NET.id.."_workable" }, TARGET_EXCLUDE_TAGS)
                    if CanEntitySeeTarget(self.inst, target) then
                        return BufferedAction(self.inst, target, ACTIONS.NET, tool)
                    end
                elseif force_target_distsq <= 25 and
                    force_target.replica.health ~= nil and
                    ValidateBugNet(force_target) and
                    force_target:HasTag(ACTIONS.NET.id.."_workable") then
                    return BufferedAction(self.inst, force_target, ACTIONS.NET, tool)
                end
            end

            --catching
            if self.inst:HasTag("cancatch") then
                if force_target == nil then
                    local target = FindEntity(self.inst, 10, nil, CATCHABLE_TAGS, TARGET_EXCLUDE_TAGS)
                    if CanEntitySeeTarget(self.inst, target) then
                        return BufferedAction(self.inst, target, ACTIONS.CATCH)
                    end
                elseif force_target_distsq <= 100 and
                    force_target:HasTag("catchable") then
                    return BufferedAction(self.inst, force_target, ACTIONS.CATCH)
                end
            end

            --unstick
            if force_target == nil then
                local target = FindEntity(self.inst, self.directwalking and 3 or 6, nil, PINNED_TAGS, TARGET_EXCLUDE_TAGS)
                if CanEntitySeeTarget(self.inst, target) then
                    return BufferedAction(self.inst, target, ACTIONS.UNPIN)
                end
            elseif force_target_distsq <= (self.directwalking and 9 or 36) and
                force_target:HasTag("pinned") then
                return BufferedAction(self.inst, force_target, ACTIONS.UNPIN)
            end

            --revive (only need to do this if i am also revivable)
            if self.inst.components.revivablecorpse ~= nil then
                if force_target == nil then
                    local target = FindEntity(self.inst, 3, ValidateCorpseReviver, CORPSE_TAGS, TARGET_EXCLUDE_TAGS)
                    if CanEntitySeeTarget(self.inst, target) then
                        return BufferedAction(self.inst, target, ACTIONS.REVIVE_CORPSE)
                    end
                elseif force_target_distsq <= 9
                    and force_target:HasTag("corpse")
                    and ValidateCorpseReviver(force_target, self.inst) then
                    return BufferedAction(self.inst, force_target, ACTIONS.REVIVE_CORPSE)
                end
            end

            --misc: pickup, tool work, smother
            if force_target == nil then
                local pickup_tags =
                {
                    "_inventoryitem",
                    "pickable",
                    "donecooking",
                    "readyforharvest",
                    "notreadyforharvest",
                    "harvestable",
                    "trapsprung",
                    "minesprung",
                    "dried",
                    "inactive",
                    "smolder",
                    "saddled",
                    "brushable",
                    "tapped_harvestable",
                }
                if tool ~= nil then
                    for k, v in pairs(TOOLACTIONS) do
                        if tool:HasTag(k.."_tool") then
                            table.insert(pickup_tags, k.."_workable")
                        end
                    end
                end
                if self.inst.components.revivablecorpse ~= nil then
                    table.insert(pickup_tags, "corpse")
                end
                local ents = GetModifiedEnts(self, PICKUP_TARGET_EXCLUDE_TAGS, pickup_tags)
                for i, v in ipairs(ents) do
                    if v ~= self.inst and v.entity:IsVisible() and CanEntitySeeTarget(self.inst, v) and not IsFiltered(v) then
                        local action = GetPickupAction(self, v, tool)
                        if action ~= nil then
                            return BufferedAction(self.inst, v, action, action ~= ACTIONS.SMOTHER and tool or nil)
                        end
                    end
                end
            elseif force_target_distsq <= (self.directwalking and 9 or 36) then
                local action = GetPickupAction(self, force_target, tool)
                if action ~= nil then
                    return BufferedAction(self.inst, force_target, action, action ~= ACTIONS.SMOTHER and tool or nil)
                end
            end
        end
    end

    print("FilterPickup init")
end

local function CanBePickedUp(ent)
    return ent
       and ent.replica.inventoryitem
       and ent.replica.inventoryitem:CanBePickedUp()
end

KeybindService:AddKey("PICKUP_FILTER", function()
    local ent = TheInput:GetWorldEntityUnderMouse()

    if CanBePickedUp(ent) then
        Say(
            string.format(
                AddToFilter(ent) and MOD_EQUIPMENT_CONTROL.STRINGS.PICKUP_FILTER.ADD
                or MOD_EQUIPMENT_CONTROL.STRINGS.PICKUP_FILTER.REMOVE,
                ent.name
            )
        )
    end
end)

return Init
