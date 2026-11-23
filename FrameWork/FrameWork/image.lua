local ffi = require("ffi")
local fs = require("fs")
local native = require("_win_native")
local win = require("_win_extension")
local gdip = ffi.load("gdiplus")
local shell = ffi.load("shlwapi")
local image = {}

ffi.cdef[[
typedef struct { uint32_t version; void *debugCallback; int suppressThread, suppressCodecs; } fw_image_startup;
typedef struct { uint32_t a; uint16_t b, c; uint8_t d[8]; } fw_image_guid;
typedef struct {
    fw_image_guid id, formatId;
    const uint16_t *name, *dllName, *description, *extension, *mime;
    uint32_t flags, version, sigCount, sigSize;
    const uint8_t *pattern, *mask;
} fw_image_codec;
typedef struct {
    fw_image_guid guid;
    uint32_t count, type;
    void *value;
} fw_image_encoder_parameter;
typedef struct {
    uint32_t count;
    fw_image_encoder_parameter parameter;
    uint32_t quality[1];
} fw_image_jpeg_options;
typedef struct {
    void *queryInterface;
    uint32_t (__stdcall *addRef)(void *);
    uint32_t (__stdcall *release)(void *);
    int32_t (__stdcall *read)(void *, void *, uint32_t, uint32_t *);
    void *write;
    int32_t (__stdcall *seek)(void *, int64_t, uint32_t, uint64_t *);
} fw_image_stream_vtable;
typedef struct { int x, y, width, height; } fw_image_rect;
typedef struct { float x, y; } fw_image_point;
typedef struct { float x, y, width, height; } fw_image_text_rect;
typedef struct {
    uint32_t width, height;
    int stride, format;
    void *data;
    uintptr_t reserved;
} fw_image_bitmap_data;

void *__stdcall SHCreateMemStream(const uint8_t *, uint32_t);
int __stdcall GdiplusStartup(uintptr_t *, const fw_image_startup *, void *);
void __stdcall GdiplusShutdown(uintptr_t);
int __stdcall GdipCreateBitmapFromStream(void *, void **);
int __stdcall GdipDisposeImage(void *);
int __stdcall GdipCloneImage(void *, void **);
int __stdcall GdipImageRotateFlip(void *, int);
int __stdcall GdipGetImageWidth(void *, uint32_t *);
int __stdcall GdipGetImageHeight(void *, uint32_t *);
int __stdcall GdipGetImagePixelFormat(void *, int *);
int __stdcall GdipGetImageEncodersSize(uint32_t *, uint32_t *);
int __stdcall GdipGetImageEncoders(uint32_t, uint32_t, fw_image_codec *);
int __stdcall GdipSaveImageToFile(void *, const uint16_t *, const fw_image_guid *, const void *);
int __stdcall GdipSaveImageToStream(void *, void *, const fw_image_guid *, const void *);
int __stdcall GdipCreateBitmapFromScan0(int, int, int, int, uint8_t *, void **);
int __stdcall GdipCloneBitmapAreaI(int, int, int, int, int, void *, void **);
int __stdcall GdipBitmapGetPixel(void *, int, int, uint32_t *);
int __stdcall GdipBitmapSetPixel(void *, int, int, uint32_t);
int __stdcall GdipBitmapLockBits(void *, const fw_image_rect *, uint32_t, int, fw_image_bitmap_data *);
int __stdcall GdipBitmapUnlockBits(void *, fw_image_bitmap_data *);
int __stdcall GdipGetImageGraphicsContext(void *, void **);
int __stdcall GdipDeleteGraphics(void *);
int __stdcall GdipGraphicsClear(void *, uint32_t);
int __stdcall GdipSetCompositingMode(void *, int);
int __stdcall GdipSetInterpolationMode(void *, int);
int __stdcall GdipSetPixelOffsetMode(void *, int);
int __stdcall GdipCreateImageAttributes(void **);
int __stdcall GdipSetImageAttributesWrapMode(void *, int, uint32_t, int);
int __stdcall GdipDisposeImageAttributes(void *);
int __stdcall GdipDrawImageRectRectI(void *, void *, int, int, int, int, int, int, int, int,
    int, const void *, void *, void *);
int __stdcall GdipDrawImagePointsRect(void *, void *, const fw_image_point *, int, float, float, float, float,
    int, const void *, void *, void *);
int __stdcall GdipGetGenericFontFamilySansSerif(void **);
int __stdcall GdipCreateFontFamilyFromName(const uint16_t *, void *, void **);
int __stdcall GdipDeleteFontFamily(void *);
int __stdcall GdipCreateFont(const void *, float, int, int, void **);
int __stdcall GdipDeleteFont(void *);
int __stdcall GdipCreateSolidFill(uint32_t, void **);
int __stdcall GdipDeleteBrush(void *);
int __stdcall GdipCreateStringFormat(int, uint16_t, void **);
int __stdcall GdipSetStringFormatAlign(void *, int);
int __stdcall GdipDeleteStringFormat(void *);
int __stdcall GdipSetPageUnit(void *, int);
int __stdcall GdipSetTextRenderingHint(void *, int);
int __stdcall GdipSetClipRectI(void *, int, int, int, int, int);
int __stdcall GdipDrawString(void *, const uint16_t *, int, const void *, const fw_image_text_rect *,
    const void *, const void *);
]]

