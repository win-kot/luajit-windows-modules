local ffi = require("ffi")
local fs = require("fs")
local options = require("_options")
local str = require("str")
local win = require("_win_extension")

ffi.cdef[[
typedef struct fw_sqlite sqlite3;
typedef struct fw_sqlite_stmt sqlite3_stmt;
int sqlite3_open_v2(const char *, sqlite3 **, int, const char *);
int sqlite3_close_v2(sqlite3 *);
const char *sqlite3_errmsg(sqlite3 *);
const char *sqlite3_errstr(int);
int sqlite3_busy_timeout(sqlite3 *, int);
int sqlite3_prepare_v2(sqlite3 *, const char *, int, sqlite3_stmt **, const char **);
int sqlite3_finalize(sqlite3_stmt *);
int sqlite3_bind_parameter_count(sqlite3_stmt *);
int sqlite3_bind_null(sqlite3_stmt *, int);
int sqlite3_bind_int64(sqlite3_stmt *, int, int64_t);
int sqlite3_bind_double(sqlite3_stmt *, int, double);
int sqlite3_bind_text(sqlite3_stmt *, int, const char *, int, void *);
int sqlite3_bind_blob(sqlite3_stmt *, int, const void *, int, void *);
int sqlite3_step(sqlite3_stmt *);
int sqlite3_column_count(sqlite3_stmt *);
const char *sqlite3_column_name(sqlite3_stmt *, int);
int sqlite3_column_type(sqlite3_stmt *, int);
int64_t sqlite3_column_int64(sqlite3_stmt *, int);
double sqlite3_column_double(sqlite3_stmt *, int);
const char *sqlite3_column_text(sqlite3_stmt *, int);
const void *sqlite3_column_blob(sqlite3_stmt *, int);
int sqlite3_column_bytes(sqlite3_stmt *, int);
int sqlite3_changes(sqlite3 *);
int sqlite3_total_changes(sqlite3 *);
]]

local M = {NULL = {}}
local databases = setmetatable({}, {__mode = "k"})
local known = setmetatable({}, {__mode = "k"})
local blobs = setmetatable({}, {__mode = "k"})
local methods = {}
local transient = ffi.cast("void *", -1)
local library

local function failure(db, code)
    -- sqlite3_errmsg can quote SQL fragments and user-supplied trigger errors.
    local detail = library.sqlite3_errstr(code)
    return nil, ("Сбой SQLite (код %d)%s"):format(tonumber(code), detail ~= nil and (": " .. ffi.string(detail)) or ""), tonumber(code)
end

function M.Blob(bytes)
    if type(bytes) ~= "string" then return nil, "Требуется строка байт SQLite" end
    local blob = {}
    blobs[blob] = bytes
    return blob
end

function M.Open(path, opts)
    local optionError
    opts, optionError = options(opts, {readOnly = "boolean", busyTimeoutMs = "number"})
    if not opts then return nil, optionError end
    local timeout = opts.busyTimeoutMs or 1000
    if not win.Integer(timeout, 0, 0x7FFFFFFF) then return nil, "Недопустимое значение busyTimeoutMs" end
    if type(path) ~= "string" or path == "" or path:find("\0", 1, true) then return nil, "Недопустимый путь к базе SQLite" end
    if path ~= ":memory:" then
        local resolved, err, code = fs.PathAbsolute(path)
        if not resolved then return nil, err, code end
        path = resolved
    end
    if not library then
        local dir, err, code = fs.SystemDirGet()
        if not dir then return nil, err, code end
        local dll
        dll, err, code = win.Library(dir .. "\\winsqlite3.dll")
        if not dll then return nil, err, code end
        library = dll
    end
    local out = ffi.new("sqlite3 *[1]")
    local status = library.sqlite3_open_v2(path, out, opts.readOnly and 1 or 6, nil)
    local db = out[0]
    if status == 0 then status = library.sqlite3_busy_timeout(db, timeout) end
    if status ~= 0 then
        local _, err, code = failure(db, status)
        if db ~= nil then library.sqlite3_close_v2(db) end
        return nil, err, code
    end
    local object = setmetatable({}, {__index = methods})
    known[object] = true
    databases[object] = ffi.gc(db, library.sqlite3_close_v2)
    return object
end

function M.Close(object)
    if not known[object] then
        return nil, "invalid SQLite database", 21
    end
    local db = databases[object]
    if not db then return true end
    local status = library.sqlite3_close_v2(db)
    if status ~= 0 then return failure(db, status) end
    ffi.gc(db, nil)
    databases[object] = nil
    return true
