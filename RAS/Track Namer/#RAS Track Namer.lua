-- @description Track Namer
-- @version 1.5.4
-- @author RAS
-- @about
--   #RAS

local script_path = debug.getinfo(1, 'S').source:match('@?(.*[\\/])') or ''
local data_file = script_path .. "Track Data.txt"

local dim_factor = 0.3
local base_colors = {
    Prefix1 = {0.4, 0.0, 0.0, 1.0},
    Prefix2 = {0.0, 0.3, 0.6, 0.8},
    Suffix =  {0.8, 0.8, 0.3, 0.6},
    Ending =  {0.7, 0.4, 0.7, 0.8},
    Name =    {0.5, 0.5, 0.5, 1.0}
}

local categories = {"Prefix1", "Prefix2", "Name", "Suffix", "Ending"}
local track_data = {}
local selected_values = {}
local original_selected_values = {}
local ctx = nil
local last_selected_tracks = {}
local last_track_name = ""
local window_flags = reaper.ImGui_WindowFlags_NoCollapse()
local undo_flag = "Track Namer"
local enable_instant_apply = reaper.GetExtState("TrackNamer", "InstantApply") == "true" -- Загрузка состояния

local function has_value(tbl, val)
    if not tbl then return false end
    for _, v in ipairs(tbl) do
        if v == val then return true end
    end
    return false
end

local function get_parent_folder_name()
    local track = reaper.GetSelectedTrack(0, 0)
    if not track then return nil end
    local parent_track = reaper.GetParentTrack(track)
    if not parent_track then return nil end
    local _, name = reaper.GetTrackName(parent_track, "")
    return name
end

local function parse_color_groups(line)
    local color_groups = {}
    
    local color_part, remaining = line:match("^%s*{%s*([^}]+)}%s*(.*)$")
    local color = nil
    if color_part then
        color = {}
        for num in color_part:gmatch("[%d%.]+") do
            table.insert(color, math.min(tonumber(num), 1.0))
        end
        while #color < 4 do table.insert(color, 1.0) end
    else
        remaining = line
    end

    local folders_part, values_part = remaining:match("^%s*%(([^)]*)%)%s*(.*)$")
    local folders = {}
    
    if folders_part then
        for folder in folders_part:gmatch("([^,]+)") do
            table.insert(folders, folder:match("^%s*(.-)%s*$"))
        end
    else
        values_part = remaining
    end
    
    local values = {}
    for value in (values_part or ""):gmatch("([^,]+)") do
        local cleaned = value:match("^%s*(.-)%s*$")
        if cleaned ~= "" then table.insert(values, cleaned) end
    end
    
    if #values > 0 then
        table.insert(color_groups, {
            color = color,
            folders = folders,
            values = values
        })
    end
    
    return color_groups
end

local function load_data()
    local f = io.open(data_file, "r")
    if not f then 
        reaper.ShowMessageBox("Data file not found at:\n" .. data_file, "Error", 0)
        return 
    end
    
    local current_category = nil
    for line in f:lines() do
        line = line:match("^%s*(.-)%s*$")
        if line:sub(-1) == ":" then
            current_category = line:sub(1, -2)
            track_data[current_category] = {}
        elseif current_category and #line > 0 then
            local groups = parse_color_groups(line)
            for _, group in ipairs(groups) do
                if not group.color then
                    group.color = base_colors[current_category] or {1,1,1,1}
                end
                if #group.values > 0 then
                    table.insert(track_data[current_category], group)
                end
            end
        end
    end
    f:close()
end

local function reset_selections()
    for _, cat in ipairs(categories) do
        selected_values[cat] = ""
    end
end