local ARGB32 = 0x26200A -- PixelFormat32bppARGB
local ARGB_SIZE_LIMIT = 0x7FFFFFFF
local formats = {bmp = "image/bmp", png = "image/png", jpg = "image/jpeg", jpeg = "image/jpeg"}
local encoderQuality = ffi.new("fw_image_guid", {
    0x1D5BE4B5, 0xFA4A, 0x452D, {0x9C, 0xDD, 0x5D, 0xB3, 0x51, 0x05, 0xE7, 0xEB}
})
local codecs, token
local active = 0
local states = setmetatable({}, {__mode = "k"})
local methods = {}
local objectType = {__index = methods}

local function errorStatus(method, status)
    return nil, ("%s (GDI+ status %d)"):format(method, status), status
end

local function retain()
    if active == 0 then
        local out = ffi.new("uintptr_t[1]")
        local input = ffi.new("fw_image_startup[1]")
        input[0].version, input[0].suppressCodecs = 1, 1
        local status = gdip.GdiplusStartup(out, input, nil)
        if status ~= 0 then return errorStatus("GdiplusStartup", status) end
        token = out[0]
    end
    active = active + 1
    return true
end

local function releaseStream(stream)
    if stream ~= nil then ffi.cast("fw_image_stream_vtable **", stream)[0].release(stream) end
end

local function release(stream)
    releaseStream(stream)
    active = active - 1
    if active == 0 then
        gdip.GdiplusShutdown(token)
        codecs, token = nil, nil
    end
end

-- The bitmap may read from its stream until it is disposed.
local function ownBitmap(pointer, stream)
    return ffi.gc(pointer, function(ptr)
        gdip.GdipDisposeImage(ptr)
        release(stream)
    end)
end

local function wrap(pointer, width, height, stream)
    local object = setmetatable({}, objectType)
    states[object] = {pointer = ownBitmap(pointer, stream), width = width, height = height, stream = stream}
    return object
end

local function openState(object)
    local state = states[object]
    if not state or state.pointer == nil then return win.Error("Invalid or closed image", 6) end
    return state
end

