-- @description Создание цветных регионов
-- @version 2.5
-- @author Your Name
-- @about
--   Создает цветные регионы с помощью кнопок в горизонтальном ряду

local ctx = reaper.ImGui_CreateContext('Region Namer')
local flags = reaper.ImGui_WindowFlags_NoCollapse() | reaper.ImGui_WindowFlags_HorizontalScrollbar()
local text_color = 0x000000FF -- Черный цвет текста

-- Конвертация цвета в формат 0xRRGGBBAA
local function convert_color(r, g, b, a)
    return (math.floor(r*255) << 24) | 
           (math.floor(g*255) << 16) | 
           (math.floor(b*255) << 8) | 
           math.floor(a*255)
end

-- Предопределенные регионы
local regions = {
    {name = "Intro",     color = convert_color(0.6, 0.8, 0.6, 0.9)},
    {name = "Verse",     color = convert_color(0.9, 0.9, 0.6, 0.9)},
    {name = "Pause",     color = convert_color(0.3, 0.6, 0.7, 0.9)},
    {name = "Pre Chorus",color = convert_color(0.8, 0.9, 0.5, 0.7)},
    {name = "Chorus",    color = convert_color(0.9, 0.5, 0.5, 0.7)},
    {name = "Bridge",    color = convert_color(0.6, 0.9, 0.8, 0.7)},
    {name = "Drop",      color = convert_color(0.6, 0.8, 0.7, 0.7)},
    {name = "Outro",     color = convert_color(0.8, 0.9, 0.8, 0.7)},
    {name = "End",       color = convert_color(0.8, 0.8, 0.8, 0.7)},
}

-- Настройки кнопок
local button_width = 80   -- Фиксированная ширина кнопок
local button_height = 20   -- Фиксированная высота кнопок
local button_spacing = 5   -- Расстояние между кнопками

-- Создание региона
local function create_region(region)
    local start, fin = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if start < fin then
        reaper.Undo_BeginBlock()
        reaper.AddProjectMarker2(0, true, start, fin, region.name, -1, region.color)
        reaper.Undo_EndBlock("Создан регион: " .. region.name, -1)
        reaper.UpdateArrange()
    else
        reaper.ShowMessageBox("Сначала выделите диапазон времени!", "Ошибка", 0)
    end
end

-- Основной цикл
local function loop()
    local visible, open = reaper.ImGui_Begin(ctx, 'Region Namer', true, flags)
    if not visible then
        if open then reaper.ImGui_End(ctx) end
        return false
    end

    -- Закрытие по ESC
    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
        open = false
    end

    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), button_spacing, 0)
    
    -- Первая кнопка без SameLine
    local first = true
    
    for _, region in ipairs(regions) do
        if not first then
            reaper.ImGui_SameLine(ctx)
        else
            first = false
        end
        
        -- Рассчет цветов кнопки
        local r, g, b, a = reaper.ImGui_ColorConvertU32ToDouble4(region.color)
        local hover = {
            math.min(r * 1.1, 1.0),
            math.min(g * 1.1, 1.0),
            math.min(b * 1.1, 1.0),
            a
        }
        local active = {
            r * 0.8,
            g * 0.8,
            b * 0.8,
            a
        }

        -- Устанавливаем стили кнопки
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), region.color)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), reaper.ImGui_ColorConvertDouble4ToU32(table.unpack(hover)))
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), reaper.ImGui_ColorConvertDouble4ToU32(table.unpack(active)))
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), text_color)

        -- Создаем кнопку с фиксированным размером
        if reaper.ImGui_Button(ctx, region.name, button_width, button_height) then
            create_region(region)
        end
        reaper.ImGui_PopStyleColor(ctx, 4)
    end
    
    reaper.ImGui_PopStyleVar(ctx)

    reaper.ImGui_End(ctx)
    return open
end

-- Запуск
local function main()
    -- Устанавливаем начальный размер окна
    reaper.ImGui_SetNextWindowSize(ctx, 
        button_width * #regions + (button_spacing*(#regions-1)), 
        button_height + 20, 
        reaper.ImGui_Cond_FirstUseEver()
    )
    
    local function defer_loop()
        if loop() then
            reaper.defer(defer_loop)
        end
    end
    
    defer_loop()
end

main()