# Function Index

Signatures are extracted from the source files. This index lists functions declared with `function module.name(...)`; aliases, table fields, and metatables may expose additional features. Consult the linked source for parameter types, defaults, and return values.

## app_icon

[Source](../app_icon.lua)

```lua
app_icon.set(hwnd, source)
app_icon.release(hwnd, destroying)
```

## argv

[Source](../argv.lua)

```lua
argv.commandLine()
argv.get()
argv.count()
argv.at(index)
argv.program()
```

## clipboard

[Source](../clipboard.lua)

```lua
clipboard.hasText()
clipboard.getText()
clipboard.setText(text)
clipboard.clear()
clipboard.getSequenceNumber()
```

## env

[Source](../env.lua)

```lua
env.get(name, default_value)
env.exists(name)
env.set(name, value)
env.unset(name)
env.expand(text)
```

## file_dialog

[Source](../file_dialog.lua)

```lua
file_dialog.open(options)
file_dialog.save(options)
file_dialog.selectFolder(options)
```

## keyboard

[Source](../keyboard.lua)

```lua
keyboard.keyCode(key)
keyboard.keyDown(key)
keyboard.keyUp(key)
keyboard.press(key, count, delay)
keyboard.hotkey(keys)
keyboard.sendText(text)
keyboard.isDown(key)
keyboard.sleep(ms)
```

## lvars

[Source](../lvars.lua)

```lua
lvars.SetWorkingDir(path_value)
```

## mouse

[Source](../mouse.lua)

```lua
mouse.getPosition()
mouse.getVirtualScreen()
mouse.move(dx, dy)
mouse.moveTo(x, y)
mouse.down(button)
mouse.up(button)
mouse.click(button, count, delay)
mouse.doubleClick(button)
mouse.clickAt(x, y, button, count)
mouse.wheel(steps)
mouse.hWheel(steps)
mouse.dragTo(x, y, button)
mouse.sleep(ms)
```

## process

[Source](../process.lua)

```lua
process.quoteArg(value)
process.command(exePath, args)
process.run(commandLine, options)
process.runWait(commandLine, options)
process.runCapture(commandLine, options)
process.exists(target)
process.getName(target)
process.getParent(target)
process.getPath(target)
process.getList()
process.close(target, exitCode)
process.setPriority(priority, target)
process.wait(target, timeout)
process.waitClose(target, timeout)
process.getACP()
process.getOEMCP()
process.decode(data, codePage)
process.ProcessExist(target)
process.ProcessClose(target)
process.ProcessGetName(target)
process.ProcessGetParent(target)
process.ProcessGetPath(target)
process.ProcessSetPriority(priority, target)
process.ProcessWait(target, timeout)
process.ProcessWaitClose(target, timeout)
process.ProcessGetList()
process.Run(target, workingDir, options)
process.RunWait(target, workingDir, options)
process.RunCapture(target, workingDir, options)
process.QuoteArg(value)
process.Command(program, args)
process.Exec(program, args, workingDir, options)
process.ExecRun(program, args, workingDir, options)
process.ExecWait(program, args, workingDir, options)
process.ExecShell(command, workingDir, options)
process.GetACP()
process.GetOEMCP()
process.Decode(data, codePage)
```

## registry

[Source](../registry.lua)

```lua
registry.typeName(valueType)
registry.qword(value)
registry.qwordToString(value)
registry.read(path, valueName, view)
registry.write(path, valueName, value, valueType, view)
registry.createKey(path, view)
registry.keyExists(path, view)
registry.valueExists(path, valueName, view)
registry.deleteValue(path, valueName, view)
registry.enumKeys(path, view)
registry.enumValues(path, view)
registry.deleteKey(path, recursive, view)
registry.expand(text)
```

## runtime

[Source](../runtime.lua)

This module provides values or performs initialization; see README and the source.

## setup_paths

[Source](../setup_paths.lua)

This module provides values or performs initialization; see README and the source.

## shell

[Source](../shell.lua)

```lua
shell.quoteArg(value)
shell.parameters(args)
shell.errorText(code)
shell.execute(verb, target, args, directory, showMode)
shell.open(target, args, directory, showMode)
shell.run(exePath, args, directory, showMode)
shell.runAs(exePath, args, directory, showMode)
shell.openUrl(url)
shell.openFolder(path)
shell.explore(path)
shell.openWith(path)
shell.edit(path)
shell.select(path)
```

## single_instance

[Source](../single_instance.lua)

This module provides values or performs initialization; see README and the source.

## strings

[Source](../strings.lua)

