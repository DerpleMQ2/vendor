local mq             = require('mq')
local ImGui          = require('ImGui')
local Icons          = require('mq.Icons')

local vendorInv      = require('vendor_inv')
local actors         = require 'actors'
local animItems      = mq.FindTextureAnimation("A_DragItem")

local openGUI        = true
local shouldDrawGUI  = false

local terminate      = false

local sourceIndex    = 1
local sellAllJunk    = false
local vendItem       = nil
local showHidden     = false

local settings_file  = mq.configDir .. "/vendor.lua"
local custom_sources = mq.configDir .. "/vendor_sources.lua"

local settings       = {}

local Output         = function(msg, ...)
    local formatted = msg
    if ... then
        formatted = string.format(msg, ...)
    end
    printf('\aw[' .. mq.TLO.Time() .. '] [\aoDerple\'s Vendor Helper\aw] ::\a-t %s', formatted)
end

function Tooltip(desc)
    ImGui.SameLine()
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.PushTextWrapPos(ImGui.GetFontSize() * 25.0)
        ImGui.Text(desc)
        ImGui.PopTextWrapPos()
        ImGui.EndTooltip()
    end
end

local function SaveSettings()
    mq.pickle(settings_file, settings)
    actors.send({ from = mq.TLO.Me.DisplayName(), script = "DerpleVend", event = "SaveSettings", })
end

local function LoadSettings()
    local config, err = loadfile(settings_file)
    if err or not config then
        Output("\ayNo valid configuration found. Creating a new one: %s", settings_file)
        settings = {}
        SaveSettings()
    else
        settings = config()
    end

    settings.Junk = settings.Junk or {}
    settings.Hide = settings.Hide or {}

    local vendorSources = {}
    local config, err = loadfile(custom_sources)
    if not err and config then
        vendorSources = config()
    end

    vendorInv = vendorInv:new(vendorSources)
end

local function sellItem(item)
    if not mq.TLO.Window("MerchantWnd").Open() then
        return
    end

    local tabPage = mq.TLO.Window("MerchantWnd").Child("MW_MerchantSubWindows")
    if tabPage.CurrentTab.Name() ~= "MW_PurchasePage" then
        tabPage.SetCurrentTab(1)
        return
    end

    if item and item.Item then
        Output("\aySelling item: \at%s\ay in Slot\aw(\am%d\aw)\ay, Slot2\aw(\am%d\aw)", item.Item.Name(), item.Item.ItemSlot(), item.Item.ItemSlot2())

        local retries = 15
        repeat
            mq.cmd("/itemnotify in " ..
                vendorInv.toPack(item.Item.ItemSlot()) ..
                " " .. vendorInv.toBagSlot(item["Item"].ItemSlot2()) .. " leftmouseup")
            mq.delay(500)
            retries = retries - 1
            if retries < 0 then return end
            if not openGUI then return end
        until mq.TLO.Window("MerchantWnd").Child("MW_Sell_Button")() == "TRUE" and mq.TLO.Window("MerchantWnd").Child("MW_Sell_Button").Enabled()

        retries = 15
        repeat
            mq.delay(500)
            if mq.TLO.Window("MerchantWnd").Child("MW_Sell_Button").Enabled() then
                Output("Pushign sell")
                mq.cmd("/shift /notify MerchantWnd MW_Sell_Button leftmouseup")
            end
            retries = retries - 1
            if retries < 0 then return end
            if not openGUI then return end
        until mq.TLO.Window("MerchantWnd").Child("MW_Sell_Button")() ~= "TRUE"

        Output("\agDone selling...")
    else
        vendorInv:resetState()
    end
end

-- default false
local function IsHidden(itemName)
    local itemStartString = itemName:sub(1, 1)
    return settings.Hide[itemStartString] and settings.Hide[itemStartString][itemName] == true
end

-- default false
local function IsJunk(itemName)
    local itemStartString = itemName:sub(1, 1)
    return settings.Junk[itemStartString] and settings.Junk[itemStartString][itemName] == true
end

