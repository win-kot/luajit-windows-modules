-- Formatting only: independent of the Framework's Windows and text helpers.
local ffi = require('ffi')
ffi.cdef[[
unsigned long __stdcall GetLastError(void);
unsigned long __stdcall fe_FormatMessageW(unsigned long, const void *, unsigned long, unsigned long, uint16_t *, unsigned long, void *) __asm__("FormatMessageW");
int __stdcall fe_WideCharToMultiByte(unsigned int, unsigned long, const uint16_t *, int, char *, int, const char *, int *) __asm__("WideCharToMultiByte");
]]
local k = ffi.load('kernel32')
local M = {}

-- Lua permits any error value, including nil and objects whose __tostring fails.
function M.Message(value)
    local ok, message = pcall(tostring, value)
    if not ok or type(message) ~= 'string' or message == '' then
        return 'Не удалось получить текст ошибки'
    end
    return message
end

function M.Callback(context, value)
    return nil, context .. ': ' .. M.Message(value), 31
end
local common = {
    [2]='Файл не найден', [3]='Путь не найден', [5]='Отказано в доступе',
    [17]='Исходный и конечный пути находятся на разных дисках',
    [32]='Объект используется другим процессом', [33]='Область файла заблокирована',
    [80]='Файл уже существует', [87]='Недопустимый параметр',
    [112]='Недостаточно места на диске', [123]='Недопустимое имя объекта',
    [126]='Модуль не найден', [145]='Папка не пуста', [183]='Объект уже существует',
    [203]='Переменная среды не найдена', [206]='Слишком длинное имя',
    [267]='Указан недопустимый каталог', [1113]='Недопустимая последовательность символов',
    [12002]='Истекло время ожидания HTTP', [12005]='Недопустимый URL',
    [12007]='Не удалось разрешить имя сервера', [12029]='Не удалось подключиться к серверу',
}

local function systemMessage(code, language)
    local wide = ffi.new('uint16_t[1024]')
    local n = k.fe_FormatMessageW(0x1200, nil, code, language, wide, 1024, nil)
    if n == 0 then return nil end
    local bytes = ffi.new('char[4096]')
    local size = k.fe_WideCharToMultiByte(65001, 128, wide, n, bytes, 4096, nil, nil)
    if size == 0 then return nil end
    return (ffi.string(bytes, size):gsub('%s+$', ''))
end

function M.Win32(operation, code, context)
    code = tonumber(code == nil and k.GetLastError() or code)
    local reason = common[code]
    if code and code ~= 0 and not reason then
        reason = systemMessage(code, 0x0419) or systemMessage(code, 0)
    end
    local message = 'Не удалось выполнить ' .. operation
    if context then message = message .. ' [' .. context .. ']' end
    if code and code ~= 0 then message = message .. (' (Win32: %d)'):format(code) end
    if reason then message = message .. ': ' .. reason end
    return nil, message, code ~= 0 and code or nil
end

function M.Status(operation, subsystem, code, context)
    local message = 'Не удалось выполнить ' .. operation
    if context then message = message .. ' [' .. context .. ']' end
    return nil, message .. (' (%s: %s)'):format(subsystem, tostring(code)), code
end

function M.Context(context, message, code)
    return nil, context .. ': ' .. message, code
end

function M.MissingPath(code) return code == 2 or code == 3 end
function M.AlreadyExists(code) return code == 80 or code == 183 end
return M
