-- ZIP for Windows: Windows PowerShell 5.1 + .NET Framework.
-- UTF-8 paths; synchronous operations; compression is always Optimal.
local ffi = require('ffi')
local fs = require('fs')
local process = require('process')
local json = require('json')
local errors = require('_errors')
local win = require('_win_extension')
assert(ffi.os == 'Windows', 'zip requires Windows')
ffi.cdef[[
unsigned int __stdcall GetSystemDirectoryW(unsigned short *, unsigned int);
unsigned int __stdcall GetTempFileNameW(const unsigned short *, const unsigned short *, unsigned int, unsigned short *);
]]
local C = ffi.load('kernel32')
local M = {}

local Utf8 = win.FromWide
local function Wide(s)
    local wide, detail, code = win.ToWide(s)
    if not wide then return nil, detail, code end
    return wide
end
local function Path(s)
    if type(s) ~= 'string' or s == '' then return nil, 'Требуется непустой путь' end
    return fs.PathAbsolute(s)
end
local function TempFile(dir)
    local w, err, code = Wide(dir)
    if not w then return nil, err, code end
    local b = ffi.new('unsigned short[32768]')
    if C.GetTempFileNameW(w, Wide('LJZ'), 0, b) == 0 then
        return errors.Win32('GetTempFileNameW', nil, dir)
    end
    return Utf8(b)
end
local function Delete(path)
    if not path then return true end
    local wide, err, code = Wide(path)
    if not wide then return nil, err, code end
    if C.DeleteFileW(wide) == 0 then
        code = tonumber(C.GetLastError())
        if not errors.MissingPath(code) then return errors.Win32('удаление временного файла ZIP', code, path) end
    end
    return true
end
local function Options(overwrite, exclude, filesArgument)
    if overwrite ~= nil and type(overwrite) ~= 'boolean' then
        return nil, 'Third argument overwrite must be a boolean or nil'
    end
    if exclude == nil then exclude = {} end
    if type(exclude) ~= 'table' then return nil, (filesArgument or 'Fourth argument exclude') .. ' must be an array of patterns' end
    local count, patterns = 0, {}
    for k, pattern in pairs(exclude) do
        if type(k) ~= 'number' or k % 1 ~= 0 or k < 1 or k > #exclude then
            return nil, 'Exclude must be a dense array'
        end
        count = count + 1
        local w, err = Wide(pattern)
        if not w or pattern == '' then return nil, err or 'Empty exclusion pattern' end
        if pattern:find('[\r\n]') then return nil, 'Exclusion patterns must not contain newlines' end
        patterns[k] = pattern:gsub('\\', '/')
    end
    if count ~= #exclude then return nil, 'Exclude must be a dense array' end
    return {exclude = json.Array(patterns), overwrite = overwrite == true}
end

local HEADER = [=[
param([string]$settingsPath, [string]$errorLog)
$ErrorActionPreference = 'Stop'
try {
    $config = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($settingsPath))
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    & {
]=]
local FOOTER = [=[
    }
    [IO.File]::WriteAllText($errorLog, 'OK', [Text.UTF8Encoding]::new($false))
    exit 0
} catch {
    [IO.File]::WriteAllText($errorLog, $_.Exception.Message, [Text.UTF8Encoding]::new($false))
    exit 1
}
]=]

