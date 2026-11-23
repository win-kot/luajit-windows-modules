local _source = debug.getinfo(1, 'S').source
local _dir = _source:sub(2):match('^(.*)[/\\]') or '.'
local Bootstrap = loadfile(_dir .. '/_bootstrap.lua') or loadfile(_dir .. '/../_bootstrap.lua')
assert(Bootstrap, 'Keep this example with the FrameWork directory and the included _bootstrap.lua file')
Bootstrap()

local s = require('str')
assert(s.Len('Привет') == 6)
print(s.Upper('Привет, мир!'))
for i, part in ipairs(s.Split('один::два::три', '::', true, true)) do
  print(i, part)
end
print(assert(s.Normalize('e' .. s.Char(0x301), 'NFC')))

-- str works with Unicode codepoints; string.* keeps native byte semantics.
local text = 'Привет'
assert(#text == 12 and s.Len(text) == 6)
assert(s.Sub(text, 2, 4) == 'рив')
assert(s.CodePoint('ж') == 1078)
assert(string.rep('ж', 3, '|') == 'ж|ж|ж')
local left, right = s.Divide('ключ=значение', '=')
assert(left == 'ключ' and right == 'значение')
assert(s.Trim(s.Char(0xA0) .. '  Привет  ') == 'Привет')
-- Literal search returns codepoint indices.
local first, last = s.LFind('АБ日本', '日本')
assert(first == 3 and last == 4)

-- Reverse literal search also returns Unicode scalar positions.
local reverse_text = 'АБАБ'
local reverse_first, reverse_last = s.RFind(reverse_text, 'АБ')
assert(reverse_first == 3 and reverse_last == 4)
reverse_first, reverse_last = s.RFind(reverse_text, 'АБ', -3)
assert(reverse_first == 1 and reverse_last == 2)
-- Overlapping matches remain eligible.
assert(s.RFind('ааа', 'аа') == 2)

-- Lua patterns and their position captures use byte indices.
local key, value = string.match('ключ=значение', '^([^=]*)=(.*)$')
assert(key == 'ключ' and value == 'значение')
local byte_first, byte_last = string.find('АБ日本', '日本', 1, true)
assert(byte_first == 5 and byte_last == 10)
local parts = {}
for part in string.gmatch('один,два', '[^,]+') do
  parts[#parts + 1] = part
end
assert(#parts == 2 and parts[2] == 'два')

-- All four normalization forms use one entry point.
local decomposed = 'e' .. s.Char(0x301)
assert(s.Normalize(decomposed) == 'é') -- NFC by default
assert(s.Normalize('é', 'NFD') == decomposed)
assert(s.Normalize('ＡＢ', 'NFKC') == 'AB')
assert(s.Normalize('ＡＢ', 'NFKD') == 'AB')

assert(s.CharAt('АБ日本', -1) == '本')
assert(s.RangeRemove('АБ日本', 2, 3) == 'А本')
assert(s.RangeReplace('АБ日本', 2, 3, 'X') == 'АX本')
assert(s.Center('Я', 6, 'аб') == 'абЯаба')
assert(table.concat(s.LinesSplit('А\r\nБ\n'), '|') == 'А|Б')


-- Unicode comparisons and searches return positions in the original string.
assert(s.Equals("Σ", "ς", false))
assert(s.Equals("Straße", "STRASSE", false))
assert(not s.Equals("A", "a"))
local a, b = s.LFind("xßz", "SS", nil, false)
assert(a == 2 and b == 2)
assert(not s.Contains("ß", "s", false))
assert(s.RFind("АБаб", "АБ", nil, false) == 3)
local replaced, count = s.Replace("Straße STRASSE", "strasse", "X", nil, false)
assert(replaced == "X X" and count == 2)
assert(s.Count("ßSS", "ss", false) == 2)
local fields = s.Split("a::::b::", "::", true, true)
assert(#fields == 4 and fields[2] == "" and fields[4] == "")
assert(#s.Split("a,b;c", ",;") == 3)
print("str: PASS")
