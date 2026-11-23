return function(options, schema)
    if options == nil then return {} end
    if type(options) ~= "table" then return nil, "Параметры должны быть таблицей" end
    for key, value in pairs(options) do
        local expected = schema[key]
        if not expected then return nil, "Неизвестный параметр" end
        if type(value) ~= expected then return nil, "Неверный тип параметра " .. key .. "; требуется " .. expected end
    end
    return options
end