local function parse_name_into_parts(name)
    local parts = {}
    local remaining_name = name
    
    for _, cat in ipairs(categories) do
        parts[cat] = ""
        for _, group in ipairs(track_data[cat] or {}) do
            for _, value in ipairs(group.values) do
                local pattern = value:gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
                local postfix = (#remaining_name > #pattern) and "%s" or "$"
                local start_pos = remaining_name:find("^"..pattern..postfix)
                if start_pos then
                    parts[cat] = value
                    remaining_name = remaining_name:sub(#value + 1)
                    break
                end
            end
            if parts[cat] ~= "" then break end
        end
        remaining_name = remaining_name:gsub("^%s*", "")
    end
    return parts
end

local function parse_track_name(name)
    reset_selections()
    local parts = parse_name_into_parts(name)
    for cat, value in pairs(parts) do
        selected_values[cat] = value
    end
end

local function check_selection_change()
    local current = {}
    for i = 0, reaper.CountSelectedTracks(0)-1 do
        current[i+1] = reaper.GetSelectedTrack(0, i)
    end

    local changed = false
    if #current ~= #last_selected_tracks then
        changed = true
    else
        for i, track in ipairs(current) do
            if track ~= last_selected_tracks[i] then
                changed = true
                break
            end
        end
    end

    if not changed and #current > 0 then
        local track = current[1]
        local _, name = reaper.GetTrackName(track, "")
        if name ~= last_track_name then
            changed = true
        end
    end

    if changed then
        last_selected_tracks = current
        if #current > 0 then
            local track = current[1]
            local _, name = reaper.GetTrackName(track, "")
            parse_track_name(name)
            last_track_name = name
            original_selected_values = {}
            for _, cat in ipairs(categories) do
                original_selected_values[cat] = selected_values[cat]
            end
        else
            reset_selections()
            last_track_name = ""
            original_selected_values = {}
        end
    end
end

local function rename_tracks(switch_to_next)    
    reaper.Undo_BeginBlock()
    
    for i = 0, reaper.CountSelectedTracks(0)-1 do
        local track = reaper.GetSelectedTrack(0, i)
        local _, old_name = reaper.GetTrackName(track, "")
        local old_parts = parse_name_into_parts(old_name)
        
        local new_parts = {}
        for _, cat in ipairs(categories) do
            if original_selected_values[cat] ~= selected_values[cat] then
                new_parts[cat] = selected_values[cat]
            else
                new_parts[cat] = old_parts[cat]
            end
        end
        
        local parts = {}
        for _, cat in ipairs(categories) do
            if new_parts[cat] and new_parts[cat] ~= "" then
                table.insert(parts, new_parts[cat])
            end
        end
        local new_name = table.concat(parts, " ")
        
        reaper.GetSetMediaTrackInfo_String(track, "P_NAME", new_name, true)
        
        if switch_to_next and i == reaper.CountSelectedTracks(0)-1 then
            local track_num = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
            local next_track = reaper.GetTrack(0, track_num)
            if next_track then
                reaper.SetOnlyTrackSelected(next_track)
                reaper.UpdateArrange()
            end
        end
    end
    
    reaper.Undo_EndBlock(undo_flag, -1)
end

local function create_gui()
    check_selection_change()
    
    reaper.ImGui_SetNextWindowSize(ctx, 500, 500, reaper.ImGui_Cond_FirstUseEver())
    local visible, open = reaper.ImGui_Begin(ctx, "Track Namer", true, window_flags)
    if not visible then
        if open then reaper.ImGui_End(ctx) end
        return open
    end

    reaper.ImGui_SetWindowFocus(ctx)
    
    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_W(), false) then
        local key_mods = reaper.ImGui_GetKeyMods(ctx)
        local switch_to_next = (key_mods & reaper.ImGui_Mod_Alt()) == 0
        rename_tracks(switch_to_next)
    end

    local button_width = (reaper.ImGui_GetContentRegionAvail(ctx) - (2 * reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing()))) / 7
    local parent_folder = get_parent_folder_name()

    for _, cat in ipairs(categories) do
        reaper.ImGui_Text(ctx, cat .. ":")
        reaper.ImGui_BeginGroup(ctx)
        
        local items_per_row = math.floor(reaper.ImGui_GetContentRegionAvail(ctx) / (button_width + reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing())))
        local item_counter = 0

        for _, group in ipairs(track_data[cat] or {}) do
            local col = group.color
            local is_active = true
            local category_has_matching_folder = false
            
            if has_value(group.folders, "ALL") then
                is_active = true
            else
                if parent_folder then
                    category_has_matching_folder = false
                    for _, g in ipairs(track_data[cat] or {}) do
                        if #g.folders > 0 and has_value(g.folders, parent_folder) then
                            category_has_matching_folder = true
                            break
                        end
                    end

                    if category_has_matching_folder then
                        is_active = has_value(group.folders, parent_folder)
                    else
                        is_active = (#group.folders == 0)
                    end
                else
                    is_active = (#group.folders == 0)
                end
            end

            -- New dimming condition
            if parent_folder and category_has_matching_folder and not is_active then
                col = {col[1]*dim_factor, col[2]*dim_factor, col[3]*dim_factor, col[4]}
            end

            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), reaper.ImGui_ColorConvertDouble4ToU32(col[1], col[2], col[3], col[4]))
            
            for _, value in ipairs(group.values) do
                if item_counter > 0 and item_counter % items_per_row ~= 0 then
                    reaper.ImGui_SameLine(ctx)
                end
                
                local is_selected = (selected_values[cat] == value)
                if is_selected then
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), reaper.ImGui_ColorConvertDouble4ToU32(1.0, 0.0, 0.0, 0.8))
                end
                
                reaper.ImGui_PushItemWidth(ctx, button_width)
                if reaper.ImGui_Button(ctx, value) then
                    selected_values[cat] = (selected_values[cat] == value) and "" or value
                    -- Проверка активации мгновенного применения
                    if enable_instant_apply then
                        rename_tracks(false)
                    end
                end
                reaper.ImGui_PopItemWidth(ctx)
                
                if is_selected then
                    reaper.ImGui_PopStyleColor(ctx)
                end
                
                item_counter = item_counter + 1
            end
            reaper.ImGui_PopStyleColor(ctx)
        end
        
        reaper.ImGui_EndGroup(ctx)
        reaper.ImGui_NewLine(ctx)
    end

    reaper.ImGui_Separator(ctx)
    if reaper.ImGui_Button(ctx, "Apply Next (W)") then rename_tracks(true) end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Apply (Alt+W)") then rename_tracks(false) end
    reaper.ImGui_SameLine(ctx)
    
    -- Модифицированный чекбокс с сохранением состояния
    local prev_state = enable_instant_apply
    _, enable_instant_apply = reaper.ImGui_Checkbox(ctx, "Instant", enable_instant_apply)
    if enable_instant_apply ~= prev_state then
        reaper.SetExtState("TrackNamer", "InstantApply", tostring(enable_instant_apply), true)
    end

    reaper.ImGui_End(ctx)
    return open
end

local function main()
    if not ctx then
        ctx = reaper.ImGui_CreateContext('Track Namer')
        load_data()
        reset_selections()
        check_selection_change()
    end
    
    local open = create_gui()
    if open then
        reaper.defer(main)
    else
        if ctx and reaper.ImGui_GetCurrentContext() == ctx then
            reaper.ImGui_DestroyContext(ctx)
        end
        ctx = nil
    end
end

reaper.defer(main)