-- Scripts and logs are temporary runtime files, never shipped with the library.
local function RunScript(body, settings, internal)
    local sys = ffi.new('unsigned short[32768]')
    local n = C.GetSystemDirectoryW(sys, 32768)
    if n == 0 then return errors.Win32('GetSystemDirectoryW') end
    if n >= 32768 then return nil, 'Путь к системной папке слишком длинный' end
    local exe, err, code = Utf8(sys, n)
    if not exe then return nil, err, code end
    exe = exe .. '\\WindowsPowerShell\\v1.0\\powershell.exe'
    local tempDir; tempDir, err, code = fs.TempDirGet()
    if not tempDir then return nil, err, code end
    local log, scriptTemp, script
    log, err, code = TempFile(tempDir)
    if not log then return nil, err, code end
    scriptTemp, err, code = TempFile(tempDir)
    if not scriptTemp then Delete(log); return nil, err, code end
    script = scriptTemp .. '.ps1'
    if C.MoveFileExW((Wide(scriptTemp)), (Wide(script)), 0) == 0 then
        local _, message, status = errors.Win32('подготовку сценария ZIP', nil, script)
        Delete(scriptTemp); Delete(log); return nil, message, status
    end
    local config
    config, err, code = TempFile(tempDir)
    if not config then Delete(script); Delete(log); return nil, err, code end
    local function Cleanup()
        local deleted, message, status = Delete(script)
        local configDeleted, configMessage, configStatus = Delete(config)
        local logDeleted, logMessage, logStatus = Delete(log)
        if not deleted then return nil, message, status end
        if not configDeleted then return nil, configMessage, configStatus end
        return logDeleted, logMessage, logStatus
    end
    -- User paths and patterns are JSON data. The .ps1 contains only library code.
    local skipped = {script, config, log}
    for _, path in ipairs(internal or {}) do skipped[#skipped + 1] = path end
    settings.internal = skipped
    local data
    data, err = json.Encode(settings)
    if not data then Cleanup(); return nil, err end
    local written
    written, err, code = fs.FileWriteBytes(config, data)
    if not written then Cleanup(); return nil, err, code end
    written, err, code = fs.FileWriteBytes(script, '\239\187\191' .. HEADER .. body .. FOOTER)
    if not written then Cleanup(); return nil, err, code end
    local result
    result, err, code = process.Exec(exe, {'-NoLogo', '-NoProfile', '-NonInteractive',
        '-ExecutionPolicy', 'Bypass', '-File', script, config, log}, nil, {hidden = true})
    if not result then Cleanup(); return nil, err, code end
    if result.exitCode ~= 0 then
        local detail = fs.FileRead(log, 'UTF-8') or ''
        if detail == '' then detail = result.stderr or '' end
        Cleanup()
        return nil, 'Сбой операции ZIP; код завершения PowerShell: ' .. result.exitCode
            .. (detail ~= '' and (':\n' .. detail) or ''), result.exitCode
    end
    local completion
    completion, err, code = fs.FileRead(log, 'UTF-8')
    if completion ~= 'OK' then
        Cleanup()
        return nil, err or 'PowerShell завершился без подтверждения операции ZIP', code
    end
    return Cleanup()
end

local CREATE = [=[
    $patterns = @($config.exclude | ForEach-Object {
        [System.Management.Automation.WildcardPattern]::new($_,
            [System.Management.Automation.WildcardOptions]::IgnoreCase)
    })
    function Excluded($name, $relative) {
        foreach ($p in $patterns) {
            if ($p.IsMatch($name) -or $p.IsMatch($relative)) { return $true }
        }
        return $false
    }
    function SelectedForCreate($relative, $isDir) {
        if ($null -eq $createSelection) { return $true }
        foreach ($selected in $createSelection) {
            if ([StringComparer]::OrdinalIgnoreCase.Equals($relative, $selected.Relative)) { return $true }
            if ($selected.IsDir -and $relative.StartsWith($selected.Relative + '/', [StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
            if ($isDir -and $selected.Relative.StartsWith($relative + '/', [StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }
        return $false
    }
    function AddFolder($folder, $relative, $zipPrefix) {
        foreach ($item in ([IO.DirectoryInfo]::new($folder)).GetFileSystemInfos()) {
            if ($config.internal -icontains $item.FullName) { continue }
            $entry = $relative + $item.Name
            if (Excluded $item.Name $entry) { continue }
            $isDir = ($item.Attributes -band [IO.FileAttributes]::Directory) -ne 0
            if (-not (SelectedForCreate $entry $isDir)) { continue }
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw ('Symbolic links and junctions are not supported: ' + $item.FullName)
            }
            if (($item.Attributes -band [IO.FileAttributes]::Directory) -ne 0) {
                $null = $zip.CreateEntry($zipPrefix + $entry + '/')
                AddFolder $item.FullName ($entry + '/') $zipPrefix
            } else {
                $null = [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                    $zip, $item.FullName, ($zipPrefix + $entry), [IO.Compression.CompressionLevel]::Optimal)
            }
        }
    }
    $stream = [IO.File]::Open($config.archive, [IO.FileMode]::Create, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create,
            $true, [Text.Encoding]::UTF8)
        try {
            if ($config.sourceType -eq 'file') {
                if ([StringComparer]::OrdinalIgnoreCase.Equals(
                    [IO.Path]::GetFullPath($config.source), [IO.Path]::GetFullPath($config.finalArchive))) {
                    throw 'Source file and ZIP archive must be different paths'
                }
                if (Excluded $config.rootName $config.rootName) {
                    throw ('Source file is excluded: ' + $config.rootName)
                }
                $file = [IO.FileInfo]::new($config.source)
                if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw ('Symbolic links are not supported: ' + $config.source)
                }
                $null = [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                    $zip, $config.source, $config.rootName, [IO.Compression.CompressionLevel]::Optimal)
            } else {
                if (([IO.File]::GetAttributes($config.source) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw ('Symbolic links and junctions are not supported: ' + $config.source)
                }
                $zipPrefix = $config.rootName + '/'
                $null = $zip.CreateEntry($zipPrefix)
                AddFolder $config.source '' $zipPrefix
            }
        } finally { $zip.Dispose() }
    } finally { $stream.Dispose() }
]=]

-- Internal archive writer; selection contains validated literal relative paths.
-- source may be a single file or a directory.
-- Returns true, or nil, message, [PowerShell exit code].
local function Create(source, archive, overwrite, exclude, selection)
    local opts, err = Options(overwrite, exclude, 'Fifth argument files')
    local code
    if not opts then return nil, err end
    source, err, code = Path(source)
    if not source then return nil, err, code end
    archive, err, code = Path(archive)
    if not archive then return nil, err, code end
    local sourceInfo; sourceInfo, err, code = fs.FileGetInfo(source)
    if not sourceInfo then return nil, err, code end
    local isFile = sourceInfo.is_file
    if selection and isFile then return nil, 'Create include source must be a directory' end
    local cleanSource = source:gsub('[\\/]+$', '')
    local rootName = fs.PathBaseName(cleanSource)
    if not rootName or rootName == '' or rootName:find(':', 1, true) then
        return nil, 'Source must be a named file or directory, not a drive root'
    end
    if isFile and source:lower() == archive:lower() then
        return nil, 'Source file and ZIP archive must be different paths'
    end
    if archive:find('[\\/]$') then return nil, 'Archive must be a file path' end
    local parent = fs.PathDirName(archive)
    local parentInfo; parentInfo, err, code = fs.FileGetInfo(parent)
    if not parentInfo then return nil, err, code end
    if not parentInfo.is_dir then return nil, 'Родительский путь архива не является папкой: ' .. parent end
    local existing; existing, err, code = fs.FileGetInfo(archive)
    if not existing and not errors.MissingPath(code) then return nil, err, code end
    if existing and existing.is_dir then return nil, 'Путь архива указывает на папку: ' .. archive end
    if existing and not opts.overwrite then return nil, 'Архив уже существует: ' .. archive end
    local temp
    temp, err, code = TempFile(parent)
    if not temp then return nil, err, code end
    local ok
    local body = CREATE
    if selection then
        body = [=[
    $createSelection = [Collections.Generic.List[object]]::new()
    foreach ($relative in $config.selection) {
        $target = [IO.Path]::GetFullPath([IO.Path]::Combine($config.source, $relative))
        if ([StringComparer]::OrdinalIgnoreCase.Equals($target, $config.finalArchive)) {
            throw ('Selected file is the output archive: ' + $relative)
        }
        # GetAttributes throws when a selected file or directory is missing.
        $attr = [IO.File]::GetAttributes($target)
        $createSelection.Add([PSCustomObject]@{
            Relative=$relative; IsDir=(($attr -band [IO.FileAttributes]::Directory) -ne 0)
        })
    }
]=] .. CREATE
    end
    ok, err, code = RunScript(body, {
        source = source, archive = temp, rootName = rootName,
        sourceType = isFile and 'file' or 'directory', finalArchive = archive,
        selection = selection, exclude = opts.exclude, overwrite = opts.overwrite
    }, {archive, temp})
    if not ok then Delete(temp); return nil, err, code end
    if C.MoveFileExW((Wide(temp)), (Wide(archive)), opts.overwrite and 1 or 0) == 0 then
        local _, message, status = errors.Win32('сохранение архива', nil, archive)
        Delete(temp); return nil, message, status
    end
    return true
end

local function Selection(files)
    if type(files) ~= 'table' then
        return nil, 'Fifth argument files must be a nonempty array of relative paths in include mode'
    end
    local count, names = 0, {}
    for key, name in pairs(files) do
        if type(key) ~= 'number' or key % 1 ~= 0 or key < 1 or key > #files then
            return nil, 'Files must be a nonempty dense array'
        end
        count = count + 1
        local wide, err = Wide(name)
        if not wide or name == '' then return nil, err or 'Selected path must not be empty' end
        name = name:gsub('\\', '/')
        if name:sub(1, 1) == '/' or name:find('[<>:"|?*%c]') then
            return nil, 'Expected a literal relative path: ' .. name
        end
        name = name:gsub('/+$', '')
        if name == '' or name:find('//', 1, true) then
            return nil, 'Invalid relative path: ' .. name
        end
        for part in name:gmatch('[^/]+') do
            if part == '.' or part == '..' or part:find('[ .]$') then
                return nil, 'Invalid relative path component: ' .. part
            end
        end
        names[key] = name
    end
    if count == 0 or count ~= #files then return nil, 'Files must be a nonempty dense array' end
    return names
end

-- Create(source, archive, overwrite = false, mode = "exclude", files = {}).
-- mode="exclude": archive everything except matching names/paths/patterns.
-- mode="include": archive only listed relative files/directories (no wildcards).
-- Listed directories include all descendants; overlapping paths are not duplicated.
function M.Create(source, archive, overwrite, mode, files)
    if overwrite ~= nil and type(overwrite) ~= 'boolean' then
        return nil, 'Third argument overwrite must be a boolean or nil'
    end
    if mode ~= nil and mode ~= 'include' and mode ~= 'exclude' then
        return nil, 'Create fourth argument mode must be "include", "exclude", or nil'
    end
    if mode == 'include' then
        local selection, err = Selection(files)
        if not selection then return nil, err end
        return Create(source, archive, overwrite, nil, selection)
    end
    return Create(source, archive, overwrite, files)
end

local CHECK_DISK_PATH = [=[
    function CheckDiskPath($path) {
        $current = $path
        while ($current) {
            try { $attr = [IO.File]::GetAttributes($current) }
            catch [IO.FileNotFoundException] { $attr = $null }
            catch [IO.DirectoryNotFoundException] { $attr = $null }
            if ($null -ne $attr) {
                if (($attr -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw ('Destination contains a symbolic link or junction: ' + $current)
                }
                if ($current -ne $path -and ($attr -band [IO.FileAttributes]::Directory) -eq 0) {
                    throw ('Destination parent is a file: ' + $current)
                }
            }
            $parent = [IO.Path]::GetDirectoryName($current)
            if ($parent -eq $current) { break }
            $current = $parent
        }
    }
]=]

local VERIFY_DATA = [=[
    # The embedded .NET Framework assembly verifies ZIP length and CRC32.
    # Rebuild it from Tools/LjZipIntegrity.cs with Tools/UpdateZipIntegrity.ps1.
    $integrityAssembly = @'
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
EwAAAAQAAAACAAAABwAAAAcAAAAWAAAACQAAAAMAAAABAAAAAgAAAAAAZwEBAAAAAAAGAAABAQIG
ACABAQIGANQA7gEPACECAAAGAKEAAQIGADQBhQEGAFsChQEGALwAhQEGAGwChQEGAHoBPQAGAMcB
PQAGAH4BPQAGAA4AhQEKALIBPQAGAHwAPQAGAEMBhQEGANQBhQEGAHAAhQEGAD4BhQEAAAAANAAA
AAAAAQABAAABEACPADoCGQABAAEAAAEQAOgAAQIZAAEAAgCBARAAiwIAACUAAgADACYAkAGbADEA
agCeAFAgAAAAAIYY4QEGAAEAWCAAAAAAhhjhAQEAAQBoIAAAAACRAGUAogABALUgAAAAAJEAqQGn
AAEA0CAAAAAAlgBRAqwAAgD0IwAAAACWAIYCswAEAIkkAAAAAJEY5wG9AAgAAAABAMUBAAABAEgB
AAACAHMCAAABAHkCAAACAH8CAAADAFgBAAAEAFAACQDhAQEAEQDhAQYAGQDhAQoAKQDhAQYAQQDh
ARAAMQDhAQYAcQDhAR4AeQBcAD4AWQDhAUQAYQBNAUoAgQCMAU4AYQClAVQAWQAwAlkAiQAMAF8A
iQArAGYAWQABAG0AWQAVAHEAWQAgAHUAYQCYAUoAkQCBAAYAYQCJAIIAYQBgAIoAJwASAB4BLgAL
AMEALgATAMoALgAbAOkAQwAjAPIAQwAKAPIAYwAjAPIAYwAKAPIAYwArAPcAFgAjAHkABIAAAAAA
AAAAAAAAAAAAAAAAiwIAAAQAAAAAAAAAAAAAAJIARwAAAAAABAAAAAAAAAAAAAAAkgCFAQAAAAAA
AABSZWFkVUludDMyAFRvVUludDMyAFJlYWRVSW50NjQAUmVhZFVJbnQxNgBUb1VJbnQxNgA8TW9k
dWxlPgBTeXN0ZW0uSU8AbXNjb3JsaWIAZXhwZWN0ZWRDcmMAT3BlblJlYWQAQnVpbGRUYWJsZQBJ
RGlzcG9zYWJsZQBGaWxlAERpc3Bvc2UAV3JpdGUARW1iZWRkZWRBdHRyaWJ1dGUAQ29tcGlsZXJH
ZW5lcmF0ZWRBdHRyaWJ1dGUAQXR0cmlidXRlVXNhZ2VBdHRyaWJ1dGUARGVidWdnYWJsZUF0dHJp
YnV0ZQBSZWZTYWZldHlSdWxlc0F0dHJpYnV0ZQBDb21waWxhdGlvblJlbGF4YXRpb25zQXR0cmli
dXRlAFJ1bnRpbWVDb21wYXRpYmlsaXR5QXR0cmlidXRlAEJ5dGUATWF0aABwYXRoAGdldF9MZW5n
dGgAZXhwZWN0ZWRMZW5ndGgATGpaaXBJbnRlZ3JpdHkuZGxsAEZpbGVTdHJlYW0AU3lzdGVtAE1p
bgBWZXJzaW9uAGdldF9Qb3NpdGlvbgBzZXRfUG9zaXRpb24ASW52YWxpZERhdGFFeGNlcHRpb24A
QmluYXJ5UmVhZGVyAEJpdENvbnZlcnRlcgAuY3RvcgAuY2N0b3IAU3lzdGVtLkRpYWdub3N0aWNz
AFN5c3RlbS5SdW50aW1lLkNvbXBpbGVyU2VydmljZXMARGVidWdnaW5nTW9kZXMAUmVhZEJ5dGVz
AE1pY3Jvc29mdC5Db2RlQW5hbHlzaXMAQ2hlY2tzdW1zAEF0dHJpYnV0ZVRhcmdldHMAT2JqZWN0
AGNvdW50AGlucHV0AG91dHB1dABDb3B5AExqWmlwSW50ZWdyaXR5AAAAAC9aAEkAUAAgAG8AZgBm
AHMAZQB0ACAAaQBzACAAdABvAG8AIABsAGEAcgBnAGUAADFaAEkAUAAgAGUAbgBkACAAcgBlAGMA
bwByAGQAIABuAG8AdAAgAGYAbwB1AG4AZAAAQ00AdQBsAHQAaQAtAHYAbwBsAHUAbQBlACAAWgBJ
AFAAIABpAHMAIABuAG8AdAAgAHMAdQBwAHAAbwByAHQAZQBkAAElSQBuAHYAYQBsAGkAZAAgAFoA
SQBQADYANAAgAGQAaQBzAGsAAEdNAHUAbAB0AGkALQB2AG8AbAB1AG0AZQAgAFoASQBQADYANAAg
AGkAcwAgAG4AbwB0ACAAcwB1AHAAcABvAHIAdABlAGQAATFJAG4AdgBhAGwAaQBkACAAWgBJAFAA
NgA0ACAAZQBuAGQAIAByAGUAYwBvAHIAZAAAM0kAbgB2AGEAbABpAGQAIABaAEkAUAA2ADQAIABl
AG4AdAByAHkAIABjAG8AdQBuAHQAADtJAG4AdgBhAGwAaQBkACAAWgBJAFAAIABjAGUAbgB0AHIA
YQBsACAAZABpAHIAZQBjAHQAbwByAHkAADNJAG4AdgBhAGwAaQBkACAAWgBJAFAAIABjAGUAbgB0
AHIAYQBsACAAZQBuAHQAcgB5AAA3VAByAHUAbgBjAGEAdABlAGQAIABaAEkAUAAgAGMAZQBuAHQA
cgBhAGwAIABlAG4AdAByAHkAAC9aAEkAUAAgAGUAbgB0AHIAeQAgAHMAaQB6AGUAIABtAGkAcwBt
AGEAdABjAGgAADFaAEkAUAAgAGUAbgB0AHIAeQAgAEMAUgBDADMAMgAgAG0AaQBzAG0AYQB0AGMA
aAAAAAAAgR35vZlFV0WGh1XLojD14AAEIAEBCAMgAAEFIAEBEREFIAEBER0HBwQdCQkJCAQgAQEO
GgcTEikSLQgdBQgKCwsLCgoKHQkKCAgICB0JBQABEikOBSABARIxAyAACgUAAgoKCgQgAQEKBSAB
HQUIBgACCR0FCAYAAgcdBQgDIAAJAyAACwMgAAcIBwUdBQoJCAgHIAMBHQUICAcgAwgdBQgICLd6
XFYZNOCJAgYIAwYdCQQAAB0JBAABCgsGAAIdCQ4ICQAEARIxEjEKCQMAAAEIAQAIAAAAAAAeAQAB
AFQCFldyYXBOb25FeGNlcHRpb25UaHJvd3MBCAEAAgAAAAAABAEAAAAmAQACAAAAAgBUAg1BbGxv
d011bHRpcGxlAFQCCUluaGVyaXRlZAAIAQALAAAAAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAA
AAAAADQuAAAAAAAAAAAAAE4uAAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAABALgAAAAAAAAAAAAAA
AF9Db3JEbGxNYWluAG1zY29yZWUuZGxsAAAAAAD/JQAgABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAABABAAAAAYAACAAAAAAAAAAAAAAAAAAAABAAEAAAAwAACAAAAAAAAAAAAAAAAAAAABAAAA
AABIAAAAWEAAAGQCAAAAAAAAAAAAAGQCNAAAAFYAUwBfAFYARQBSAFMASQBPAE4AXwBJAE4ARgBP
AAAAAAC9BO/+AAABAAAAAAAAAAAAAAAAAAAAAAA/AAAAAAAAAAQAAAACAAAAAAAAAAAAAAAAAAAA
RAAAAAEAVgBhAHIARgBpAGwAZQBJAG4AZgBvAAAAAAAkAAQAAABUAHIAYQBuAHMAbABhAHQAaQBv
AG4AAAAAAAAAsATEAQAAAQBTAHQAcgBpAG4AZwBGAGkAbABlAEkAbgBmAG8AAACgAQAAAQAwADAA
MAAwADAANABiADAAAAAsAAIAAQBGAGkAbABlAEQAZQBzAGMAcgBpAHAAdABpAG8AbgAAAAAAIAAA
ADAACAABAEYAaQBsAGUAVgBlAHIAcwBpAG8AbgAAAAAAMAAuADAALgAwAC4AMAAAAEYAEwABAEkA
bgB0AGUAcgBuAGEAbABOAGEAbQBlAAAATABqAFoAaQBwAEkAbgB0AGUAZwByAGkAdAB5AC4AZABs
AGwAAAAAACgAAgABAEwAZQBnAGEAbABDAG8AcAB5AHIAaQBnAGgAdAAAACAAAABOABMAAQBPAHIA
aQBnAGkAbgBhAGwARgBpAGwAZQBuAGEAbQBlAAAATABqAFoAaQBwAEkAbgB0AGUAZwByAGkAdAB5
AC4AZABsAGwAAAAAADQACAABAFAAcgBvAGQAdQBjAHQAVgBlAHIAcwBpAG8AbgAAADAALgAwAC4A
MAAuADAAAAA4AAgAAQBBAHMAcwBlAG0AYgBsAHkAIABWAGUAcgBzAGkAbwBuAAAAMAAuADAALgAw
AC4AMAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgAAAMAAAAYD4A
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
'@
    $null = [Reflection.Assembly]::Load([Convert]::FromBase64String($integrityAssembly))
]=]


local EXTRACT = CHECK_DISK_PATH .. VERIFY_DATA .. [=[
    function CompileExtractPatterns($patterns) {
        foreach ($pattern in $patterns) {
            $folder = $pattern.EndsWith('/')
            $path = if ($folder) { $pattern.Substring(0, $pattern.Length - 1) } else { $pattern }
            $byName = -not $path.Contains('/') -and ($path.Contains('*') -or $path.Contains('?'))
            # Escape everything first so only * and ? act as wildcards.
            $character = '(?:[\uD800-\uDBFF][\uDC00-\uDFFF]|[^/\uD800-\uDFFF])'
            $glob = [regex]::Escape($path).Replace('\*', '[^/]*').Replace('\?', $character)
            $flags = [Text.RegularExpressions.RegexOptions]'IgnoreCase, CultureInvariant'
            [PSCustomObject]@{
                Folder=$folder; ByName=$byName; Regex=[regex]::new(('\A' + $glob + '\z'), $flags)
            }
        }
    }
    function MatchesExtractPatterns($patterns, $relative, $isDir) {
        foreach ($pattern in $patterns) {
            $candidate = $relative
            if ($pattern.Folder -and -not $isDir) {
                $candidate = $relative.Substring(0, $relative.LastIndexOf('/') + 1).TrimEnd('/')
            }
            while ($candidate) {
                $value = if ($pattern.ByName) {
                    $candidate.Substring($candidate.LastIndexOf('/') + 1)
                } else { $candidate }
                if ($pattern.Regex.IsMatch($value)) { return $true }
                $separator = $candidate.LastIndexOf('/')
                if (-not $pattern.Folder -or $separator -lt 0) { break }
                $candidate = $candidate.Substring(0, $separator)
            }
        }
        return $false
    }
    $includes = @(CompileExtractPatterns $config.include)
    $excludes = @(CompileExtractPatterns $config.exclude)
    CheckDiskPath $config.destination
    if ([IO.File]::Exists($config.destination)) { throw 'Destination is a file' }
    $separator = [IO.Path]::DirectorySeparatorChar
    $root = $config.destination.TrimEnd($separator) + $separator
    $seen = [Collections.Generic.Dictionary[string,bool]]::new([StringComparer]::OrdinalIgnoreCase)
    $plan = [Collections.Generic.List[object]]::new()
    $zip = [IO.Compression.ZipFile]::OpenRead($config.archive)
    try {
        $checksums = [LjZipIntegrity]::Checksums($config.archive, $zip.Entries.Count)
        $entryIndex = -1
        foreach ($entry in $zip.Entries) {
            $entryIndex++
            $relative = $entry.FullName.Replace('\', '/')
            while ($relative.StartsWith('./')) { $relative = $relative.Substring(2) }
            if ($relative -eq '' -and $entry.FullName.EndsWith('/')) { continue }
            $isDir = ($relative.EndsWith('/') -or ($entry.ExternalAttributes -band 16) -ne 0 -or
                ($entry.ExternalAttributes -band 0xF0000000) -eq 0x40000000)
            if ($relative.EndsWith('/')) { $relative = $relative.Substring(0, $relative.Length - 1) }
            if ($null -ne $config.include -and -not (MatchesExtractPatterns $includes $relative $isDir)) { continue }
            if (MatchesExtractPatterns $excludes $relative $isDir) { continue }
            if (-not $relative -or $relative.StartsWith('/') -or $relative -match '[<>:"|?*\x00-\x1f]') {
                throw ('Unsafe ZIP entry: ' + $entry.FullName)
            }
            $parts = $relative.Split('/')
            foreach ($part in $parts) {
                if ($part -eq '' -or $part -eq '.' -or $part -eq '..' -or $part -match '[ .]$' -or
                    $part -match '^(CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³])(\.|$)') {
                    throw ('Unsafe ZIP entry: ' + $entry.FullName)
                }
            }
            if ((($entry.ExternalAttributes -shr 16) -band 0xf000) -eq 0xa000) {
                throw ('ZIP symbolic links are not supported: ' + $entry.FullName)
            }
            if ($seen.ContainsKey($relative)) { throw ('Duplicate ZIP entry: ' + $relative) }
            $seen.Add($relative, $isDir)
            $target = [IO.Path]::GetFullPath([IO.Path]::Combine($root, $relative))
            if (-not $target.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
                throw ('ZIP entry escapes destination: ' + $relative)
            }
            if ([StringComparer]::OrdinalIgnoreCase.Equals($target, $config.archive)) {
                throw 'An entry would overwrite the source ZIP'
            }
            CheckDiskPath $target
            if ($isDir) {
                if ([IO.File]::Exists($target)) { throw ('Directory conflicts with file: ' + $target) }
            } else {
                if ([IO.Directory]::Exists($target)) { throw ('File conflicts with directory: ' + $target) }
                if (-not $config.overwrite -and [IO.File]::Exists($target)) { throw ('File already exists: ' + $target) }
            }
            $plan.Add([PSCustomObject]@{Entry=$entry; Target=$target; Relative=$relative; IsDir=$isDir; Crc=$checksums[$entryIndex]})
        }
        if ($plan.Count -eq 0) { return }
        # Validate file/directory conflicts across the extraction plan before writing.
        foreach ($item in $plan) {
            $parent = $item.Relative
            while ($parent.Contains('/')) {
                $parent = $parent.Substring(0, $parent.LastIndexOf('/'))
                if ($seen.ContainsKey($parent) -and -not $seen[$parent]) {
                    throw ('ZIP file is also used as a directory: ' + $parent)
                }
            }
        }
        $null = [IO.Directory]::CreateDirectory($config.destination)
        foreach ($item in $plan) {
            CheckDiskPath $item.Target
            if ($item.IsDir) {
                $null = [IO.Directory]::CreateDirectory($item.Target)
                continue
            }
            $dir = [IO.Path]::GetDirectoryName($item.Target)
            $null = [IO.Directory]::CreateDirectory($dir)
            $temp = [IO.Path]::Combine($dir, 'LJZ-' + [Guid]::NewGuid().ToString('N') + '.tmp')
            $output = [IO.File]::Open($temp, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try {
                try {
                    $input = $item.Entry.Open()
                    try { [LjZipIntegrity]::Copy($input, $output, $item.Entry.Length, $item.Crc) } finally { $input.Dispose() }
                } finally { $output.Dispose() }
                [IO.File]::SetLastWriteTimeUtc($temp, $item.Entry.LastWriteTime.UtcDateTime)
                CheckDiskPath $item.Target
                if ([IO.File]::Exists($item.Target) -and $config.overwrite) {
                    [IO.File]::Replace($temp, $item.Target, [NullString]::Value)
                } else { [IO.File]::Move($temp, $item.Target) }
                $temp = $null
            } finally {
                if ($null -ne $temp) { [IO.File]::Delete($temp) }
            }
        }
    } finally { $zip.Dispose() }
]=]

local function ExtractPatterns(patterns, name)
    if type(patterns) ~= 'table' then return nil, name .. ' must be an array of patterns' end
    local count, normalized = 0, {}
    for key, pattern in pairs(patterns) do
        if type(key) ~= 'number' or key % 1 ~= 0 or key < 1 or key > #patterns then
            return nil, name .. ' must be a dense array'
        end
        local w, err = Wide(pattern)
        if not w then return nil, name .. '[' .. key .. ']: ' .. err end
        pattern = pattern:gsub('\\', '/')
        while pattern:sub(1, 2) == './' do pattern = pattern:sub(3) end
        if pattern == '' or pattern:sub(1, 1) == '/' or pattern:find('//', 1, true)
            or pattern:find('[<>:"|%c]') then
            return nil, name .. '[' .. key .. '] must be a relative ZIP path or pattern'
        end
        for part in pattern:gmatch('[^/]+') do
            if part == '.' or part == '..' then
                return nil, name .. '[' .. key .. '] must be a relative ZIP path or pattern'
            end
        end
        normalized[key] = pattern
        count = count + 1
    end
    if count ~= #patterns then return nil, name .. ' must be a dense array' end
    return json.Array(normalized)
end

-- A trailing slash selects a folder and its descendants. Exclusions win.
-- Paths stay relative to the archive root. Completed files are not rolled back.
function M.Extract(archive, destination, options)
    if options == nil then options = {} end
    if type(options) ~= 'table' then return nil, 'Third argument options must be a table or nil' end
    for key in pairs(options) do
        if key ~= 'include' and key ~= 'exclude' and key ~= 'overwrite' then
            return nil, 'Unknown ZIP extraction option: ' .. tostring(key)
        end
    end
    if options.overwrite ~= nil and type(options.overwrite) ~= 'boolean' then
        return nil, 'options.overwrite must be a boolean or nil'
    end
    local include, exclude, err, code
    if options.include ~= nil then
        include, err = ExtractPatterns(options.include, 'options.include')
        if not include then return nil, err end
    end
    if options.exclude ~= nil then
        exclude, err = ExtractPatterns(options.exclude, 'options.exclude')
        if not exclude then return nil, err end
    end
    archive, err, code = Path(archive)
    if not archive then return nil, err, code end
    destination, err, code = Path(destination)
    if not destination then return nil, err, code end
    local info; info, err, code = fs.FileGetInfo(archive)
    if not info then return nil, err, code end
    if not info.is_file then return nil, 'Путь архива указывает на папку: ' .. archive end
    local ok; ok, err, code = RunScript(EXTRACT, {
        archive = archive, destination = destination, include = include, exclude = exclude,
        overwrite = options.overwrite == true
    })
    if not ok then return errors.Context("Распаковка [" .. archive .. "] в [" .. destination .. "] не завершена", err, code) end
    return true
end

local LIST = [=[
    $stream = [IO.File]::OpenRead($config.archivePath)
    try {
        $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Read)
        try {
            $entries = @(
                foreach ($entry in $zip.Entries) {
                    [PSCustomObject]@{
                        name = $entry.FullName
                        isDir = ($entry.FullName.EndsWith('/') -or $entry.FullName.EndsWith('\') -or
                            ($entry.ExternalAttributes -band 16) -ne 0 -or
                            ($entry.ExternalAttributes -band 0xF0000000) -eq 0x40000000)
                        size = $entry.Length.ToString([Globalization.CultureInfo]::InvariantCulture)
                        compressedSize = $entry.CompressedLength.ToString([Globalization.CultureInfo]::InvariantCulture)
                    }
                }
            )
            $json = ConvertTo-Json -InputObject $entries -Compress
            [IO.File]::WriteAllText($config.listingPath, $json, [Text.UTF8Encoding]::new($false))
        } finally { $zip.Dispose() }
    } finally { $stream.Dispose() }
]=]

local function exactSize(value)
    local limit = "9007199254740991"
    if #value < #limit or (#value == #limit and value <= limit) then return tonumber(value) end
    return value
end

function M.List(archive)
    local path, err, code = Path(archive)
    if not path then return nil, err, code end
    local info; info, err, code = fs.FileGetInfo(path)
    if not info then return nil, err, code end
    if not info.is_file then return nil, "Путь архива указывает на папку: " .. path end
    local directory
    directory, err, code = fs.TempDirGet()
    if not directory then return nil, err, code end
    local output
    output, err, code = TempFile(directory)
    if not output then return nil, err, code end
    local ok
    ok, err, code = RunScript(LIST, {archivePath = path, listingPath = output})
    local raw
    if ok then raw, err, code = fs.FileRead(output, "BINARY") end
    local deleted, deleteError, deleteCode = Delete(output)
    if not raw then return nil, err, code end
    if not deleted then return nil, deleteError, deleteCode end
    local entries
    entries, err = json.Decode(raw)
    if not entries then return errors.Context("Не удалось прочитать список файлов ZIP [" .. path .. "]", err) end
    for _, entry in ipairs(entries) do
        entry.size = exactSize(entry.size)
        entry.compressedSize = exactSize(entry.compressedSize)
    end
    -- Remove json.Array's marker, including for an empty archive.
    return setmetatable(entries, nil)
end

return M
