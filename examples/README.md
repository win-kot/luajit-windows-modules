# Usage Examples

These scripts demonstrate common tasks using the modules in the repository
root. They require Windows and LuaJIT. No installation step or additional
DLL download is needed when LuaJIT and its built-in modules are available.

Run commands below in CMD from the repository root. Replace `luajit` with
the full quoted path to `luajit.exe` if it is not on `PATH`.

```bat
luajit examples\01_strings.lua
```

Each script adds the library directory to the module search paths using
`setup_paths.lua`, resolved relative to the script itself. Keep the directory
structure intact. The numbered scripts are independent; there is no need to
run them in order.

## Available scripts

| Script | Demonstrates | Effects |
|---|---|---|
| [01_strings.lua](01_strings.lua) | UTF-8 bytes versus code points, uppercase, substrings, and timing | Prints text and timing |
| [02_files.lua](02_files.lua) | Creating a directory, writing and reading a Unicode file name | Creates a file and leaves it for inspection |
| [03_environment.lua](03_environment.lua) | Reading, expanding, setting, and restoring environment variables | Temporarily changes one variable in the current process |
| [04_process.lua](04_process.lua) | Command construction, output capture, timeout, and exit code | Starts `cmd.exe` with a fixed `echo` command |
| [05_system.lua](05_system.lua) | Computer name, paths, and physical memory | Reads system information |
| [06_windows.lua](06_windows.lua) | Listing visible windows matching a title substring | Reads window titles |
| [07_registry.lua](07_registry.lua) | Reading a registry value and handling missing values | Reads one value; does not write |
| [08_clipboard.lua](08_clipboard.lua) | Detecting and reading clipboard text | Prints the current clipboard text |
| [09_input_state.lua](09_input_state.lua) | Pointer coordinates and Shift key state | Reads input state; does not send input |
| [10_file_dialog.lua](10_file_dialog.lua) | A native file picker, filters, cancellation, and errors | Opens a dialog and prints the selected path |
| [11_runtime_arguments.lua](11_runtime_arguments.lua) | Script paths, working directories, and Windows arguments | Prints paths and the command line |
| [12_single_instance.lua](12_single_instance.lua) | A path-based single-instance guard | Waits 10 seconds; a concurrent second instance exits |

## Files and directories

```bat
luajit examples\02_files.lua
```

The script creates `examples/output/cafe.txt` with an accented `e` (U+00E9)
in its name. The UTF-8 name is written using byte escapes in the source so the
example remains readable in editors regardless of their display configuration.
The script reads the text back and verifies the contents. The output directory
is ignored by Git. An existing example file is rejected instead of replaced.
To run it again, remove the generated file yourself or choose another directory:

```bat
luajit examples\02_files.lua "C:\Temp\LuaJIT-example-2"
```

Text helpers default to UTF-8. Use `"BINARY"` explicitly for raw file bytes.
Call `unicode_io` functions through their returned module table; requiring the
module does not replace standard `io` or `os` functions.

## Processes

```bat
luajit examples\04_process.lua
```

Expected output includes `LuaJIT process example`, exit code `0`, and the child
PID. `process.command` constructs a command line from an executable and argument
list. `runCapture` returns `stdout, stderr, exitCode, pid, timedOut` on the
normal capture path, or `nil, error` if launching or capturing fails. Its timeout
option is in seconds. Captured output is raw bytes; determine the child's actual
encoding before using `process.decode` for non-UTF-8 output. The command in this
example produces ASCII, so no conversion is needed.

## Window lookup

```bat
luajit examples\06_windows.lua "Notepad"
```

The argument is a title substring; omit it to list all visible top-level windows.
Window titles depend on the applications open on your desktop and their language.
An empty result is valid. A window can disappear between enumeration and reading
its title, so the example handles that case.

## Interactive examples

Run these individually when you want to interact with the desktop:

```bat
luajit examples\08_clipboard.lua
luajit examples\10_file_dialog.lua
```

The clipboard example displays your current clipboard text. The dialog example
returns a selected path without opening or reading that file; cancellation returns
`nil` without an error. A dialog failure returns `nil, error`.

For the single-instance example, run the following command in two CMD windows
within 10 seconds:

```bat
luajit examples\12_single_instance.lua
```

The first process waits, and the second exits immediately. The guard key uses
the normalized entry path in the current Windows session, so use the same script
file in both windows.

## Arguments and errors

```bat
luajit examples\11_runtime_arguments.lua "hello world" sample
```

`argv.get()` includes the executable and script arguments from the original
Windows command line. The standard `arg[1]` is the script's first user argument.
`runtime` and `lvars` require a valid UTF-8 script path in `arg[0]`.

The examples use `assert` for unexpected failures so errors are easy to see.
Applications should handle recoverable failures according to their own needs.
Some functions distinguish a missing item from an API failure; keep all return
values when inspecting an error. See the [function index](../docs/API.md) and
the linked sources for individual contracts.
