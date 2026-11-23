local ffi = require("ffi")
local win = require("_win_extension")
local native = require("_win_native")
local str = require("str")
local M = {}
local LIMIT, ITERATIONS = 64 * 1024 * 1024, 600000
local HEADER, PREFIX = 44, 60
local MAGIC = "W32PASS1"
local FILE_MAGIC, FILE_HEADER, BLOCK = "W32FILE1", 32, 1024 * 1024
local TAG, REKEY_BLOCKS = 16, 1024
ffi.cdef[[
unsigned long __stdcall GetFileType(void *);
typedef struct {
    uint32_t size, version;
    uint8_t *nonce;
    uint32_t nonceBytes;
    uint8_t *aad;
    uint32_t aadBytes;
    uint8_t *tag;
    uint32_t tagBytes;
    uint8_t *macContext;
    uint32_t macContextBytes, aadProcessed;
    uint64_t bytesProcessed;
    uint32_t flags;
} fw_gcm_info;
typedef struct { uint32_t size; uint8_t *data; } fw_data_blob;
long __stdcall BCryptOpenAlgorithmProvider(void **, const uint16_t *, const uint16_t *, unsigned long);
long __stdcall BCryptCloseAlgorithmProvider(void *, unsigned long);
long __stdcall BCryptCreateHash(void *, void **, void *, unsigned long, const void *, unsigned long, unsigned long);
long __stdcall BCryptHashData(void *, const void *, unsigned long, unsigned long);
long __stdcall BCryptFinishHash(void *, void *, unsigned long, unsigned long);
long __stdcall BCryptDestroyHash(void *);
long __stdcall BCryptDeriveKeyPBKDF2(void *, const void *, unsigned long, const void *,
    unsigned long, uint64_t, void *, unsigned long, unsigned long);
long __stdcall BCryptGenerateSymmetricKey(void *, void **, void *, unsigned long, const void *, unsigned long, unsigned long);
long __stdcall BCryptDestroyKey(void *);
long __stdcall BCryptSetProperty(void *, const uint16_t *, const void *, unsigned long, unsigned long);
long __stdcall BCryptEncrypt(void *, const void *, unsigned long, fw_gcm_info *, void *, unsigned long,
    void *, unsigned long, unsigned long *, unsigned long);
long __stdcall BCryptDecrypt(void *, const void *, unsigned long, fw_gcm_info *, void *, unsigned long,
    void *, unsigned long, unsigned long *, unsigned long);
int __stdcall CryptBinaryToStringA(const uint8_t *, unsigned long, unsigned long, char *, unsigned long *);
int __stdcall CryptStringToBinaryA(const char *, unsigned long, unsigned long, uint8_t *,
    unsigned long *, unsigned long *, unsigned long *);
int __stdcall CryptProtectData(fw_data_blob *, const uint16_t *, fw_data_blob *, void *, void *, uint32_t, fw_data_blob *);
int __stdcall CryptUnprotectData(fw_data_blob *, uint16_t **, fw_data_blob *, void *, void *, uint32_t, fw_data_blob *);
]]

local function nt(operation, status)
    if status < 0 then
        local hex = tonumber(ffi.cast("uint32_t", status))
        error({message = ("%s (NTSTATUS 0x%08X)"):format(operation, hex), code = tonumber(status)}, 0)
    end
end

local function fail(message, code)
    error({message = message, code = code}, 0)
end

local function asResult(ok, result, cleanup)
    if not ok then
        if type(result) == "table" then return nil, result.message, result.code end
        error(result, 0)
    end
    if cleanup and cleanup < 0 then
        return nil, ("CNG cleanup (NTSTATUS 0x%08X)"):format(tonumber(ffi.cast("uint32_t", cleanup))), tonumber(cleanup)
    end
    return result
end

local function hex(bytes)
    return (bytes:gsub(".", function(char) return ("%02x"):format(char:byte()) end))
end

local function getAlgorithm(algorithm)
    if algorithm == nil then return "SHA256", 32 end
    if type(algorithm) == "string" then
        local name = algorithm:upper():gsub("%-", "")
        if name == "SHA256" then return name, 32 end
        if name == "SHA512" then return name, 64 end
    end
end

