# Publishing on GitHub

Suggested repository name: `luajit-windows-modules`.

Suggested description:

> Windows API modules for LuaJIT: UTF-8, files, processes, windows, registry and automation.

Suggested topics: `luajit`, `lua`, `windows`, `winapi`, `ffi`, `utf8`.

The project uses the MIT License. The copyright notice identifies the project
contributors collectively. You can replace that attribution with your preferred
copyright holder name before publishing.

## Using Git

Create an empty repository in your GitHub account without an automatically
generated README, `.gitignore`, or license.

Open CMD and run the commands below from the prepared project directory.
Replace the local path and `YOUR_ACCOUNT` with your own values:

```bat
cd /d "C:\Projects\luajit-windows-modules"
git init -b main
git add .
git diff --cached --stat
git commit -m "Initial release of LuaJIT Windows modules"
git remote add origin https://github.com/YOUR_ACCOUNT/luajit-windows-modules.git
git push -u origin main
```

Git must have your author name and email configured for the commit. Pushing
requires authentication with your GitHub account.

## Using the browser

Upload the contents of the prepared directory through **Add file → Upload files**.
Extract the ZIP first: uploading the archive alone does not create a source tree.
Make sure `.gitignore` and `.gitattributes` are included.

## Preparation checks

- All 22 Lua source files were initially copied byte for byte. The only later
  source edit translates the example heading in a comment in `timer.lua`.
- All 22 files passed syntax checks with the installed LuaJIT on Windows.
- The 21 library modules loaded in a single process in both alphabetical and
  reverse order. `setup_paths.lua` was checked separately for syntax.
- Smoke checks covered UTF-8 string length and uppercase conversion, reading
  README through `unicode_io`, checking a directory, timing, reading an
  environment variable, and obtaining the current directory.
- Twelve runnable examples are included with an English usage guide. Nine
  examples were executed: strings, files, environment, process capture, system
  information, window enumeration, registry reading, input state, and arguments.
  The clipboard, dialog, and single-instance examples were checked for syntax
  without running their interactive scenarios. All example scripts passed
  syntax checks. Relative library setup was also exercised from another working
  directory.

These are publication preparation checks, not a full functional audit.
Dialogs, window manipulation, simulated input, registry changes, and concurrent
single-instance behavior were not covered. File creation and a temporary
process-local environment variable change were exercised by the examples.