local function renderItems()
    if ImGui.BeginTable("BagItemList", 5, bit32.bor(ImGuiTableFlags.Resizable, ImGuiTableFlags.Borders)) then
        ImGui.PushStyleColor(ImGuiCol.Text, 0.8, 0, 1.0, 1)
        ImGui.TableSetupColumn('Icon', bit32.bor(ImGuiTableColumnFlags.NoSort, ImGuiTableColumnFlags.WidthFixed), 20.0)
        ImGui.TableSetupColumn('Item',
            bit32.bor(ImGuiTableColumnFlags.NoSort, ImGuiTableColumnFlags.PreferSortDescending,
                ImGuiTableColumnFlags.WidthStretch),
            150.0)
        ImGui.TableSetupColumn('Junk', bit32.bor(ImGuiTableColumnFlags.NoSort, ImGuiTableColumnFlags.WidthFixed), 20.0)
        ImGui.TableSetupColumn('Sell', bit32.bor(ImGuiTableColumnFlags.NoSort, ImGuiTableColumnFlags.WidthFixed), 20.0)
        ImGui.TableSetupColumn('Hide', bit32.bor(ImGuiTableColumnFlags.NoSort, ImGuiTableColumnFlags.WidthFixed), 20.0)
        ImGui.PopStyleColor()
        ImGui.TableHeadersRow()

        for idx, item in ipairs(vendorInv.items) do
            local itemStartString = item.Item.Name():sub(1, 1)
            settings.Junk[itemStartString] = settings.Junk[itemStartString] or {}
            settings.Hide[itemStartString] = settings.Hide[itemStartString] or {}

            if not IsHidden(item.Item.Name()) or showHidden then
                ImGui.PushID("#_itm_" .. tostring(idx))
                local currentItem = item.Item
                ImGui.TableNextColumn()
                animItems:SetTextureCell((tonumber(currentItem.Icon()) or 500) - 500)
                ImGui.DrawTextureAnimation(animItems, 20, 20)
                ImGui.TableNextColumn()
                if ImGui.Selectable(currentItem.Name(), false, 0) then
                    currentItem.Inspect()
                end
                ImGui.TableNextColumn()
                if IsJunk(item.Item.Name()) then
                    ImGui.PushStyleColor(ImGuiCol.Text, 0.02, 0.8, 0.02, 1.0)
                else
                    ImGui.PushStyleColor(ImGuiCol.Text, 0.8, 0.02, 0.02, 1.0)
                end
                ImGui.PushID("#_btn_jnk" .. tostring(idx))
                if ImGui.Selectable(Icons.FA_TRASH_O) then
                    settings.Junk[itemStartString][item.Item.Name()] = not IsJunk(item.Item.Name())
                    Output("\awToggled %s\aw for item: \at%s", IsJunk(item.Item.Name()) and "\arJunk" or "\agNot-Junk", item.Item.Name())
                    SaveSettings()
                end
                ImGui.PopID()
                ImGui.PopStyleColor()
                ImGui.TableNextColumn()
                if ImGui.Selectable(Icons.MD_MONETIZATION_ON) then
                    vendItem = item
                end
                ImGui.TableNextColumn()
                if not IsHidden(item.Item.Name()) then
                    ImGui.PushStyleColor(ImGuiCol.Text, 0.02, 0.8, 0.02, 1.0)
                else
                    ImGui.PushStyleColor(ImGuiCol.Text, 0.8, 0.02, 0.02, 1.0)
                end
                ImGui.PushID("#_btn_hide" .. tostring(idx))
                if ImGui.Selectable(IsHidden(item.Item.Name()) and Icons.FA_EYE or Icons.FA_EYE_SLASH) then
                    settings.Hide[itemStartString][item.Item.Name()] = not IsHidden(item.Item.Name())
                    Output("\awToggled %s\aw for item: \at%s", IsHidden(item.Item.Name()) and "\arHide" or "\agShow", item.Item.Name())
                    SaveSettings()
                end
                ImGui.PopID()
                ImGui.PopStyleColor()
                ImGui.PopID()
            end
        end

        ImGui.EndTable()
    end
