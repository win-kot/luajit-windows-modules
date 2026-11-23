local ffi = require("ffi")
local fs = require("fs")
local mouse = require("mouse")
local win = require("_win_extension")
local user = ffi.load("user32")
local gdi = ffi.load("gdi32")
local screen = {}

ffi.cdef[[
typedef struct __attribute__((packed)) {
    uint16_t type;
    uint32_t size;
    uint16_t reserved1, reserved2;
    uint32_t offset;
} fw_screen_bmp_header;
typedef struct {
    uint32_t size;
    int32_t width, height;
    uint16_t planes, bits;
    uint32_t compression, imageSize;
    int32_t xPixelsPerMeter, yPixelsPerMeter;
    uint32_t colorsUsed, colorsImportant;
} fw_screen_dib_header;
void *__stdcall fw_screen_SetThreadDpiAwarenessContext(void *) __asm__("SetThreadDpiAwarenessContext");
void *__stdcall fw_screen_GetDC(void *) __asm__("GetDC");
int __stdcall fw_screen_ReleaseDC(void *, void *) __asm__("ReleaseDC");
void *__stdcall fw_screen_CreateCompatibleDC(void *) __asm__("CreateCompatibleDC");
int __stdcall fw_screen_DeleteDC(void *) __asm__("DeleteDC");
void *__stdcall fw_screen_CreateDIBSection(void *, const fw_screen_dib_header *, uint32_t,
    void **, void *, uint32_t) __asm__("CreateDIBSection");
void *__stdcall fw_screen_SelectObject(void *, void *) __asm__("SelectObject");
int __stdcall fw_screen_DeleteObject(void *) __asm__("DeleteObject");
int __stdcall fw_screen_BitBlt(void *, int, int, int, int, void *, int, int, uint32_t) __asm__("BitBlt");
int __stdcall fw_screen_GdiFlush(void) __asm__("GdiFlush");
]]

local function readRegion(read, x, y, width, height)
    local bounds = mouse.VirtualScreenGet()
    if bounds.width <= 0 or bounds.height <= 0 then return win.Error("Desktop is unavailable", 21) end
    if x == nil then x, y, width, height = bounds.x, bounds.y, bounds.width, bounds.height end
    if x < bounds.x or y < bounds.y or x + width > bounds.x + bounds.width
        or y + height > bounds.y + bounds.height then
        return win.Error("Capture region lies outside the virtual desktop", 87)
    end

    local dib = ffi.new("fw_screen_dib_header[1]")
    local stride = math.ceil(width * 3 / 4) * 4
    local imageSize = stride * height
    local offset = ffi.sizeof("fw_screen_bmp_header") + ffi.sizeof(dib)
    if imageSize + offset >= 0x7FFFFF00 then return win.Error("Capture region is too large", 87) end
    dib[0].size, dib[0].width, dib[0].height = ffi.sizeof(dib), width, -height
    dib[0].planes, dib[0].bits, dib[0].imageSize = 1, 24, imageSize
    local pixels = ffi.new("void *[1]")

    local source = user.fw_screen_GetDC(nil)
    if source == nil then return win.Error("GetDC(desktop)", 21) end
    local dc, bitmap, previous
    local function copy()
        dc = gdi.fw_screen_CreateCompatibleDC(source)
        if dc == nil then return win.Error("CreateCompatibleDC", 31) end
        bitmap = gdi.fw_screen_CreateDIBSection(source, dib, 0, pixels, nil, 0)
        if bitmap == nil then return win.Error("CreateDIBSection") end
        ffi.fill(pixels[0], imageSize)
        previous = gdi.fw_screen_SelectObject(dc, bitmap)
        if previous == nil then return win.Error("SelectObject", 31) end
        if gdi.fw_screen_BitBlt(dc, 0, 0, width, height, source, x, y, 0x40CC0020) == 0 then
            return win.Error("BitBlt")
        end
        if gdi.fw_screen_GdiFlush() == 0 then return win.Error("GdiFlush", 31) end
        return read(ffi.cast("const uint8_t *", pixels[0]), dib, stride)
    end
    local called, result, err, code = pcall(copy)
    if previous ~= nil then gdi.fw_screen_SelectObject(dc, previous) end
    if dc ~= nil then gdi.fw_screen_DeleteDC(dc) end
    if bitmap ~= nil then gdi.fw_screen_DeleteObject(bitmap) end
    user.fw_screen_ReleaseDC(nil, source)
    if not called then error(result, 0) end
    return result, err, code
