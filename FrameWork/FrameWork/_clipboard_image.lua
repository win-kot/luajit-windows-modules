local ffi = require("ffi")
local win = require("_win_extension")
local user = ffi.load("user32")
local kernel = win.kernel

ffi.cdef[[
uint32_t __stdcall RegisterClipboardFormatW(const uint16_t *);
typedef struct __attribute__((packed)) {
    uint16_t type;
    uint32_t size, reserved, offset;
} fw_clipboard_bmp_file_header;
]]

local CF_DIB, CF_DIBV5 = 8, 17
local GMEM_MOVEABLE_ZEROINIT = 0x42
local PNG_NAME = assert(win.ToWide("PNG"))
local PNG_SIGNATURE = "\137PNG\r\n\26\n"
local pngFormat

local function registerPng()
    if pngFormat then return pngFormat end
    local id = user.RegisterClipboardFormatW(PNG_NAME)
    if id == 0 then return win.Error("RegisterClipboardFormatW(PNG)") end
    pngFormat = tonumber(id)
    return pngFormat
end

local function word(bytes, index)
    local a, b = bytes:byte(index, index + 1)
    return a + b * 256
end

local function dword(bytes, index)
    return word(bytes, index) + word(bytes, index + 2) * 65536
end

local function packedDibOffset(bytes)
    if #bytes < 12 then return nil end
    local header = dword(bytes, 1)
    if #bytes < header then return nil end
    local width, height, planes, bits, compression, palette, paletteEntry
    if header == 12 then -- BITMAPCOREHEADER
        width, height = word(bytes, 5), word(bytes, 7)
        planes, bits = word(bytes, 9), word(bytes, 11)
        compression, palette, paletteEntry = 0, 0, 3
    elseif header == 40 or header == 52 or header == 56 or header == 108 or header == 124 then
        width, height = dword(bytes, 5), dword(bytes, 9)
        if width >= 0x80000000 then return nil end
        if height >= 0x80000000 then height = 4294967296 - height end
        planes, bits = word(bytes, 13), word(bytes, 15)
        compression, palette, paletteEntry = dword(bytes, 17), dword(bytes, 33), 4
    else
        return nil
    end
    if planes ~= 1 or width == 0 or height == 0 then return nil end
    if bits ~= 1 and bits ~= 4 and bits ~= 8 and bits ~= 16 and bits ~= 24 and bits ~= 32 then return nil end
    if compression ~= 0 and (compression ~= 3 or (bits ~= 16 and bits ~= 32)) then return nil end
    if bits <= 8 then
        if palette > 2 ^ bits then return nil end
        if palette == 0 then palette = 2 ^ bits end
    end
    local offset = header + palette * paletteEntry
    if header == 40 and compression == 3 then offset = offset + 12 end
    local pixelEnd = offset + math.ceil(width * bits / 32) * 4 * height
    if pixelEnd > #bytes then return nil end
    if header == 124 then
        local colorSpace = dword(bytes, 57)
        if colorSpace == 0x4C494E4B then return nil end -- PROFILE_LINKED
        if colorSpace == 0x4D424544 then -- PROFILE_EMBEDDED
            local profileStart, profileSize = dword(bytes, 113), dword(bytes, 117)
            if profileStart < pixelEnd or profileSize == 0 or profileStart + profileSize > #bytes then return nil end
        end
    end
    return offset
end

local function bmpFromDib(bytes)
    local offset = packedDibOffset(bytes)
    if not offset then return win.Error("Invalid or unsupported packed clipboard DIB", 13) end
    local header = ffi.new("fw_clipboard_bmp_file_header[1]")
    local headerSize = ffi.sizeof(header)
    header[0].type, header[0].size, header[0].offset = 0x4D42, headerSize + #bytes, headerSize + offset
    return ffi.string(header, headerSize) .. bytes
end