end
local openLastFrame = false
local function vendorGUI()
    if mq.TLO.MacroQuest.GameState() ~= "INGAME" then return end

    local merchantWnd = mq.TLO.Window("MerchantWnd")
    if openGUI and merchantWnd.Open() then
        if not openLastFrame then
            vendorInv:createContainerInventory()
            vendorInv:getItems(sourceIndex)
        end

        openLastFrame = true
        ImGui.SetNextWindowPos(merchantWnd.X() + merchantWnd.Width(), merchantWnd.Y())
        ImGui.SetNextWindowSize(400, merchantWnd.Height())

        openGUI, shouldDrawGUI = ImGui.Begin('DerpleVend', openGUI,
            bit32.bor(ImGuiWindowFlags.NoResize, ImGuiWindowFlags.NoDecoration, ImGuiWindowFlags.NoCollapse, ImGuiWindowFlags.NoScrollWithMouse))

        ImGui.PushStyleColor(ImGuiCol.Text, 1, 1, 1, 1)
        local pressed

        if shouldDrawGUI then
            local disabled = false
            if vendItem ~= nil or sellAllJunk then
                ImGui.BeginDisabled()
                disabled = true
            end

            ImGui.Text("Item Filters: ")
            ImGui.SameLine()
            sourceIndex, pressed = ImGui.Combo("##Select Bag", sourceIndex, function(idx) return vendorInv.sendSources[idx].name end, #vendorInv.sendSources)
            if pressed then
                vendorInv:getItems(sourceIndex)
            end

            ImGui.Text(string.format("Filtered Items (%d):", #vendorInv.items or 0))

            ImGui.SameLine()

            if ImGui.SmallButton(Icons.MD_REFRESH) then
                vendorInv:createContainerInventory()
                vendorInv:getItems(sourceIndex)
            end

            ImGui.SameLine()

            if ImGui.SmallButton("Sell Junk") then
                sellAllJunk = true
            end
            Tooltip("Sell all junk items")

            ImGui.SameLine()

            if ImGui.SmallButton(showHidden and Icons.FA_EYE or Icons.FA_EYE_SLASH) then
                showHidden = not showHidden
            end
            Tooltip("Toggle showing hidden items")

            ImGui.NewLine()
            ImGui.Separator()

            ImGui.BeginChild("##VendorItems", -1, -1, ImGuiChildFlags.None, ImGuiWindowFlags.AlwaysVerticalScrollbar)
            renderItems()
            ImGui.EndChild()

            if disabled then
                ImGui.EndDisabled()
            end
        end

        ImGui.PopStyleColor()
        ImGui.End()
    else
        openLastFrame = false
    end
end

mq.imgui.init('vendorGUI', vendorGUI)

mq.bind("/vendor", function()
    openGUI = not openGUI
end
)

LoadSettings()

vendorInv:createContainerInventory()
vendorInv:getItems(sourceIndex)

Output("\aw>>> \ayDerple's Vendor tool loaded! UI will auto show when you open a Merchant Window. Use \at/vendor\ay to toggle the UI!")

-- Global Messaging callback
---@diagnostic disable-next-line: unused-local
local script_actor = actors.register(function(message)
    local msg = message()

    if msg["from"] == mq.TLO.Me.DisplayName() then
        return
    end
    if msg["script"] ~= "DerpleVend" then
        return
    end

    ---@diagnostic disable-next-line: redundant-parameter
    Output("\ayGot Event from(\am%s\ay) event(\at%s\ay)", msg["from"], msg["event"])

    if msg["event"] == "SaveSettings" then
        LoadSettings()
    end
end)

while not terminate do
    if mq.TLO.MacroQuest.GameState() ~= "INGAME" then return end

    if vendItem ~= nil then
        sellItem(vendItem)
        vendItem = nil
        mq.delay(50)
        Output("\amRefreshing inv...")
        vendorInv:createContainerInventory()
        vendorInv:getItems(sourceIndex)
    end

    if sellAllJunk then
        local itemsToSell = vendorInv.items
        for _, item in ipairs(itemsToSell) do
            if IsJunk(item.Item.Name()) then
                sellItem(item)
                mq.delay(50)
                vendorInv:getItems(sourceIndex)
            end

            if not openGUI then return end
        end

        Output("\amRefreshing inv...")
        vendorInv:createContainerInventory()
        vendorInv:getItems(sourceIndex)
        sellAllJunk = false
    end

    mq.doevents()
    mq.delay(400)
end