function image.FromBytes(bytes)
    if type(bytes) ~= "string" or bytes == "" or #bytes > 0xFFFFFFFF then
        return win.Error("Expected nonempty encoded image bytes", 87)
    end
    local ok, err, code = retain()
    if not ok then return nil, err, code end
    local stream = shell.SHCreateMemStream(bytes, #bytes)
    if stream == nil then
        release()
        return win.Error("SHCreateMemStream", 8)
    end
    local bitmap = ffi.new("void *[1]")
    local width, height = ffi.new("uint32_t[1]"), ffi.new("uint32_t[1]")
    local status = gdip.GdipCreateBitmapFromStream(stream, bitmap)
    if status == 0 then status = gdip.GdipGetImageWidth(bitmap[0], width) end
    if status == 0 then status = gdip.GdipGetImageHeight(bitmap[0], height) end
    if status ~= 0 then
        if bitmap[0] ~= nil then gdip.GdipDisposeImage(bitmap[0]) end
        release(stream)
        return errorStatus("Decode bitmap", status)
    end
    return wrap(bitmap[0], tonumber(width[0]), tonumber(height[0]), stream)
end

function image.Load(path)
    if type(path) ~= "string" or path == "" then return win.Error("Expected image path", 87) end
    local bytes, err, code = fs.FileRead(path, "BINARY")
    if not bytes then return nil, err, code end
    return image.FromBytes(bytes)
end

function image.Close(object)
    local state = states[object]
    if not state then return win.Error("Invalid image", 6) end
    if state.pointer == nil then return true end
    local status = gdip.GdipDisposeImage(state.pointer)
    if status ~= 0 then return errorStatus("GdipDisposeImage", status) end
    ffi.gc(state.pointer, nil)
    release(state.stream)
    state.pointer, state.stream = nil, nil
    return true
end
methods.Close = image.Close

function image.GetSize(object)
    local state, err, code = openState(object)
    if not state then return nil, err, code end
    return state.width, state.height
end

local function findEncoder(mime)
    if not codecs then
        local count, size = ffi.new("uint32_t[1]"), ffi.new("uint32_t[1]")
        local status = gdip.GdipGetImageEncodersSize(count, size)
        if status ~= 0 then return errorStatus("GdipGetImageEncodersSize", status) end
        local buffer = ffi.new("uint8_t[?]", size[0])
        local list = ffi.cast("fw_image_codec *", buffer)
        status = gdip.GdipGetImageEncoders(count[0], size[0], list)
        if status ~= 0 then return errorStatus("GdipGetImageEncoders", status) end
        codecs = {}
        for i = 0, tonumber(count[0]) - 1 do
            local entry = list[i]
            if entry.mime ~= nil then
                local name = win.FromWide(entry.mime)
                if name then
                    local clsid = ffi.new("fw_image_guid[1]")
                    clsid[0] = entry.id
                    codecs[name] = clsid
                end
            end
        end
    end
    if not codecs[mime] then return win.Error("Image encoder unavailable", 50) end
    return codecs[mime]
end

local function encoderOptions(format, opts)
    local mime = type(format) == "string" and formats[format:lower()]
    if not mime then return win.Error("Expected BMP, PNG, JPG or JPEG format", 87) end
    local params
    if opts ~= nil then
        if type(opts) ~= "table" then return win.Error("Expected options table", 87) end
        for k in pairs(opts) do
            if k ~= "quality" then return win.Error("Unknown image saving option: " .. tostring(k), 87) end
        end
        if opts.quality ~= nil then
            if mime ~= "image/jpeg" or not win.Integer(opts.quality, 0, 100) then
                return win.Error("JPEG quality must be an integer from 0 to 100", 87)
            end
            params = ffi.new("fw_image_jpeg_options[1]")
            params[0].count, params[0].quality[0] = 1, opts.quality
            params[0].parameter.guid = encoderQuality
            params[0].parameter.count, params[0].parameter.type = 1, 4 -- EncoderParameterValueTypeLong
            params[0].parameter.value = params[0].quality
        end
    end
    local encoder, err, code = findEncoder(mime)
    if not encoder then return nil, err, code end
    return encoder, params
end

function image.Save(object, path, format, opts)
    local state, err, code = openState(object)
    if not state then return nil, err, code end
    if type(path) ~= "string" or path == "" then return win.Error("Expected destination path", 87) end
    if format == nil then format = path:match("%.([^%.\\/]+)$") end
    local encoder, params, status = encoderOptions(format, opts)
    if not encoder then return nil, params, status end
    local absolute
    absolute, err, code = fs.PathAbsolute(path)
    if not absolute then return nil, err, code end
    local file, temp, fileCode = native.FsMkstemp(fs.PathJoin(fs.PathDirName(absolute), ".fw-image-XXXXXX"))
    if not file then return nil, temp, fileCode end
    local ok
    ok, err, code = native.FsClose(file)
    if ok then
        local wide
        wide, err, code = win.PathWide(temp)
        if wide then
            local status = gdip.GdipSaveImageToFile(state.pointer, wide, encoder, params)
            if status == 0 then ok, err, code = native.FsRename(temp, absolute)
            else ok, err, code = errorStatus("GdipSaveImageToFile", status) end
        else ok = nil end
    end
    if not ok then native.FsUnlink(temp) end
    return ok, err, code
end

function image.Encode(object, format, opts)
    local state, err, code = openState(object)
    if not state then return nil, err, code end
    if format == nil then format = "png" end
    local encoder, params, status = encoderOptions(format, opts)
    if not encoder then return nil, params, status end
    local stream = shell.SHCreateMemStream(nil, 0)
    if stream == nil then return win.Error("SHCreateMemStream", 8) end
    local called, bytes, message, result = pcall(function()
        local status = gdip.GdipSaveImageToStream(state.pointer, stream, encoder, params)
        if status ~= 0 then return errorStatus("GdipSaveImageToStream", status) end
        local api = ffi.cast("fw_image_stream_vtable **", stream)[0]
        local size = ffi.new("uint64_t[1]")
        if api.seek(stream, 0, 2, size) < 0 or api.seek(stream, 0, 0, nil) < 0 then
            return win.Error("IStream.Seek", 31)
        end
        if size[0] == 0 or size[0] >= 0x7FFFFF00 then return win.Error("Invalid encoded image size", 13) end
        local buffer = ffi.new("uint8_t[?]", tonumber(size[0]))
        local read = ffi.new("uint32_t[1]")
        if api.read(stream, buffer, tonumber(size[0]), read) ~= 0 or read[0] ~= size[0] then
            return win.Error("IStream.Read", 30)
        end
        return ffi.string(buffer, tonumber(size[0]))
    end)
    releaseStream(stream)
    if not called then error(bytes, 0) end
    return bytes, message, result
end

local function validPoint(state, x, y)
    return win.Integer(x, 0, state.width - 1) and win.Integer(y, 0, state.height - 1)
end

local function validRegion(state, x, y, width, height)
    return validPoint(state, x, y) and win.Integer(width, 1, state.width - x)
        and win.Integer(height, 1, state.height - y)
end

function image.Crop(object, x, y, width, height)
    local state, err, code = openState(object)
    if not state then return nil, err, code end
    if not validRegion(state, x, y, width, height) then
        return win.Error("Crop rectangle lies outside the image", 87)
    end
    local bitmap = ffi.new("void *[1]")
    local status = gdip.GdipCloneBitmapAreaI(x, y, width, height, ARGB32, state.pointer, bitmap)
    if status ~= 0 then return errorStatus("GdipCloneBitmapAreaI", status) end
    active = active + 1
    return wrap(bitmap[0], width, height)
end

local function render(width, height, interpolation, draw)
    if width * height * 4 > ARGB_SIZE_LIMIT then return win.Error("ARGB bitmap is too large", 87) end
    local bitmap, graphics, attributes = ffi.new("void *[1]"), ffi.new("void *[1]"), ffi.new("void *[1]")
    local status = gdip.GdipCreateBitmapFromScan0(width, height, 0, ARGB32, nil, bitmap)
    if status == 0 then status = gdip.GdipGetImageGraphicsContext(bitmap[0], graphics) end
    if status == 0 then status = gdip.GdipSetCompositingMode(graphics[0], 1) end -- SourceCopy
    if status == 0 then status = gdip.GdipSetInterpolationMode(graphics[0], interpolation) end
    if status == 0 then status = gdip.GdipSetPixelOffsetMode(graphics[0], 4) end -- Half
    if status == 0 then status = gdip.GdipCreateImageAttributes(attributes) end
    if status == 0 then status = gdip.GdipSetImageAttributesWrapMode(attributes[0], 3, 0, 0) end -- TileFlipXY
    if status == 0 then status = draw(graphics[0], attributes[0]) end
    if attributes[0] ~= nil then gdip.GdipDisposeImageAttributes(attributes[0]) end
    if graphics[0] ~= nil then gdip.GdipDeleteGraphics(graphics[0]) end
    if status ~= 0 then
        if bitmap[0] ~= nil then gdip.GdipDisposeImage(bitmap[0]) end
        return errorStatus("Render bitmap", status)
    end
    return bitmap[0]
end

local function resample(state, width, height, interpolation)
    return render(width, height, interpolation, function(graphics, attributes)
        return gdip.GdipDrawImageRectRectI(graphics, state.pointer, 0, 0, width, height, 0, 0,
            state.width, state.height, 2, attributes, nil, nil) -- UnitPixel
    end)
end

function image.Resize(object, width, height)
    local state, err, code = openState(object)
    if not state then return nil, err, code end
    if not win.Integer(width, 1, 0x1FFFFFFF) or not win.Integer(height, 1, 0x7FFFFFFF) then
        return win.Error("Expected positive integer dimensions", 87)
    end
    local bitmap
    bitmap, err, code = resample(state, width, height, 7) -- HighQualityBicubic
    if not bitmap then return nil, err, code end
    active = active + 1
    return wrap(bitmap, width, height)
end

local function rotateFlip(state, operation, swapDimensions)
    local bitmap = ffi.new("void *[1]")
    local status = gdip.GdipCloneImage(state.pointer, bitmap)
    if status ~= 0 then return errorStatus("GdipCloneImage", status) end
    if operation ~= 0 then
        status = gdip.GdipImageRotateFlip(bitmap[0], operation)
        if status ~= 0 then
            gdip.GdipDisposeImage(bitmap[0])
            return errorStatus("GdipImageRotateFlip", status)
        end
    end
    local stream = state.stream
    if stream ~= nil then ffi.cast("fw_image_stream_vtable **", stream)[0].addRef(stream) end
    local width, height = state.width, state.height
    if swapDimensions then width, height = height, width end
    active = active + 1
    return wrap(bitmap[0], width, height, stream)
end

function image.Rotate(object, angle)
    local state, err, code = openState(object)
    if not state then return nil, err, code end
    if type(angle) ~= "number" or not (angle > -math.huge and angle < math.huge) then
        return win.Error("Expected finite angle in degrees", 87)
    end
    angle = math.fmod(angle, 360)
    if angle < 0 then angle = angle + 360 end
    if angle % 90 == 0 then
        local turn = angle % 360 / 90
        return rotateFlip(state, turn, turn % 2 == 1)
    end

    local radians = math.rad(angle)
    local cosine, sine = math.cos(radians), math.sin(radians)
    local rightX, rightY = state.width * cosine, state.width * sine
    local bottomX, bottomY = -state.height * sine, state.height * cosine
    local spanX, spanY = math.abs(rightX) + math.abs(bottomX), math.abs(rightY) + math.abs(bottomY)
    local width, height = math.ceil(spanX), math.ceil(spanY)
    local x = (width - spanX) / 2 - math.min(0, rightX) - math.min(0, bottomX)
    local y = (height - spanY) / 2 - math.min(0, rightY) - math.min(0, bottomY)
    -- Sampling only at final pixel centers can miss a one-pixel detail.
    local scale = width * height * 16 <= ARGB_SIZE_LIMIT and 2 or 1
    local corners = ffi.new("fw_image_point[3]", {
        {x * scale, y * scale},
        {(x + rightX) * scale, (y + rightY) * scale},
        {(x + bottomX) * scale, (y + bottomY) * scale}
    })
    local bitmap
    bitmap, err, code = render(width * scale, height * scale, 7, function(graphics, attributes)
        local status = gdip.GdipGraphicsClear(graphics, 0)
        if status ~= 0 then return status end
        return gdip.GdipDrawImagePointsRect(graphics, state.pointer, corners, 3, 0, 0,
            state.width, state.height, 2, attributes, nil, nil) -- UnitPixel
    end)
    if not bitmap then return nil, err, code end
    if scale ~= 1 then
        local scaled
        scaled, err, code = resample({pointer = bitmap, width = width * scale, height = height * scale}, width, height, 7)
        gdip.GdipDisposeImage(bitmap)
        if not scaled then return nil, err, code end
        bitmap = scaled
    end
    active = active + 1
    return wrap(bitmap, width, height)
end

function image.Flip(object, axis)
    local state, err, code = openState(object)
    if not state then return nil, err, code end
    if axis == "horizontal" then return rotateFlip(state, 4) end -- RotateNoneFlipX
    if axis == "vertical" then return rotateFlip(state, 6) end -- RotateNoneFlipY
    return win.Error('Expected axis "horizontal" or "vertical"', 87)
end

local function editBitmap(state, edit)
    if not state.argb32 then
        local format = ffi.new("int[1]")
        local status = gdip.GdipGetImagePixelFormat(state.pointer, format)
        if status ~= 0 then return errorStatus("GdipGetImagePixelFormat", status) end
        state.argb32 = format[0] == ARGB32
    end
    if state.argb32 then return edit(state.pointer) end

    -- Indexed and RGB bitmaps may reject edits or discard alpha. Convert once.
    local bitmap, err, code = resample(state, state.width, state.height, 5) -- NearestNeighbor
    if not bitmap then return nil, err, code end
    local ok
    ok, err, code = edit(bitmap)
    if not ok then
        gdip.GdipDisposeImage(bitmap)
        return nil, err, code
    end
    local status = gdip.GdipDisposeImage(state.pointer)
    if status ~= 0 then
        gdip.GdipDisposeImage(bitmap)
        return errorStatus("GdipDisposeImage", status)
    end
    ffi.gc(state.pointer, nil)
    releaseStream(state.stream)
    state.pointer, state.stream, state.argb32 = ownBitmap(bitmap), nil, true
    return true
end

local function argbColor(color, alpha)
    if alpha == nil then alpha = 255 end
    if not win.Integer(color, 0, 0xFFFFFF) or not win.Integer(alpha, 0, 255) then
        return win.Error("Expected a 24-bit RGB color and alpha from 0 to 255", 87)
    end
    return alpha * 0x1000000 + color
end

function image.GetPixel(object, x, y)
    local state, err, code = openState(object)
    if not state then return nil, err, code end
    if not validPoint(state, x, y) then return win.Error("Pixel lies outside the image", 87) end
    local out = ffi.new("uint32_t[1]")
    local status = gdip.GdipBitmapGetPixel(state.pointer, x, y, out)
    if status ~= 0 then return errorStatus("GdipBitmapGetPixel", status) end
    local argb = tonumber(out[0])
    return argb % 0x1000000, math.floor(argb / 0x1000000)
end

function image.SetPixel(object, x, y, color, alpha)
    local state, err, code = openState(object)
    if not state then return nil, err, code end
    if not validPoint(state, x, y) then return win.Error("Pixel lies outside the image", 87) end
    local argb
    argb, err, code = argbColor(color, alpha)
    if not argb then return nil, err, code end
    return editBitmap(state, function(bitmap)
        local status = gdip.GdipBitmapSetPixel(bitmap, x, y, argb)
        if status ~= 0 then return errorStatus("GdipBitmapSetPixel", status) end
        return true
    end)
end

function image.DrawRect(object, x, y, width, height, color, opts)
    local state, err, code = openState(object)
    if not state then return nil, err, code end
    if not validRegion(state, x, y, width, height) then
        return win.Error("Rectangle lies outside the image", 87)
    end
    if opts == nil then opts = {} end
    if type(opts) ~= "table" then return win.Error("Expected options table", 87) end
    for k in pairs(opts) do
        if k ~= "alpha" and k ~= "fill" and k ~= "thickness" then
            return win.Error("Unknown rectangle option: " .. tostring(k), 87)
        end
    end
    if opts.fill ~= nil and type(opts.fill) ~= "boolean" then return win.Error("fill must be boolean", 87) end
    local thickness = opts.thickness
    if thickness == nil then thickness = 1 end
    if not win.Integer(thickness, 1, 0x7FFFFFFF) then return win.Error("Expected positive thickness", 87) end
    local argb
    argb, err, code = argbColor(color, opts.alpha)
    if not argb then return nil, err, code end
    local fill = opts.fill or thickness * 2 >= math.min(width, height)
    local rect = ffi.new("fw_image_rect[1]", {{x, y, width, height}})
    local data = ffi.new("fw_image_bitmap_data[1]")
    return editBitmap(state, function(bitmap)
        local status = gdip.GdipBitmapLockBits(bitmap, rect, 3, ARGB32, data) -- Read | Write
        if status ~= 0 then return errorStatus("GdipBitmapLockBits", status) end
        local start, stride = ffi.cast("uint8_t *", data[0].data), tonumber(data[0].stride)
        for row = 0, height - 1 do
            local pixels = ffi.cast("uint32_t *", start + row * stride)
            if fill or row < thickness or row >= height - thickness then
                for column = 0, width - 1 do pixels[column] = argb end
            else
                for column = 0, thickness - 1 do
                    pixels[column], pixels[width - 1 - column] = argb, argb
                end
            end
        end
        status = gdip.GdipBitmapUnlockBits(bitmap, data)
        if status ~= 0 then return errorStatus("GdipBitmapUnlockBits", status) end
        return true
    end)
end

local textOptions = {
    font = "string", size = "number", color = "number", alpha = "number", bold = "boolean", italic = "boolean",
    width = "number", height = "number", align = "string", wrap = "boolean"
}
local textAlignment = {left = 0, center = 1, right = 2}

function image.DrawText(object, text, x, y, opts)
    local state, err, code = openState(object)
    if not state then return nil, err, code end
    if not validPoint(state, x, y) then return win.Error("Text origin lies outside the image", 87) end
    if opts == nil then opts = {} end
    if type(opts) ~= "table" then return win.Error("Expected text options table", 87) end
    for name, value in pairs(opts) do
        if type(value) ~= textOptions[name] then return win.Error("Invalid text option: " .. tostring(name), 87) end
    end
    local width, height = opts.width or state.width - x, opts.height or state.height - y
    if not validRegion(state, x, y, width, height) then return win.Error("Text area lies outside the image", 87) end
    local size, align = opts.size or 16, textAlignment[opts.align or "left"]
    if not (size > 0 and size <= 0x7FFFFFFF) or align == nil then
        return win.Error("Expected a positive font size and left, center or right alignment", 87)
    end
    local color
    color, err, code = argbColor(opts.color or 0, opts.alpha)
    if not color then return nil, err, code end
    local wide, length
    wide, length, code = win.ToWide(text)
    if not wide then return nil, length, code end
    local fontName
    if opts.font ~= nil then
        if opts.font == "" then return win.Error("Font family name is empty", 87) end
        fontName, err, code = win.ToWide(opts.font)
        if not fontName then return nil, err, code end
    end
    if length == 0 or opts.alpha == 0 then return true end

    local rect = ffi.new("fw_image_text_rect[1]", {{x, y, width, height}})
    local family, font, brush = ffi.new("void *[1]"), ffi.new("void *[1]"), ffi.new("void *[1]")
    local format, graphics = ffi.new("void *[1]"), ffi.new("void *[1]")
    local style = (opts.bold and 1 or 0) + (opts.italic and 2 or 0)
    local formatFlags = opts.wrap == false and 0x1000 or 0 -- StringFormatFlagsNoWrap
    return editBitmap(state, function(bitmap)
        local status
        if fontName then status = gdip.GdipCreateFontFamilyFromName(fontName, nil, family)
        else status = gdip.GdipGetGenericFontFamilySansSerif(family) end
        if status == 0 then status = gdip.GdipCreateFont(family[0], size, style, 2, font) end -- UnitPixel
        if status == 0 then status = gdip.GdipCreateSolidFill(color, brush) end
        if status == 0 then status = gdip.GdipCreateStringFormat(formatFlags, 0, format) end
        if status == 0 then status = gdip.GdipSetStringFormatAlign(format[0], align) end
        if status == 0 then status = gdip.GdipGetImageGraphicsContext(bitmap, graphics) end
        if status == 0 then status = gdip.GdipSetPageUnit(graphics[0], 2) end -- UnitPixel
        if status == 0 then status = gdip.GdipSetTextRenderingHint(graphics[0], 3) end -- AntiAliasGridFit
        if status == 0 then status = gdip.GdipSetClipRectI(graphics[0], x, y, width, height, 1) end -- Intersect
        if status == 0 then
            status = gdip.GdipDrawString(graphics[0], wide, length, font[0], rect, format[0], brush[0])
        end
        if graphics[0] ~= nil then gdip.GdipDeleteGraphics(graphics[0]) end
        if format[0] ~= nil then gdip.GdipDeleteStringFormat(format[0]) end
        if brush[0] ~= nil then gdip.GdipDeleteBrush(brush[0]) end
        if font[0] ~= nil then gdip.GdipDeleteFont(font[0]) end
        if family[0] ~= nil then gdip.GdipDeleteFontFamily(family[0]) end
        if status ~= 0 then return errorStatus("Draw text", status) end
        return true
    end)
end

return image