local function allocate(bytes)
    local memory = kernel.GlobalAlloc(GMEM_MOVEABLE_ZEROINIT, #bytes)
    if memory == nil then return win.Error("GlobalAlloc(clipboard image)") end
    local ptr = kernel.GlobalLock(memory)
    if ptr == nil then
        local code = kernel.GetLastError()
        kernel.GlobalFree(memory)
        return win.Error("GlobalLock(clipboard image)", code)
    end
    ffi.copy(ptr, bytes, #bytes)
    kernel.GlobalUnlock(memory)
    return memory
end

local function copyMemory(memory)
    local size = tonumber(kernel.GlobalSize(memory))
    if size == 0 or size >= 0x7FFFFF00 then return win.Error("Invalid clipboard image size", 13) end
    local ptr = kernel.GlobalLock(memory)
    if ptr == nil then return win.Error("GlobalLock(clipboard image)") end
    local called, bytes = pcall(ffi.string, ptr, size)
    kernel.GlobalUnlock(memory)
    if not called then error(bytes, 0) end
    return bytes
end

return function(clipboard, openClipboard)
    function clipboard.ImageExists()
        if user.IsClipboardFormatAvailable(CF_DIBV5) ~= 0 or user.IsClipboardFormatAvailable(CF_DIB) ~= 0 then
            return true
        end
        local png, err, code = registerPng()
        if not png then return nil, err, code end
        return user.IsClipboardFormatAvailable(png) ~= 0
    end

    function clipboard.ImageGet()
        local png, err, code = registerPng()
        if not png then return nil, err, code end
        local opened
        opened, err, code = openClipboard()
        if not opened then return nil, err, code end
        local called, bytes, format, status = pcall(function()
            local failed
            for _, id in ipairs({png, CF_DIBV5, CF_DIB}) do
                if user.IsClipboardFormatAvailable(id) ~= 0 then
                    local memory = user.GetClipboardData(id)
                    if memory ~= nil then
                        local payload, message, result = copyMemory(memory)
                        if not payload then return nil, message, result end
                        return payload, id
                    end
                    failed = tonumber(kernel.GetLastError())
                end
            end
            if failed then return win.Error("GetClipboardData(image)", failed == 0 and 13 or failed) end
            return nil
        end)
        local closed = user.CloseClipboard()
        if not called then error(bytes, 0) end
        if closed == 0 then return win.Error("CloseClipboard") end
        if not bytes then return nil, format, status end
        if format ~= png then
            bytes, err, code = bmpFromDib(bytes)
            if not bytes then return nil, err, code end
        elseif bytes:sub(1, #PNG_SIGNATURE) ~= PNG_SIGNATURE then
            return win.Error("Invalid clipboard PNG signature", 13)
        end
        return require("image").FromBytes(bytes)
    end

    function clipboard.ImageSet(object)
        local pngFormatId, err, code = registerPng()
        if not pngFormatId then return nil, err, code end
        local image = require("image")
        local png, bmp
        png, err, code = image.Encode(object, "png")
        if not png then return nil, err, code end
        bmp, err, code = image.Encode(object, "bmp")
        if not bmp then return nil, err, code end
        local dib = bmp:sub(15)
        local offset = packedDibOffset(dib)
        if not offset or offset + 14 ~= dword(bmp, 11) then return win.Error("Invalid encoded clipboard DIB", 13) end

        local pngMemory, dibMemory
        pngMemory, err, code = allocate(png)
        if not pngMemory then return nil, err, code end
        dibMemory, err, code = allocate(dib)
        if not dibMemory then
            kernel.GlobalFree(pngMemory)
            return nil, err, code
        end
        local opened
        opened, err, code = openClipboard()
        if opened then
            local operation
            if user.EmptyClipboard() == 0 then
                operation = "EmptyClipboard"
            elseif user.SetClipboardData(pngFormatId, pngMemory) == nil then
                operation = "SetClipboardData(PNG)"
            else
                pngMemory = nil -- ownership transferred to Windows
                if user.SetClipboardData(CF_DIB, dibMemory) == nil then operation = "SetClipboardData(CF_DIB)"
                else dibMemory = nil end
            end
            local failed = operation and tonumber(kernel.GetLastError())
            if user.CloseClipboard() == 0 and not operation then
                operation, failed = "CloseClipboard", tonumber(kernel.GetLastError())
            end
            if operation then
                local ignored
                ignored, err, code = win.Error(operation, failed == 0 and 31 or failed)
            end
        end
        if pngMemory ~= nil then kernel.GlobalFree(pngMemory) end
        if dibMemory ~= nil then kernel.GlobalFree(dibMemory) end
        if err then return nil, err, code end
        return true
    end
end
