# LuaJIT FrameWork 2.0

FrameWork is a library for LuaJIT 2.1 on Windows x64. It provides Unicode file
and string operations, native GUI controls, process management, IPC, HTTP, and
access to Windows APIs through LuaJIT FFI.

## Quick start

Install 64-bit LuaJIT and make `luajit.exe` available on PATH. From the
repository root, run these commands in CMD.

```bat
cd FrameWork
luajit Examples\01_str.lua
luajit Examples\02_files.lua
```

To use the library, create `demo.lua` in the package directory beside
`Reference.html`.

```lua
dofile("FrameWork\\setup_paths.lua")

local fs = require("fs")
local str = require("str")

local filename = "café.txt"
assert(fs.FileWrite(filename, "Hello, world!\n", "UTF-8"))
print(assert(fs.FileRead(filename, "UTF-8")))
assert(str.Len("café") == 4)
```

Save the script as UTF-8 and run `luajit demo.lua` from the package directory.
It writes `café.txt` to the current working directory. Use an absolute path to
`setup_paths.lua` when launching from elsewhere. Keep the Lua modules and the
two bundled DLLs together in `FrameWork/FrameWork/`.

## Modules

| Modules | Purpose |
| --- | --- |
| `setup_paths` | Add the library to LuaJIT's module and DLL search paths |
| `fs`, `path`, `zip` | Work with Unicode paths, files, directories, watches, and ZIP archives |
| `str`, `encoding` | Work with UTF-8 strings and convert between text encodings |
| `csv`, `ini`, `json`, `sqlite` | Read and write structured data and work with SQLite databases |
| `app`, `argv`, `env`, `l_vars`, `single_instance` | Access application paths, command-line arguments, environment variables, shared values, and instance guards |
| `process`, `ipc`, `sync` | Launch and inspect processes, communicate between processes, and synchronize work |
| `gui`, `window`, `file_dialog`, `app_icon`, `tray` | Create native interfaces, control windows, select files, and manage icons |
| `screen`, `monitor`, `image` | Capture the screen, inspect displays, and work with raster images |
| `clipboard`, `keyboard`, `mouse` | Access the clipboard and handle keyboard and mouse input |
| `http`, `network`, `url` | Make HTTP requests, inspect network settings, and encode URLs |
| `crypto`, `random`, `security` | Hash and encrypt data, generate random values, and inspect Windows security information |
| `audio`, `speech` | Work with audio and text-to-speech |
| `datetime`, `timer`, `logger` | Work with dates and times, measure elapsed time, and write logs |
| `registry`, `service`, `eventlog`, `power`, `shell` | Work with the Windows registry, services, event logs, power settings, and shell |
| `system`, `sys` | Inspect Windows, hardware, memory, and locale information |
| `cstring_buffer`, `win_constants`, `win_types` | Work with C string buffers, Windows constants, and FFI types |

## Documentation and tests

- Download the [English API reference](FrameWork/Reference.html) and open it in
  a browser for signatures, return values, error handling, and examples.
- Browse the [example scripts](FrameWork/Examples/) and
  [GUI tutorials](FrameWork/GUI%20Tutorials/). Each GUI tutorial includes a
  `run.cmd` launcher.
- Run `luajit tests\regression.lua` from the package directory to check the
  core APIs, SQLite, and ZIP support.

The [standalone module index](docs/API.md) and
[standalone examples](examples/README.md) cover the modules at the repository root.

## License

[MIT License](LICENSE).