end

local function readDesktop(read, x, y, width, height)
    local setDpi = win.Symbol(user, "fw_screen_SetThreadDpiAwarenessContext")
    if not setDpi then return win.Error("Per-monitor DPI awareness is unavailable", 127) end
    local previous = setDpi(ffi.cast("void *", -4))
    if previous == nil then previous = setDpi(ffi.cast("void *", -3)) end
    if previous == nil then return win.Error("SetThreadDpiAwarenessContext") end
    local called, result, err, code = pcall(readRegion, read, x, y, width, height)
    local restored = setDpi(previous)
    if not called then error(result, 0) end
    if restored == nil then return win.Error("Restore thread DPI awareness") end
    return result, err, code
end

local function validRegion(x, y, width, height)
    return win.Integer(x, -2147483648, 2147483647) and win.Integer(y, -2147483648, 2147483647)
        and win.Integer(width, 1, 2147483647) and win.Integer(height, 1, 2147483647)
end

local function bitmapBytes(pixels, dib)
    local header = ffi.new("fw_screen_bmp_header[1]")
    local offset = ffi.sizeof(header) + ffi.sizeof(dib)
    local imageSize = tonumber(dib[0].imageSize)
    header[0].type, header[0].size, header[0].offset = 0x4D42, imageSize + offset, offset
    return ffi.string(header, ffi.sizeof(header)) .. ffi.string(dib, ffi.sizeof(dib))
        .. ffi.string(pixels, imageSize)
end

local function capture(outputPath, x, y, width, height)
    if outputPath ~= nil and (type(outputPath) ~= "string" or not outputPath:lower():match("%.bmp$")) then
        return win.Error("Expected a .bmp output path", 87)
    end
    local bytes, err, code = readDesktop(bitmapBytes, x, y, width, height)
    if not bytes then return nil, err, code end
    if outputPath then return fs.FileWriteBytes(outputPath, bytes) end
    return bytes
end

function screen.Capture(outputPath)
    return capture(outputPath)
end

function screen.CaptureRegion(x, y, width, height, outputPath)
    if not validRegion(x, y, width, height) then
        return win.Error("Expected integer coordinates and positive dimensions", 87)
    end
    return capture(outputPath, x, y, width, height)
end

local function pixelColor(pixels)
    return pixels[2] * 65536 + pixels[1] * 256 + pixels[0]
end

function screen.GetPixel(x, y)
    if not validRegion(x, y, 1, 1) then return win.Error("Expected integer pixel coordinates", 87) end
    return readDesktop(pixelColor, x, y, 1, 1)
end

function screen.FindColor(color, rect, tolerance)
    if type(rect) ~= "table" then return win.Error("Expected a rectangle table", 87) end
    local x, y, width, height = rect.x, rect.y, rect.width, rect.height
    if not validRegion(x, y, width, height) then
        return win.Error("Expected a rectangle with x, y, width and height", 87)
    end
    if tolerance == nil then tolerance = 0 end
    if not win.Integer(color, 0, 0xFFFFFF) or not win.Integer(tolerance, 0, 255) then
        return win.Error("Expected an RGB color and integer tolerance from 0 to 255", 87)
    end
    local red, green, blue = math.floor(color / 65536), math.floor(color / 256) % 256, color % 256
    local abs = math.abs
    return readDesktop(function(pixels, _, stride)
        for row = 0, height - 1 do
            local pixel = pixels + row * stride
            for column = 0, width - 1 do
                if abs(pixel[2] - red) <= tolerance and abs(pixel[1] - green) <= tolerance
                    and abs(pixel[0] - blue) <= tolerance then
                    return {x = x + column, y = y + row, color = pixelColor(pixel)}
                end
                pixel = pixel + 3
            end
        end
        return false
    end, x, y, width, height)
end

return screen