```lua
strings.is_valid_utf8(text)
strings.byte_len(text)
strings.len(text)
strings.sub(text, first_index, last_index)
strings.reverse(text)
strings.codepoint(text, first_index, last_index)
strings.char(...)
strings.chars(text)
strings.codes(text)
strings.lower(text)
strings.upper(text)
strings.capitalize(text)
strings.normalize(text, form)
strings.nfc(text)
strings.nfd(text)
strings.nfkc(text)
strings.nfkd(text)
strings.starts_with(text, prefix)
strings.ends_with(text, suffix)
strings.contains(text, needle)
strings.equals_ignore_case(left, right)
strings.find_plain(text, needle, init)
strings.rfind(text, needle, init)
strings.find(text, pattern, init, plain)
strings.match(text, pattern, init)
strings.gmatch(text, pattern)
strings.gsub(text, pattern, replacement, limit)
strings.replace(text, old_text, new_text, limit)
strings.count(text, needle)
strings.ltrim(text)
strings.rtrim(text)
strings.trim(text)
strings.split(text, sep)
strings.split_str(text, sep)
strings.join(values, sep)
strings.rep(text, count, separator)
strings.pad_left(text, width, pad)
strings.pad_right(text, width, pad)
strings.center(text, width, pad)
strings.format(format_text, ...)
strings.dump(func)
strings.is_empty(text)
strings.is_blank(text)
strings.char_at(text, index)
strings.contains_ignore_case(text, needle)
strings.starts_with_ignore_case(text, prefix)
strings.ends_with_ignore_case(text, suffix)
strings.remove_prefix(text, prefix)
strings.remove_suffix(text, suffix)
strings.partition(text, separator)
strings.rpartition(text, separator)
strings.words(text)
strings.collapse_whitespace(text, replacement)
strings.split_lines(text, keep_ends)
strings.insert(text, index, value)
strings.remove_range(text, first_index, last_index)
strings.replace_range(text, first_index, last_index, replacement)
strings.truncate(text, max_length, suffix)
strings.create_buffer(size)
```

## system

[Source](../system.lua)

```lua
system.getUserName()
system.getComputerName()
system.getWindowsVersion()
system.getExePath()
system.getWindowsPath()
system.getSystemPath()
system.getTempPath()
system.getCurrentDirectory()
system.getKnownFolder(name)
system.getDesktopPath()
system.getDocumentsPath()
system.getDownloadsPath()
system.getProfilePath()
system.getAppDataPath()
system.getLocalAppDataPath()
system.getProgramDataPath()
system.getProgramFilesPath()
system.getProgramFilesX86Path()
system.getDrives()
system.getDrive(path)
system.getMemory()
system.getScreen()
system.getDpi()
system.getScale()
system.getUptime()
```

## timer

[Source](../timer.lua)

```lua
timer.start(precision)
timer.stop()
```

## unicode_io

[Source](../unicode_io.lua)

```lua
unicode_io.acp()
unicode_io.oemcp()
unicode_io.codepage_to_utf8(text, codepage)
unicode_io.utf8_to_codepage(text, codepage, allow_lossy)
unicode_io.ansi_to_utf8(text, codepage)
unicode_io.utf8_to_ansi(text, codepage, allow_lossy)
unicode_io.oem_to_utf8(text, codepage)
unicode_io.utf8_to_oem(text, codepage, allow_lossy)
unicode_io.argv_raw()
unicode_io.argv()
unicode_io.refresh_argv()
unicode_io.open(path, mode)
File:close()
File:flush()
File:write(...)
File:seek(whence, offset)
File:read(...)
File:lines(...)
unicode_io.lines(path, ...)
unicode_io.rename(from, to)
unicode_io.loadfile(path, mode, env)
unicode_io.dofile(path)
unicode_io.console_write(text)
unicode_io.print(...)
unicode_io.console_readline(prompt)
File:setvbuf(mode, size)
unicode_io.type(file)
unicode_io.input(value)
unicode_io.output(value)
unicode_io.read(...)
unicode_io.write(...)
unicode_io.flush()
unicode_io.close(file)
unicode_io.getcwd()
unicode_io.chdir(path)
unicode_io.abspath(path)
unicode_io.getenv(name)
unicode_io.setenv(name, value)
unicode_io.exists(path)
unicode_io.isfile(path)
unicode_io.isdir(path)
unicode_io.stat(path)
unicode_io.set_readonly(path, enabled)
unicode_io.set_hidden(path, enabled)
unicode_io.set_archive(path, enabled)
unicode_io.mkdir(path)
unicode_io.rmdir(path)
unicode_io.basename(path)
unicode_io.dirname(path)
unicode_io.extension(path)
unicode_io.stem(path)
unicode_io.join(...)
unicode_io.makedirs(path)
unicode_io.listdir(path)
unicode_io.glob(pattern, recursive)
unicode_io.remove(path, force)
unicode_io.copy(from, to, overwrite)
unicode_io.move(from, to, overwrite)
unicode_io.walk(path)
unicode_io.copy_tree(from, to, overwrite)
unicode_io.remove_all(path, force)
unicode_io.read_file(path, encoding)
unicode_io.write_file(path, content, encoding, allow_lossy)
unicode_io.append_file(path, content, encoding, allow_lossy)
unicode_io.read_lines(path, encoding)
unicode_io.line_count(path, encoding)
unicode_io.read_line(path, line_number, encoding)
unicode_io.write_line(path, line_number, text, encoding, allow_lossy)
unicode_io.insert_line(path, line_number, text, encoding, allow_lossy)
unicode_io.append_line(path, text, encoding, allow_lossy)
unicode_io.tmpname()
unicode_io.tmpfile()
unicode_io.popen(command, mode)
unicode_io.execute(command)
unicode_io.searchpath(name, path, sep, rep)
unicode_io.load_library(path)
unicode_io.readFile(path, encoding)
unicode_io.writeFile(path, content, encoding, allow_lossy)
unicode_io.appendFile(path, content, encoding, allow_lossy)
```