end

local function bind(stmt, index, value)
    if value == M.NULL then return library.sqlite3_bind_null(stmt, index) end
    local blob = blobs[value]
    if blob then return library.sqlite3_bind_blob(stmt, index, blob, #blob, transient) end
    local kind = type(value)
    if kind == "string" and str.IsValidUtf8(value) then
        return library.sqlite3_bind_text(stmt, index, value, #value, transient)
    end
    if kind == "boolean" then return library.sqlite3_bind_int64(stmt, index, value and 1 or 0) end
    if ffi.istype("int64_t", value) or win.Integer(value, -9007199254740991, 9007199254740991) then
        return library.sqlite3_bind_int64(stmt, index, value)
    end
    if kind == "number" and value == value and math.abs(value) < math.huge then
        return library.sqlite3_bind_double(stmt, index, value)
    end
    return nil
end

local function column(stmt, index)
    local kind = library.sqlite3_column_type(stmt, index)
    if kind == 1 then return win.Exact(library.sqlite3_column_int64(stmt, index)) end
    if kind == 2 then return library.sqlite3_column_double(stmt, index) end
    if kind == 5 then return M.NULL end
    local ptr = kind == 3 and library.sqlite3_column_text(stmt, index) or library.sqlite3_column_blob(stmt, index)
    local size = library.sqlite3_column_bytes(stmt, index)
    return size == 0 and "" or ffi.string(ptr, size)
end

local function execute(object, sql, params, query)
    local db = databases[object]
    if not db then return nil, "SQLite database is closed or invalid", 21 end
    if type(sql) ~= "string" or sql:find("\0", 1, true) or not str.IsValidUtf8(sql) then return nil, "Требуется строка SQL в UTF-8 без нулевого байта" end
    if params == nil then params = {} end
    if type(params) ~= "table" then return nil, "Параметры SQL должны быть массивом" end
    local out, tail = ffi.new("sqlite3_stmt *[1]"), ffi.new("const char *[1]")
    local status = library.sqlite3_prepare_v2(db, sql, #sql + 1, out, tail)
    if status ~= 0 then return failure(db, status) end
    local stmt = out[0]
    if stmt == nil then return nil, "expected one SQL statement", 21 end
    ffi.gc(stmt, library.sqlite3_finalize)
    local function run()
        -- tail points into sql. Retain the Lua string until the offset has been read.
        local consumed = tonumber(tail[0] - ffi.cast("const char *", sql))
        if sql:find("%S", consumed + 1) then return nil, "only one SQL statement is allowed", 21 end
        local count = library.sqlite3_bind_parameter_count(stmt)
        local supplied = 0
        for index, value in next, params do
            if not win.Integer(index, 1, count) then return nil, "expected positional parameters array", 21 end
            local result = bind(stmt, index, value)
            if result == nil then return nil, "unsupported SQLite parameter at index " .. index, 20 end
            if result ~= 0 then return failure(db, result) end
            supplied = supplied + 1
        end
        if supplied ~= count then return nil, "SQL parameter count mismatch", 25 end
        local names = {}
        local seen = {}
        if query then
            for i = 0, library.sqlite3_column_count(stmt) - 1 do
                local name = library.sqlite3_column_name(stmt, i)
                if name == nil then return failure(db, 7) end
                names[i + 1] = ffi.string(name)
                if seen[names[i + 1]] then return nil, "duplicate column name; use SQL aliases", 21 end
                seen[names[i + 1]] = true
            end
        end
        local result = {}
        local changesBefore = library.sqlite3_total_changes(db)
        while true do
            local step = library.sqlite3_step(stmt)
            if step == 101 then
                if query then return result end
                return library.sqlite3_total_changes(db) == changesBefore and 0 or library.sqlite3_changes(db)
            end
            if step ~= 100 then return failure(db, step) end
            if query then
                local row = {}
                for i, name in ipairs(names) do row[name] = column(stmt, i - 1) end
                result[#result + 1] = row
            end
        end
    end
    local ok, result, err, code = pcall(run)
    local finalized = library.sqlite3_finalize(ffi.gc(stmt, nil))
    if not ok then error(result, 0) end
    if result ~= nil and finalized ~= 0 then return failure(db, finalized) end
    return result, err, code
end

function M.Exec(db, sql, params) return execute(db, sql, params, false) end
function M.Query(db, sql, params) return execute(db, sql, params, true) end
methods.Exec, methods.Query, methods.Close = M.Exec, M.Query, M.Close

return M
