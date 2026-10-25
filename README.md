# LuaJIT Windows Modules

A collection of LuaJIT modules for Windows: Unicode strings and file operations,
processes, windows, the registry, the clipboard, keyboard and mouse input,
and system information. The modules access the Windows API through LuaJIT FFI.

## What is this library for?

Use these modules when a Windows LuaJIT script needs functionality beyond
standard Lua: Unicode file paths, native dialogs, process output capture,
registry access, or desktop automation. Each module can be required separately;
there is no central application object or mandatory framework initialization.
Keep the supporting modules alongside the modules you use so their dependencies
can be resolved by `require`.

Typical uses include:

- Small command-line tools that read and write files with Unicode names.
- Build helpers and launchers that start programs, wait for completion, and
  inspect exit codes or captured output.
- Windows administration scripts that inspect processes, environment variables,
  system paths, memory, and registry settings.
- Desktop utilities that inspect or control existing windows, use clipboard
  text, or send keyboard and mouse input.
- Applications that need a native file picker or a single-instance guard.

The modules use UTF-8 at their text interfaces and convert to UTF-16 where
required by Windows APIs. This does not change standard Lua's byte-oriented
string behavior or automatically make third-party programs' output UTF-8.
The library is Windows-specific and does not provide a widget toolkit or an
asynchronous event loop. Calls such as process waiting, sleep, and dialogs can
block the calling thread.

## Start with the examples

The [examples guide](examples/README.md) describes 12 runnable scripts, their
effects, and expected results. For example, from CMD in the repository root:

```bat
luajit examples\01_strings.lua
luajit examples\04_process.lua
luajit examples\05_system.lua
```

Each example locates the library relative to its own source file. You can also
launch an example by its full path from another working directory.

## Requirements

- Windows. The primary target is Windows 10/11 x64.
- LuaJIT with the `ffi`, `bit`, and `jit` modules.
- UTF-8 source files and UTF-8 strings for the modules' text APIs.

Standard Lua without FFI is not supported. LuaJIT, compilers, and third-party
DLLs are not included. `luv` is not required. Full compatibility with Windows
x86 has not been verified separately.

## Installation

Copy the `.lua` files into your application's directory, or add the library
directory to the module search paths using `setup_paths.lua`:

```lua
dofile("C:/Libraries/LuaJIT-Windows/setup_paths.lua")

local strings = require("strings")
local uio = require("unicode_io")

assert(strings.len("Hello") == 5)
assert(strings.upper("Hello") == "HELLO")
uio.print("Modules loaded")
```

Replace the path with your library location. `setup_paths.lua` prepends its
directory to `package.path` and `package.cpath` without changing the working
directory. Alternatively, put the modules next to your script, launch it from
that directory, and use `require` directly.

Run your script from CMD with `luajit.exe` available on `PATH`:

```bat
cd /d C:\Libraries\LuaJIT-Windows
luajit app.lua
```

`app.lua` is your own application script; it is not included.

## Modules

| Module | Purpose |
|---|---|
| `unicode_io` | Unicode paths, files, directories, encodings, console I/O, and commands |
| `strings` | UTF-8 length, substrings, case conversion, normalization, search, and replacement |
| `process` | Process creation, waiting, output capture, and process information |
| `window` | Finding and controlling existing windows, their properties, and geometry |
| `registry` | Reading, writing, and enumerating registry keys and values |
| `clipboard` | Clipboard text |
| `keyboard` | Key presses, shortcuts, text input, and key state |
| `mouse` | Coordinates, movement, buttons, and scrolling |
| `shell` | Opening files, folders, and URLs through the Windows shell |
| `system` | System directories, drives, memory, display, and Windows information |
| `env` | Environment variables of the current process |
| `argv` | The original Windows command line and its arguments in UTF-8 |
| `runtime` | The absolute script path and initial working directory |
| `lvars` | Paths, arguments, date, time, and other `L_*` values |
| `timer` | Measuring elapsed time in milliseconds |
| `single_instance` | Limiting an application to one running instance |
| `file_dialog` | Native file open, file save, and folder selection dialogs |
| `app_icon` | Setting and releasing icons for an existing window |
| `win_native` | Low-level Windows operations used by other modules |
| `win_types` | Shared Windows FFI type declarations; returns `ffi` |
| `win_constants` | Windows constants exposed through `ffi.C`; returns `ffi` |
| `setup_paths` | Module search path setup |

See the [function index](docs/API.md) for signatures extracted from the source.

## Usage

### Unicode file names

```lua
local uio = require("unicode_io")

-- U+00E9 encoded as UTF-8: the file name is cafe with an accented e.
local path = "caf\195\169.txt"
assert(uio.write_file(path, "Hello, world!\n"))
local text = assert(uio.read_file(path))
uio.print(text)
```

`write_file` creates or replaces the file. Specify `"BINARY"` for raw bytes;
text helpers default to UTF-8 when no encoding is supplied.
`require("unicode_io")` does not replace standard `io`, `os`, `loadfile`,
`dofile`, or the module loader. Call its functions through the returned table.
The explicit `uio.refresh_argv()` call updates the global `arg` table.

### Timing

```lua
local timer = require("timer")
timer.start(3)
local sum = 0
for i = 1, 1000000 do sum = sum + i end
print(assert(timer.stop()), "ms", sum)
```

### Single instance

```lua
require("single_instance")
-- Application code follows.
```

The key is derived from the normalized absolute entry script or executable
path. A second instance with the same key in the current Windows session exits
via `os.exit(0)` during `require`.

## Notes

- `runtime` and `lvars` require a nonempty script path in `arg[0]`. Prefer
  running a script file; an embedded host must set `arg[0]` explicitly.
  The host must supply a Unicode script path in UTF-8.
- `argv` reads the Windows command line. Its first element is the program path,
  not the first user argument.
- `window` controls existing windows; this collection does not include a full
  GUI backend.
- `file_dialog` and `app_icon` call `jit.off(true, true)` when loaded.
- Functions may return `nil, error` and sometimes an error code. Invalid
  arguments may raise exceptions. Consult the source for each function's contract.
- Window control and input depend on process privileges and desktop state.

## Publishing

See [GitHub publishing instructions](docs/GITHUB.md).

## License

[MIT License](LICENSE).