local function digest(algorithm, key, options, feed)
    local alg, length = getAlgorithm(algorithm)
    if not alg or (options ~= nil and
        (type(options) ~= "table" or (options.raw ~= nil and type(options.raw) ~= "boolean"))) then
        return win.Error("Unsupported hash algorithm or options", 87)
    end
    local b, err, code = win.Library("bcrypt")
    if not b then return nil, err, code end
    local provider, hash = ffi.new("void *[1]"), ffi.new("void *[1]")
    local out = ffi.new("uint8_t[?]", length)
    local function update(bytes)
        if #bytes > 0 then nt("BCryptHashData", b.BCryptHashData(hash[0], bytes, #bytes, 0)) end
    end
    local ok, result = pcall(function()
        nt("BCryptOpenAlgorithmProvider", b.BCryptOpenAlgorithmProvider(provider, win.ToWide(alg), nil, key and 8 or 0))
        nt("BCryptCreateHash", b.BCryptCreateHash(provider[0], hash, nil, 0, key, key and #key or 0, 0))
        feed(update)
        nt("BCryptFinishHash", b.BCryptFinishHash(hash[0], out, length, 0))
        local bytes = ffi.string(out, length)
        return options and options.raw and bytes or hex(bytes)
    end)
    local cleanup = 0
    if hash[0] ~= nil then cleanup = b.BCryptDestroyHash(hash[0]) end
    if provider[0] ~= nil then cleanup = math.min(cleanup, b.BCryptCloseAlgorithmProvider(provider[0], 0)) end
    return asResult(ok, result, cleanup)
end

local function validBytes(bytes)
    return type(bytes) == "string" and #bytes <= 0x7FFFFFFF
end

function M.RandomBytes(count)
    if not win.Integer(count, 0, LIMIT) then return win.Error("Invalid random byte count", 87) end
    if count == 0 then return "" end
    local b, err, code = win.Library("bcrypt")
    if not b then return nil, err, code end
    local data = ffi.new("uint8_t[?]", count)
    local ok, result = pcall(function()
        nt("BCryptGenRandom", b.BCryptGenRandom(nil, data, count, 2))
        return ffi.string(data, count)
    end)
    ffi.fill(data, count)
    return asResult(ok, result)
end
jit.off(M.RandomBytes, true)

function M.Hash(bytes, algorithm, options)
    if not validBytes(bytes) then return win.Error("Expected binary string", 87) end
    return digest(algorithm, nil, options, function(update) update(bytes) end)
end

function M.Hmac(bytes, key, algorithm, options)
    if not validBytes(bytes) or not validBytes(key) then return win.Error("Expected binary strings", 87) end
    return digest(algorithm, key, options, function(update) update(bytes) end)
end

function M.FileHash(path, algorithm, options)
    local wide, err, code = win.PathWide(path)
    if not wide then return nil, err, code end
    return digest(algorithm, nil, options, function(update)
        local handle, detail, status = native.FsOpen(path, "r")
        if not handle then fail(detail, status) end
        local ok, why = pcall(function()
            while true do
                local bytes, message, readCode = native.FsRead(handle, 65536)
                if not bytes then fail(message, readCode) end
                if #bytes == 0 then return end
                update(bytes)
            end
        end)
        local closed, message, closeCode = native.FsClose(handle)
        if not ok then error(why, 0) end
        if not closed then fail(message, closeCode) end
    end)
end

local function validatePassword(password)
    if type(password) ~= "string" or #password == 0 or #password > 4096 then
        return win.Error("Password must contain 1 to 4096 UTF-8 bytes", 87)
    end
    -- Validate UTF-8 and discard the temporary wide copy. W32PASS1 derives its key from the original UTF-8 bytes.
    local passWide, units, code = win.ToWide(password)
    if not passWide then return nil, units, code end
    ffi.fill(passWide, (units + 1) * 2)
    return true
end

local function encryptionIterations(options)
    local iterations = options.iterations
    if iterations == nil then iterations = ITERATIONS end
    if not win.Integer(iterations, 100000, 2000000) then
        return win.Error("iterations must be between 100000 and 2000000", 87)
    end
    return iterations
end

local function withAes(password, salt, iterations, run)
    local b, err, code = win.Library("bcrypt")
    if not b then return nil, err, code end
    local sha, aes, key = ffi.new("void *[1]"), ffi.new("void *[1]"), ffi.new("void *[1]")
    local secret = ffi.new("uint8_t[32]")
    local ok, result = pcall(function()
        nt("Open HMAC-SHA256", b.BCryptOpenAlgorithmProvider(sha, win.ToWide("SHA256"), nil, 8))
        nt("BCryptDeriveKeyPBKDF2", b.BCryptDeriveKeyPBKDF2(sha[0], password, #password,
            salt, 16, iterations, secret, 32, 0))
        nt("Open AES", b.BCryptOpenAlgorithmProvider(aes, win.ToWide("AES"), nil, 0))
        local mode, modeUnits = win.ToWide("ChainingModeGCM")
        nt("Set AES-GCM", b.BCryptSetProperty(aes[0], win.ToWide("ChainingMode"), mode, (modeUnits + 1) * 2, 0))
        return run(b, aes[0], key, sha[0], secret)
    end)
    local cleanup = 0
    if key[0] ~= nil then cleanup = b.BCryptDestroyKey(key[0]) end
    if aes[0] ~= nil then cleanup = math.min(cleanup, b.BCryptCloseAlgorithmProvider(aes[0], 0)) end
    if sha[0] ~= nil then cleanup = math.min(cleanup, b.BCryptCloseAlgorithmProvider(sha[0], 0)) end
    ffi.fill(secret, 32)
    return asResult(ok, result, cleanup)
end

local function gcm(encrypt, b, key, input, count, output, nonce, aad, aadBytes, tag)
    local info = ffi.new("fw_gcm_info[1]")
    info[0].size, info[0].version = ffi.sizeof(info[0]), 1
    info[0].nonce, info[0].nonceBytes = nonce, 12
    info[0].aad, info[0].aadBytes = aad, aadBytes
    info[0].tag, info[0].tagBytes = tag, TAG
    local written = ffi.new("unsigned long[1]")
    local operation = encrypt and b.BCryptEncrypt or b.BCryptDecrypt
    local status = operation(key, count > 0 and input or nil, count, info, nil, 0,
        count > 0 and output or nil, count, written, 0)
    if tonumber(ffi.cast("uint32_t", status)) == 0xC000A002 then
        fail("Wrong password or damaged encrypted data", tonumber(status))
    end
    nt(encrypt and "BCryptEncrypt" or "BCryptDecrypt", status)
    if written[0] ~= count then fail("Unexpected AES-GCM output length", 13) end
end

-- Compatible with the default W32PASS1 format in the standalone Windows module.
local function crypt(encrypt, data, password, iterations)
    if not validBytes(data) or #data > LIMIT + (encrypt and 0 or PREFIX) then
        return win.Error("Invalid data or AES-GCM size limit exceeded", 87)
    end
    local valid, err, code = validatePassword(password)
    if not valid then return nil, err, code end
    local header = ffi.new("uint8_t[?]", PREFIX)
    local fields = ffi.cast("uint32_t *", header)
    local count = #data
    if encrypt then
        ffi.copy(header, MAGIC, #MAGIC)
        fields[2], fields[3] = iterations, count
        local random
        random, err, code = M.RandomBytes(28)
        if not random then return nil, err, code end
        ffi.copy(header + 16, random, 28)
    else
        if count < PREFIX or data:sub(1, #MAGIC) ~= MAGIC then return win.Error("Invalid W32PASS1 blob", 13) end
        ffi.copy(header, data, PREFIX)
        iterations, count = tonumber(fields[2]), tonumber(fields[3])
        if not win.Integer(iterations, 100000, 2000000) or count ~= #data - PREFIX then
            return win.Error("Invalid W32PASS1 parameters or length", 13)
        end
    end
    local output = ffi.new("uint8_t[?]", math.max(count, 1))
    local result
    result, err, code = withAes(password, header + 16, iterations, function(b, aes, key, _, secret)
        nt("BCryptGenerateSymmetricKey", b.BCryptGenerateSymmetricKey(aes, key, nil, 0, secret, 32, 0))
        local input = ffi.cast("const uint8_t *", data) + (encrypt and 0 or PREFIX)
        gcm(encrypt, b, key[0], input, count, output, header + 32, header, HEADER, header + HEADER)
        local bytes = ffi.string(output, count)
        return encrypt and ffi.string(header, PREFIX) .. bytes or bytes
    end)
    ffi.fill(output, math.max(count, 1))
    return result, err, code
end
jit.off(crypt, true)
jit.off(withAes, true)
jit.off(gcm, true)

function M.Encrypt(bytes, password, options)
    if options == nil then options = {} end
    if type(options) ~= "table" then return win.Error("Expected encryption options table", 87) end
    local iterations, err, code = encryptionIterations(options)
    if not iterations then return nil, err, code end
    return crypt(true, bytes, password, iterations)
end

function M.Decrypt(blob, password)
    return crypt(false, blob, password)
end

local BASE64, NO_CRLF = 1, 0x40000000
local MAX_BASE64 = 4 * math.ceil((LIMIT + PREFIX) / 3)

local function base64Encode(blob)
    if #blob == 0 then return "" end
    local dll, err, code = win.Library("crypt32")
    if not dll then return nil, err, code end
    local size = ffi.new("unsigned long[1]")
    local flags = BASE64 + NO_CRLF
    if dll.CryptBinaryToStringA(blob, #blob, flags, nil, size) == 0 then
        return win.Error("CryptBinaryToStringA")
    end
    local output = ffi.new("char[?]", size[0])
    if dll.CryptBinaryToStringA(blob, #blob, flags, output, size) == 0 then
        return win.Error("CryptBinaryToStringA")
    end
    return ffi.string(output, size[0])
end

local function base64Decode(encoded, maximum)
    if type(encoded) ~= "string" or #encoded > maximum then
        return win.Error("Expected Base64 within size limit", 87)
    end
    if #encoded == 0 then return "" end
    if #encoded % 4 ~= 0 or
        not encoded:match("^[A-Za-z0-9+/]+=?=?$") then
        return win.Error("Invalid Base64", 13)
    end
    local dll, err, code = win.Library("crypt32")
    if not dll then return nil, err, code end
    -- The grammar above checks the complete input, including trailing padding.
    local padding = encoded:sub(-2) == "==" and 2 or (encoded:sub(-1) == "=" and 1 or 0)
    local length = #encoded / 4 * 3 - padding
    local size = ffi.new("unsigned long[1]", length)
    local blob = ffi.new("uint8_t[?]", length)
    if dll.CryptStringToBinaryA(encoded, #encoded, BASE64, blob, size, nil, nil) == 0 then
        return win.Error("CryptStringToBinaryA")
    end
    if size[0] ~= length then return win.Error("Invalid Base64 length", 13) end
    return ffi.string(blob, length)
end

function M.Base64Encode(bytes)
    if type(bytes) ~= "string" or #bytes > LIMIT then
        return win.Error("Expected bytes up to 64 MiB", 87)
    end
    return base64Encode(bytes)
end

function M.Base64Decode(text)
    local bytes, err, code = base64Decode(text, 4 * math.ceil(LIMIT / 3))
    if not bytes then return nil, err, code end
    if #bytes > LIMIT then return win.Error("Decoded Base64 exceeds 64 MiB", 223) end
    return bytes
end

function M.EncryptText(text, password, options)
    if type(text) ~= "string" or #text > LIMIT or not str.IsValidUtf8(text) then
        return win.Error("Expected UTF-8 text up to 64 MiB", 87)
    end
    local blob, err, code = M.Encrypt(text, password, options)
    if not blob then return nil, err, code end
    return base64Encode(blob)
end

function M.DecryptText(encoded, password)
    if type(encoded) ~= "string" or #encoded == 0 or #encoded > MAX_BASE64 then
        return win.Error("Expected a Base64 string produced by crypto.EncryptText", 13)
    end
    local blob, err, code = base64Decode(encoded, MAX_BASE64)
    if not blob then return nil, err, code end
    local text
    text, err, code = M.Decrypt(blob, password)
    if not text then return nil, err, code end
    if not str.IsValidUtf8(text) then return win.Error("Decrypted data is not UTF-8 text", 1113) end
    return text
end

jit.off(M.EncryptText, true)
jit.off(M.DecryptText, true)

local function checked(result, message, code)
    if not result then
        fail(message, code)
    end
    return result
end

local function openCryptoTemp(directory)
    local k = win.kernel
    for _ = 1, 16 do
        local path = directory .. ".fw-crypto-" .. hex(checked(M.RandomBytes(16)))
        local wide = checked(win.PathWide(path))
        local handle = k.CreateFileW(wide, 0x40000000, 0, nil, 1, 128, nil)
        if handle ~= win.invalidHandle then return win.Own(handle), wide end
        local code = k.GetLastError()
        if code ~= 80 and code ~= 183 then checked(win.Error("CreateFileW(crypto temporary file)", code)) end
    end
    fail("Could not create a unique crypto temporary file", 80)
end

local function readBlock(handle, count)
    local bytes = checked(native.FsRead(handle, count))
    while #bytes > 0 and #bytes < count do
        local more = checked(native.FsRead(handle, count - #bytes))
        if #more == 0 then break end
        bytes = bytes .. more
    end
    return bytes
end

local function writeBlock(handle, bytes)
    while #bytes > 0 do
        local count = checked(native.FsWrite(handle, bytes))
        if count == 0 then fail("Incomplete file write", 29) end
        bytes = bytes:sub(count + 1)
    end
end

local function fileKey(b, aes, key, sha, secret, epoch)
    if key[0] ~= nil then
        nt("BCryptDestroyKey", b.BCryptDestroyKey(key[0]))
        key[0] = nil
    end
    -- Use independent AES keys for groups of records to bound GCM usage per key.
    local context = FILE_MAGIC .. ffi.string(ffi.new("uint64_t[1]", epoch), 8)
    local hash = ffi.new("void *[1]")
    local derived = ffi.new("uint8_t[32]")
    local ok, result = pcall(function()
        nt("BCryptCreateHash", b.BCryptCreateHash(sha, hash, nil, 0, secret, 32, 0))
        nt("BCryptHashData", b.BCryptHashData(hash[0], context, #context, 0))
        nt("BCryptFinishHash", b.BCryptFinishHash(hash[0], derived, 32, 0))
        nt("BCryptGenerateSymmetricKey", b.BCryptGenerateSymmetricKey(aes, key, nil, 0, derived, 32, 0))
    end)
    ffi.fill(derived, 32)
    local cleanup = hash[0] ~= nil and b.BCryptDestroyHash(hash[0]) or 0
    if not ok then error(result, 0) end
    nt("BCryptDestroyHash", cleanup)
end

local function streamFile(encrypt, source, destination, header, password, iterations)
    local output = ffi.new("uint8_t[?]", BLOCK)
    local result, err, code = withAes(password, header + 16, iterations, function(b, aes, key, sha, secret)
        local tag = ffi.new("uint8_t[?]", TAG)
        local nonce = ffi.new("uint8_t[12]")
        local counter = ffi.cast("uint64_t *", nonce)
        local slot, epoch = 0, 0ULL
        if encrypt then writeBlock(destination, ffi.string(header, FILE_HEADER)) end
        while true do
            if slot == 0 then fileKey(b, aes, key, sha, secret, epoch) end
            counter[0] = slot
            local record = readBlock(source, encrypt and BLOCK or BLOCK + TAG)
            local count = #record
            if not encrypt then
                if count < TAG then fail("Truncated W32FILE1 file", 13) end
                count = count - TAG
                ffi.copy(tag, ffi.cast("const uint8_t *", record) + count, TAG)
            end
            gcm(encrypt, b, key[0], record, count, output, nonce, header, FILE_HEADER, tag)
            writeBlock(destination, ffi.string(output, count))
            if encrypt then writeBlock(destination, ffi.string(tag, TAG)) end
            -- The final record is always short, including an empty record at an exact boundary.
            if count < BLOCK then return true end
            slot = slot + 1
            if slot == REKEY_BLOCKS then
                slot, epoch = 0, epoch + 1ULL
            end
        end
    end)
    ffi.fill(output, BLOCK)
    return result, err, code
end
jit.off(streamFile, true)

local function fileCrypt(encrypt, sourcePath, destinationPath, password, options)
    if options == nil then options = {} end
    if type(options) ~= "table" or (options.overwrite ~= nil and type(options.overwrite) ~= "boolean") then
        return win.Error("Expected file options with boolean overwrite", 87)
    end
    local valid, err, code = validatePassword(password)
    if not valid then return nil, err, code end
    local iterations
    if encrypt then
        iterations, err, code = encryptionIterations(options)
        if not iterations then return nil, err, code end
    end
    local target
    target, err, code = win.PathWide(destinationPath)
    if not target then return nil, err, code end
    local fullPath
    fullPath, err, code = win.FromWide(target)
    if not fullPath then return nil, err, code end
    local directory, name = fullPath:match("^(.*\\)([^\\]+)$")
    if not directory or name:find(":", 1, true) or name == "." or name == ".." then
        return win.Error("Expected a destination file path", 87)
    end
    local k = win.kernel
    local source, destination, temporary
    local ok, result = pcall(function()
        -- Keep other processes from modifying or replacing the source during the operation.
        local sourceWide = checked(win.PathWide(sourcePath))
        local input = k.CreateFileW(sourceWide, 0x80000000, 1, nil, 3, 128, nil)
        if input == win.invalidHandle then checked(win.Error("CreateFileW(crypto source)", nil, sourcePath)) end
        source = win.Own(input)
        if k.GetFileType(source) ~= 1 then fail("Expected a disk file as input", 87) end
        local header = ffi.new("uint8_t[?]", FILE_HEADER)
        local fields = ffi.cast("uint32_t *", header)
        if encrypt then
            ffi.copy(header, FILE_MAGIC, #FILE_MAGIC)
            fields[2] = iterations
            ffi.copy(header + 16, checked(M.RandomBytes(16)), 16)
        else
            local bytes = readBlock(source, FILE_HEADER)
            if #bytes ~= FILE_HEADER or bytes:sub(1, #FILE_MAGIC) ~= FILE_MAGIC then
                fail("Invalid W32FILE1 header", 13)
            end
            ffi.copy(header, bytes, FILE_HEADER)
            iterations = tonumber(fields[2])
            if not win.Integer(iterations, 100000, 2000000) or fields[3] ~= 0 then
                fail("Invalid W32FILE1 parameters", 13)
            end
        end
        destination, temporary = openCryptoTemp(directory)
        checked(streamFile(encrypt, source, destination, header, password, iterations))
        checked(native.FsFsync(destination))
        checked(native.FsClose(destination))
        destination = nil
        local flags = options.overwrite and 9 or 8 -- MOVEFILE_WRITE_THROUGH, optionally REPLACE_EXISTING.
        if k.MoveFileExW(temporary, target, flags) == 0 then
            checked(win.Error("MoveFileExW(crypto)", nil, destinationPath))
        end
        temporary = nil
        return true
    end)
    if destination then native.FsClose(destination) end
    if source then native.FsClose(source) end
    if temporary and k.DeleteFileW(temporary) == 0 then
        local _, detail, cleanupCode = win.Error("DeleteFileW(crypto temporary file)")
        if cleanupCode ~= 2 and type(result) == "table" then
            result.message = result.message .. "; temporary file cleanup failed: " .. detail
        end
    end
    return asResult(ok, result)
end

function M.EncryptFile(sourcePath, destinationPath, password, options)
    return fileCrypt(true, sourcePath, destinationPath, password, options)
end

function M.DecryptFile(sourcePath, destinationPath, password, options)
    return fileCrypt(false, sourcePath, destinationPath, password, options)
end
jit.off(fileCrypt, true)
jit.off(openCryptoTemp, true)

local function dataBlob(bytes)
    local blob = ffi.new("fw_data_blob[1]")
    blob[0].size = #bytes
    blob[0].data = ffi.cast("uint8_t *", bytes)
    return blob
end

local function dpapi(protect, bytes, entropy)
    if not validBytes(bytes) or (entropy ~= nil and not validBytes(entropy)) then
        return win.Error("Expected binary strings for DPAPI", 87)
    end
    local dll, err, code = win.Library("crypt32")
    if not dll then return nil, err, code end
    local input = dataBlob(bytes)
    local extra = entropy and dataBlob(entropy) or nil
    local out = ffi.new("fw_data_blob[1]")
    local operation = protect and dll.CryptProtectData or dll.CryptUnprotectData
    local ok = operation(input, nil, extra, nil, nil, 1, out)
    code = ok == 0 and tonumber(win.kernel.GetLastError())
    local result
    if out[0].data ~= nil then
        if ok ~= 0 then result = ffi.string(out[0].data, out[0].size) end
        if not protect then ffi.fill(out[0].data, out[0].size) end
        win.kernel.LocalFree(out[0].data)
    end
    if ok == 0 then return win.Error(protect and "CryptProtectData" or "CryptUnprotectData", code) end
    return result or ""
end
jit.off(dpapi, true)

function M.ProtectWindows(bytes, optionalEntropy) return dpapi(true, bytes, optionalEntropy) end
function M.UnprotectWindows(blob, optionalEntropy) return dpapi(false, blob, optionalEntropy) end
return M
