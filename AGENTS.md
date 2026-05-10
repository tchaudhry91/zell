# Zig 0.16.0 Agent Reference

> Condensed from the [0.16.0 release notes](https://ziglang.org/download/0.16.0/release-notes.html).  
> This project uses **Zig 0.16.0**. Do not assume 0.15.x (or older) patterns.

---

## About This Project (Teaching Context)

**Tanmay** is the human being driving this project. Your job is to **teach him Zig**, not to write the project for him.

- **Background**: Tanmay is proficient in **Go** and comfortable with **Python**. He is **just starting out in Zig**.
- **Mission**: Educate him, explain *why* things work the way they do, and **make him do the hard work**. Suggest, guide, and review — but do not hand him fully-formed solutions he could simply copy-paste. He learns by struggling, by reading compiler errors, and by writing the code himself.
- **Style**: Use analogies to Go/Python where they help, but also highlight where Zig deliberately differs (e.g. manual memory management, comptime, explicit error handling, no hidden allocations). When he asks for code, prefer giving a small snippet or a skeleton over a complete implementation. Ask leading questions before giving answers.

---

## 1. The Big One: I/O as an Interface (`std.Io`)

All blocking, non-deterministic, or system-interacting APIs now require an `std.Io` instance. This is the single largest change in 0.16.

### Getting an `Io`
- **"Juicy Main"** (preferred): accept `std.process.Init` as `main`'s first parameter.
  ```zig
  pub fn main(init: std.process.Init) !void {
      const gpa = init.gpa;
      const io  = init.io;
      // ...
  }
  ```
  `Init` provides: `gpa`, `io`, `arena` (ArenaAllocator), `environ_map`, `preopens`, and `minimal` (args + environ).
- **Minimal main**: `pub fn main(init: std.process.Init.Minimal) !void` gives only `args` and `environ`.
- **No params**: `pub fn main() !void` is still legal, but you cannot access CLI args or env vars.
- **In tests**: use `std.testing.io` (like `std.testing.allocator`).
- **Last-resort workaround** when you don't have one:
  ```zig
  var threaded: std.Io.Threaded = .init_single_threaded;
  const io = threaded.io();
  ```
  This is the old blocking behavior; treat it like `page_allocator` — acceptable if you truly need it, but prefer plumbing `Io` through your APIs.

### I/O Implementations
| Impl | Status | Notes |
|------|--------|-------|
| `std.Io.Threaded` | stable, feature-complete | Drop-in replacement for old blocking I/O. `-fno-single-threaded` (task concurrency + cancelation) or `-fsingle-threaded` (no concurrency). |
| `std.Io.Evented` | WIP / experimental | M:N green threads. |
| `std.Io.Uring` | proof-of-concept | Linux io_uring. Missing networking & error handling. |
| `std.Io.Kqueue` | proof-of-concept | Enough to fix common async-runtime bugs. |
| `std.Io.Dispatch` | proof-of-concept | macOS Grand Central Dispatch. |
| `std.Io.failing` | testing | Simulates a system that supports no operations. |

### Task Concurrency Primitives
- `io.async(func, .{args})` -> `Future(T)`  
  Spawns a task. Infallible. On limited backends it may just call the function synchronously.
- `io.concurrent(func, .{args})` -> `Future(T)`  
  Requires actual concurrency; can fail with `error.ConcurrencyUnavailable`. Allocates task memory.
- `future.await(io)` — blocks (logically) until done, returns value.
- `future.cancel(io)` — like await but requests interrupt; may return `error.Canceled`.  
  **Pattern**: `defer if (foo_future.cancel(io)) |r| r.deinit() else |_| {}`
- `std.Io.Group` — manage many tasks with shared lifetime. O(1) spawn. `group.await(io)`, `group.cancel(io)`.
- `std.Io.Batch` — low-level operation concurrency (FileReadStreaming, FileWriteStreaming, NetReceive, etc.).
- `std.Io.Select` — wait until one or more tasks complete.
- `std.Io.Queue(T)` — MPMC queue with suspend/resume.

### Cancelation
- Most I/O operations now include `error.Canceled` in their error sets.
- `io.checkCancel()` adds explicit cancelation points in CPU-bound work.
- `io.recancel()` re-arms a cancelation request.
- `io.swapCancelProtection()` makes cancelation unreachable in a scope.

### Sync Primitives (all now need `Io`)
| Old (0.15) | New (0.16) |
|------------|------------|
| `std.Thread.Mutex` | `std.Io.Mutex` |
| `std.Thread.Condition` | `std.Io.Condition` |
| `std.Thread.ResetEvent` | `std.Io.Event` |
| `std.Thread.WaitGroup` | `std.Io.Group` |
| `std.Thread.Futex` | `std.Io.Futex` |
| `std.Thread.Semaphore` | `std.Io.Semaphore` |
| `std.Thread.RwLock` | `std.Io.RwLock` |
| `std.once` | **removed** — hand-roll or avoid globals |

Lock-free primitives do **not** need `Io`.

### File System (`std.Io.Dir` / `std.Io.File`)
- `std.fs.Dir` → `std.Io.Dir`
- `std.fs.File` → `std.Io.File`
- Nearly every call now takes `io` as a parameter:
  - `file.close(io)`
  - `file.readStreaming(io, buf)`
  - `dir.openFile(io, path, opts)`
- `std.fs.cwd()` → `std.Io.Dir.cwd()`
- `fs.realpathAlloc` → `std.Io.Dir.realPathFileAbsoluteAlloc`
- `fs.selfExePath*` → `std.process.executablePath*` / `executableDirPath*`
- `fs.getCwd` → `std.process.currentPath(io, buf)` / `currentPathAlloc(io, allocator)`
- `fs.getAppDataDir` → **removed** (use third-party `known-folders` or roll your own)
- `fs.path` → `std.Io.Dir.path` / `std.Io.Dir.max_path_bytes` / `std.Io.Dir.max_name_bytes`
- `fs.path.relative` is now **pure**: needs `cwd_path` and (on Windows) `environ_map`.
- Added `std.Io.Dir.walkSelectively` for skipping subtrees during walks.

### Networking
- All `std.net` APIs migrated to `std.Io`.
- Windows networking no longer uses `ws2_32.dll`; direct AFD access. Cancelation & Batch work properly.
- `std.Io.Evented` does **not** yet implement networking.

### Reader / Writer
- `std.io` → `std.Io`
- `std.Io.GenericReader` / `std.Io.AnyReader` → `std.Io.Reader` (non-generic; buffer is in the interface, not the implementation)
- `std.Io.GenericWriter` / `std.Io.AnyWriter` → `std.Io.Writer`
- `FixedBufferStream` → **removed**
  - Reading: `var reader: std.Io.Reader = .fixed(data);`
  - Writing: `var writer: std.Io.Writer = .fixed(buffer);`
- `std.leb.readUleb128` → `std.Io.Reader.takeLeb128`

### Time
- `std.time.Instant` / `std.time.Timer` → `std.Io.Timestamp`
- `std.time.timestamp` → `std.Io.Timestamp.now`
- `std.Io.Clock.resolution()` may fail; this lets `error.Unexpected`/`error.ClockUnsupported` be removed from timeout/clock-reading error sets.

### Random / Entropy
- `std.crypto.random.bytes` → `io.random(&buf)`
- `std.crypto.random` interface → `std.Random.IoSource{ .io = io }.interface()`
- `posix.getrandom` → `io.random(&buf)`
- Cryptographically secure / out-of-process entropy: `io.randomSecure(&buf)` (may return `error.EntropyUnavailable`).

### Process
- `std.process.Child.init(...); child.spawn(io);` → `std.process.spawn(io, .{ .argv = argv, .stdin = .pipe, ... });`
- `std.process.Child.run(allocator, io, ...)` → `std.process.run(allocator, io, ...)`
- `std.process.execv` → `std.process.replace(io, .{ .argv = argv })`
- `std.process.Init.preopens` replaces `std.fs.wasi.Preopens`.

### Format / Print
- `fmt.format` → `std.Io.Writer.print`
- `fmt.Formatter` → `Alt`
- `fmt.FormatOptions` → `Options`
- `fmt.bufPrintZ` → `bufPrintSentinel`
- `{D}` duration format specifier → **removed**; use `std.Io.Duration{ .nanoseconds = ns }` and print with `{f}`.

---

## 2. Language Changes

### `@Type` is Dead; Long Live the New Builtins
`@Type` is deprecated and replaced by individual builtins:
- `@Int(.unsigned, 10)` — replaces `@Type(.{ .int = ... })` and `std.meta.Int`
- `@Tuple(&.{ u32, [2]f64 })` — replaces `std.meta.Tuple`
- `@Pointer(.one, .{ .const = true }, u32, null)` — pointer type construction
- `@Fn(param_types, param_attrs, ReturnType, fn_attrs)` — function type construction
- `@Struct(layout, BackingInt, field_names, field_types, field_attrs)` — struct type construction
- `@Union(layout, ArgType, field_names, field_types, field_attrs)` — union type construction
- `@Enum(TagInt, mode, field_names, field_values)` — enum type construction
- `@EnumLiteral()` — the type of `.foo` enum literals (replaces `@Type(.enum_literal)`)

No builtins for `Float`, `Array`, `Optional`, `ErrorUnion`, `Opaque` — use `std.meta.Float`, normal `[]T`/`[N]T` syntax, `?T`, `E!T`, `opaque {}`.

**Important**: it is no longer possible to reify error sets (`@Type(.{ .error_set = ... })`). Declare them explicitly with `error{ ... }`.

### `@cImport` Deprecated
Use the build system instead:
```zig
const translate_c = b.addTranslateC(.{
    .root_source_file = b.path("src/c.h"),
    .target = target,
    .optimize = optimize,
});
// ... import as module named "c"
```
Or add the official `translate-c` package for more customization.

### `switch` Improvements
- `packed struct` and `packed union` may be used as switch prongs (compared by backing integer).
- Decl literals and result-type-dependent expressions (e.g. `@enumFromInt`) work as prongs.
- Union tag captures allowed for all prongs, not just inline ones.
- Prongs may contain errors not in the switched error set if they contain `=> comptime unreachable`.
- Switch prong captures may no longer **all** be discarded.
- Switching on `void` no longer unconditionally requires an `else` prong.

### Float ↔ Int Ergonomics
- **Small integer coercion**: if an integer type's full range fits in a float without rounding, it coerces implicitly. Example: `var x: f32 = foo_int;` where `foo_int: u24`. `u25` still needs `@floatFromInt`.
- `@floor`, `@ceil`, `@round`, `@trunc` now convert floats to integers directly. `@intFromFloat` is deprecated (use `@trunc`).
- Unary float builtins (`@sqrt`, `@sin`, `@cos`, `@exp`, `@log`, `@floor`, `@ceil`, `@round`, `@trunc`) now forward result types, so `const x: f64 = @sqrt(@floatFromInt(N));` works.

### Packed Types
- **Packed unions** require explicit backing integer: `packed union(u16) { ... }`
- **Packed unions** forbid unused bits: all fields must have same `@bitSizeOf` as backing int.
- **Pointers forbidden** in `packed struct` and `packed union` fields. Use `usize` + `@ptrFromInt`/`@intFromPtr` instead.
- **Extern context**: `enum`, `packed struct`, `packed union` with *implicit* backing types are no longer valid `extern` types. Add explicit tag/backing types.
- Equality comparisons on packed unions now work directly.

### Vectors
- **Runtime vector indexes forbidden**: `vector[i]` where `i` is runtime-known is a compile error. Coerce to array first:
  ```zig
  const arr: [vector_type.len]vector_type.child = vector;
  for (&arr) |elem| { _ = elem; }
  ```
- Vectors and arrays no longer support in-memory coercion. Use direct coercion or unwrap errors first.

### Pointers & Types
- **Returning local addresses is a compile error**: `return &x;` where `x` is a local now errors. (Returning `undefined` is still legal, but `return &local` is caught.)
- **Explicitly-aligned pointers are distinct**: `*u8` and `*align(1) u8` are no longer the same type, but they coerce to each other.
- **Pointers to comptime-only types are no longer comptime-only**: `*comptime_int` is a runtime type (but dereferencing it at runtime is still illegal).
- **Lazy field analysis**: using a type as a namespace no longer forces resolution of all its fields. This avoids unnecessary codegen bloat (e.g. `std.Io.Writer` no longer pulls in the entire `std.Io` vtable just by being named).
- **Simplified dependency loop rules**: some new cases are loops that previously weren't; error messages are clearer.
- **Zero-bit tuple fields no longer implicitly `comptime`**: they are still comptime-known, but `is_comptime` is false.

---

## 3. Standard Library Removals & Renames

### Removed
- `std.Thread.Pool` → use `std.Io.Group` / `std.Io.async` / `std.Io.concurrent`
- `heap.ThreadSafeAllocator` → `heap.ArenaAllocator` is now lock-free thread-safe on its own
- `SegmentedList`
- `meta.declList`
- `builtin.subsystem`
- `std.once`
- `Io.GenericWriter`, `Io.AnyWriter`, `Io.null_writer`, `Io.CountingReader`
- `Thread.Mutex.Recursive`
- `fs.getAppDataDir`
- Most `std.posix` and `std.os.windows` medium-level abstractions → go higher (`std.Io`) or lower (`std.posix.system`)
- All `*Z`, `*W`, `*Wasi` file system variants (e.g. `fs.realpathZ`, `fs.Dir.deleteFileW`, etc.)

### Renamed (high-impact)
| Old | New |
|-----|-----|
| `std.fs.Dir` | `std.Io.Dir` |
| `std.fs.File` | `std.Io.File` |
| `fs.File.read` / `readv` | `std.Io.File.readStreaming` |
| `fs.File.pread` / `preadv` | `std.Io.File.readPositional` |
| `fs.File.write` / `writev` | `std.Io.File.writeStreaming` |
| `fs.File.pwrite` / `pwritev` | `std.Io.File.writePositional` |
| `fs.File.seekTo` / `seekBy` | `std.Io.File.Reader.seekTo` / `seekBy` |
| `fs.File.getEndPos` | `std.Io.File.length` |
| `fs.File.setEndPos` | `std.Io.File.setLength` |
| `fs.File.chmod` | `std.Io.File.setPermissions` |
| `fs.File.chown` | `std.Io.File.setOwner` |
| `fs.File.updateTimes` | `std.Io.File.setTimestamps` / `setTimestampsNow` |
| `fs.Dir.makeDir` | `std.Io.Dir.createDir` |
| `fs.Dir.makePath` | `std.Io.Dir.createDirPath` |
| `fs.Dir.rename` | `std.Io.Dir.rename` (takes two `Dir` params + `Io`) |
| `fs.copyFileAbsolute` | `std.Io.Dir.copyFileAbsolute` |
| `fs.openDirAbsolute` | `std.Io.Dir.openDirAbsolute` |
| `fs.createFileAbsolute` | `std.Io.Dir.createFileAbsolute` |
| `fs.deleteFileAbsolute` | `std.Io.Dir.deleteFileAbsolute` |
| `fs.renameAbsolute` | `std.Io.Dir.renameAbsolute` |
| `fs.readLinkAbsolute` | `std.Io.Dir.readLinkAbsolute` |
| `fs.symLinkAbsolute` | `std.Io.Dir.symLinkAbsolute` |
| `fs.realpath` | `std.Io.Dir.realPathFileAbsolute` |
| `fs.realpathAlloc` | `std.Io.Dir.realPathFileAbsoluteAlloc` |
| `fs.Dir.realpath` | `std.Io.Dir.realPathFile` |
| `fs.Dir.realpathAlloc` | `std.Io.Dir.realPathFileAlloc` |
| `fs.selfExePath` | `std.process.executablePath` |
| `fs.selfExeDirPath` | `std.process.executableDirPath` |
| `fs.openSelfExe` | `std.process.openExecutable` |
| `fs.Dir.setAsCwd` | `std.process.setCurrentDir` |
| `fs.File.Mode` | `std.Io.File.Permissions` |
| `fs.File.getOrEnableAnsiEscapeSupport` | `std.Io.File.enableAnsiEscapeCodes` |
| `fs.Dir.atomicSymLink` | `std.Io.Dir.symLinkAtomic` |
| `fs.File.isCygwinPty` | removed |
| `std.process.getCwd` | `std.process.currentPath` |
| `std.process.getCwdAlloc` | `std.process.currentPathAlloc` |
| `std.mem.indexOf*` | `std.mem.find*` |
| `std.Progress` | max node length 40 → 120 |

### Containers ("Unmanaged" migration)
- `ArrayHashMap` / `AutoArrayHashMap` / `StringArrayHashMap` (managed) → **removed**
- `AutoArrayHashMapUnmanaged` → `array_hash_map.Auto`
- `StringArrayHashMapUnmanaged` → `array_hash_map.String`
- `ArrayHashMapUnmanaged` → `array_hash_map.Custom`
- `PriorityQueue` / `PriorityDequeue` no longer store an `Allocator`. Initialize with `.empty`. Methods renamed: `add`→`push`, `remove`→`pop`.

### Debug Info / Stack Traces
- `std.debug.captureStackTrace` → `std.debug.captureCurrentStackTrace`
- `std.debug.dumpStackTrace` → `std.debug.dumpCurrentStackTrace`
- `std.debug.writeStackTrace` / `std.debug.writeCurrentStackTrace` now take `Io.Terminal`
- `std.debug.StackIterator` → no longer public; use `captureCurrentStackTrace` or `std.debug.SelfInfo`
- Override debug info provider with `@import("root").debug.SelfInfo`

### Error Sets
- `error.RenameAcrossMountPoints` → `error.CrossDevice`
- `error.NotSameFileSystem` → `error.CrossDevice`
- `error.SharingViolation` → `error.FileBusy`
- `error.EnvironmentVariableNotFound` → `error.EnvironmentVariableMissing`
- `std.Io.Dir.rename` returns `error.DirNotEmpty` rather than `error.PathAlreadyExists`
- `fs.Dir.readFileAlloc` limit reached → `error.StreamTooLong` (was `FileTooBig`)

### Memory / MMap
- `std.posix.mlock` / `mlock2` / `mlockall` → `std.process.lockMemory` / `lockMemoryAll`
- `mmap` / `mprotect` flags now use struct booleans: `.{ .READ = true, .WRITE = true }`
- `File.MemoryMap` pointer contents are only guaranteed synchronized at explicit sync points.

### Atomic / Temporary Files
- `std.Io.File.Atomic` reworked; uses `O_TMPFILE` on Linux where possible.
- `atomicFile()` / `flush()` / `renameIntoPlace()` → `createFileAtomic()` / `writer.flush()` / `replace()` or `link()`.

---

## 4. Build System Changes

- **`@cImport` migration**: use `b.addTranslateC(...)` and import the resulting module.
- **Local overrides**: `zig build --fork=/path/to/pkg` overrides any dependency with matching `name` + `fingerprint`. Ephemeral; no source-tree mutation.
- **Packages fetched into `zig-pkg/`** (project-local), then recompressed into global cache. Fingerprint is **required** in `build.zig.zon`.
- **`--test-timeout <duration>`**: kills and restarts the test runner if any individual `test` block exceeds the timeout.
- **`--error-style {verbose,verbose_clear,minimal,minimal_clear}`**: replaces `--prominent-compile-errors`.
- **`--multiline-errors {indent,newline,none}`**: controls multi-line error formatting.
- **Temporary files**: `b.makeTempPath()` and `addRemoveDirTree` removed. Use `b.addTempFiles()` / `b.addMutateFiles()` / `Build.tmpPath`.

---

## 5. Coding Conventions for This Codebase

1. **Plumb `Io` everywhere**: if a function does I/O, it takes `io: std.Io` (or stores it in a context struct). Don't reach for `Io.Threaded.init_single_threaded` inside library code.
2. **Use "Juicy Main"**: `pub fn main(init: std.process.Init) !void` is the default entry point. Only use `Init.Minimal` if you genuinely don't need `gpa`, `io`, or `arena`.
3. **No globals for env/args**: environment variables and CLI args come from `init.minimal.args` and `init.environ_map`. Pass them down.
4. **No `std.Thread.Pool`**: use `std.Io.Group` or `io.async`/`io.concurrent`.
5. **No `ArrayHashMap` managed**: use `array_hash_map.Auto` / `.String` / `.Custom`.
6. **No `@Type` or `@intFromFloat`**: use `@Int`, `@Tuple`, `@Struct`, `@Union`, `@Enum`, `@Pointer`, `@Fn`, `@EnumLiteral`, and `@trunc`.
7. **No `std.io`**: use `std.Io`. Readers/Writers are `std.Io.Reader` / `std.Io.Writer`.
8. **No `FixedBufferStream`**: use `std.Io.Reader.fixed(data)` / `std.Io.Writer.fixed(buf)`.
9. **Check for `error.Canceled`**: any concurrent or async I/O may return it. Propagate, recancel, or assert unreachable as appropriate.
10. **Prefer `std.Io` over `std.posix`/`std.os.windows`**: if the stdlib offers a higher-level API, use it. Go to `std.posix.system` only when necessary.