## win_constants

[Source](../win_constants.lua)

This module provides values or performs initialization; see README and the source.

## win_native

[Source](../win_native.lua)

```lua
win_native.os_getenv(name)
win_native.os_setenv(name,value)
win_native.os_unsetenv(name)
win_native.os_getpid()
win_native.sleep(ms)
win_native.uptime()
win_native.cwd()
win_native.chdir(path)
win_native.exepath()
win_native.os_tmpdir()
win_native.fs_lstat(path)
win_native.fs_stat(path)
win_native.fs_mkdir(path)
win_native.fs_rmdir(path)
win_native.fs_unlink(path)
win_native.fs_copyfile(from,to,flags)
win_native.fs_rename(from,to)
win_native.fs_scandir(path)
win_native.fs_scandir_next(request)
win_native.fs_realpath(path)
win_native.fs_open(path,mode)
win_native.fs_close(h)
win_native.fs_read(h,count,offset)
win_native.fs_write(h,data,offset)
win_native.fs_fsync(h)
win_native.fs_mkstemp(template)
```

## win_types

[Source](../win_types.lua)

This module provides values or performs initialization; see README and the source.

## window

[Source](../window.lua)

```lua
window.hwndToNumber(hwnd)
window.numberToHwnd(value)
window.getTitle(hwnd)
window.find(titlePart, includeHidden)
window.findAll(titlePart, includeHidden)
window.exists(hwnd)
window.isVisible(hwnd)
window.isEnabled(hwnd)
window.isMinimized(hwnd)
window.isMaximized(hwnd)
window.getClass(hwnd)
window.getPid(hwnd)
window.getRect(hwnd)
window.move(hwnd, x, y, width, height, repaint)
window.moveTo(hwnd, x, y)
window.resize(hwnd, width, height)
window.show(hwnd)
window.hide(hwnd)
window.minimize(hwnd)
window.maximize(hwnd)
window.restore(hwnd)
window.activate(hwnd)
window.enable(hwnd, enabled)
window.disable(hwnd)
window.setTitle(hwnd, text)
window.close(hwnd)
window.wait(titlePart, timeout, includeHidden)
window.waitClose(hwnd, timeout)
window.WinExist(target, includeHidden)
window.WinGetID(target, includeHidden)
window.WinWait(target, timeoutSeconds, includeHidden)
window.WinWaitClose(target, timeoutSeconds, includeHidden)
window.WinActive(target, includeHidden)
window.WinWaitActive(target, timeoutSeconds, includeHidden)
window.WinWaitNotActive(target, timeoutSeconds, includeHidden)
window.WinActivate(target, includeHidden)
window.WinClose(target, includeHidden)
window.WinShow(target, includeHidden)
window.WinHide(target, includeHidden)
window.WinMinimize(target, includeHidden)
window.WinMaximize(target, includeHidden)
window.WinRestore(target, includeHidden)
window.WinGetTitle(target, includeHidden)
window.WinGetClass(target, includeHidden)
window.WinGetPID(target, includeHidden)
window.WinGetPos(target, includeHidden)
window.WinGetMinMax(target, includeHidden)
window.WinGetCount(title, includeHidden)
window.WinGetList(title, includeHidden)
window.WinGetStyle(target, includeHidden)
window.WinGetExStyle(target, includeHidden)
window.WinMove(x, y, width, height, target, includeHidden)
window.WinSetTitle(newTitle, target, includeHidden)
window.WinSetEnabled(value, target, includeHidden)
window.WinIsAlwaysOnTop(target, includeHidden)
window.WinSetAlwaysOnTop(value, target, includeHidden)
```

