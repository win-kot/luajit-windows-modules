-- Internal Windows argument quoting core. Callers retain their input policies.
return function(text)
    if text == "" then return '""' end
    if not text:find('[%s"]') then return text end
    -- Copy ordinary spans together; process each slash run only once.
    local parts, pos, len = {'"'}, 1, #text
    while pos <= len do
        local special = text:find('[\\"]', pos)
        if not special then
            parts[#parts + 1] = text:sub(pos)
            break
        end
        if special > pos then parts[#parts + 1] = text:sub(pos, special - 1) end
        if text:byte(special) == 34 then
            parts[#parts + 1] = '\\"'
            pos = special + 1
        else
            local after = special + 1
            while after <= len and text:byte(after) == 92 do after = after + 1 end
            local count = after - special
            if after > len or text:byte(after) == 34 then
                parts[#parts + 1] = string.rep('\\', count * 2)
            else
                parts[#parts + 1] = text:sub(special, after - 1)
            end
            pos = after
        end
    end
    parts[#parts + 1] = '"'
    return table.concat(parts)
end

