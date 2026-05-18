# Zig 0.16.0 Reference

> Condensed from the [0.16.0 release notes](https://ziglang.org/download/0.16.0/release-notes.html).
> This project uses **Zig 0.16.0**. Do not assume 0.15.x (or older) patterns.

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
- `io.async(func, .{args})` -> `Future(T)` — spawns a task, infallible.
- `io.concurrent(func, .{args})` -> `Future(T)` — requires actual concurrency, can fail.
- `future.await(io)` — blocks (logically) until done.
- `future.cancel(io)` — requests interrupt; may return `error.Canceled`.
- `std.Io.Group` — manage many tasks with shared lifetime.
- `std.Io.Batch` — low-level operation concurrency.
- `std.Io.Select` — wait until one or more tasks complete.
- `std.Io.Queue(T)` — MPMC queue with suspend/resume.

### Cancelation
- Most I/O operations now include `error.Canceled` in their error sets.
- `io.checkCancel()` — explicit cancelation points in CPU-bound work.
- `io.recancel()` — re-arms a cancelation request.
- `io.swapCancelProtection()` — makes cancelation unreachable in a scope.

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
| `std.once` | **removed** |

Lock-free primitives do **not** need `Io`.

### File System (`std.Io.Dir` / `std.Io.File`)
- `std.fs.Dir` → `std.Io.Dir`
- `std.fs.File` → `std.Io.File`
- Nearly every call now takes `io` as a parameter.
- `std.fs.cwd()` → `std.Io.Dir.cwd()`
- `fs.realpathAlloc` → `std.Io.Dir.realPathFileAbsoluteAlloc`
- `fs.selfExePath*` → `std.process.executablePath*` / `executableDirPath*`
- `fs.getCwd` → `std.process.currentPath(io, buf)` / `currentPathAlloc(io, allocator)`
- `fs.getAppDataDir` → **removed**
- Added `std.Io.Dir.walkSelectively` for skipping subtrees during walks.

### Networking
- All `std.net` APIs migrated to `std.Io`.
- Windows networking no longer uses `ws2_32.dll`; direct AFD access.

### Reader / Writer
- `std.io` → `std.Io`
- `std.Io.GenericReader` / `std.Io.AnyReader` → `std.Io.Reader` (non-generic)
- `std.Io.GenericWriter` / `std.Io.AnyWriter` → `std.Io.Writer`
- `FixedBufferStream` → **removed**; use `std.Io.Reader.fixed(data)` / `std.Io.Writer.fixed(buf)`.

### Time
- `std.time.Instant` / `std.time.Timer` → `std.Io.Timestamp`
- `std.time.timestamp` → `std.Io.Timestamp.now`

### Random / Entropy
- `std.crypto.random.bytes` → `io.random(&buf)`
- `std.crypto.random` interface → `std.Random.IoSource{ .io = io }.interface()`
- `io.randomSecure(&buf)` for cryptographically secure entropy (may fail).

### Process
- `std.process.Child.init(...); child.spawn(io);` → `std.process.spawn(io, ...)`
- `std.process.Child.run(allocator, io, ...)` → `std.process.run(allocator, io, ...)`
- `std.process.execv` → `std.process.replace(io, ...)`

### Format / Print
- `fmt.format` → `std.Io.Writer.print`
- `fmt.Formatter` → `Alt`
- `fmt.FormatOptions` → `Options`
- `fmt.bufPrintZ` → `bufPrintSentinel`
- `{D}` duration format specifier → **removed**

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
- `@EnumLiteral()` — the type of `.foo` enum literals

No builtins for `Float`, `Array`, `Optional`, `ErrorUnion`, `Opaque` — use normal syntax.

**Important**: it is no longer possible to reify error sets. Declare them explicitly with `error{ ... }`.

### `@cImport` Deprecated
Use `b.addTranslateC(...)` in the build system instead.

### `switch` Improvements
- `packed struct` and `packed union` may be used as switch prongs.
- Decl literals and result-type-dependent expressions work as prongs.
- Union tag captures allowed for all prongs.
- Prongs may contain errors not in the switched error set if they contain `=> comptime unreachable`.
- Switch prong captures may no longer **all** be discarded.
- Switching on `void` no longer unconditionally requires an `else` prong.

### Float ↔ Int Ergonomics
- Small integer coercion: if an integer type's full range fits in a float without rounding, it coerces implicitly.
- `@floor`, `@ceil`, `@round`, `@trunc` now convert floats to integers directly. `@intFromFloat` is deprecated (use `@trunc`).
- Unary float builtins now forward result types.

### Packed Types
- **Packed unions** require explicit backing integer: `packed union(u16) { ... }`
- **Packed unions** forbid unused bits.
- **Pointers forbidden** in `packed struct` and `packed union` fields.
- Equality comparisons on packed unions now work directly.

### Vectors
- **Runtime vector indexes forbidden**: coerce to array first.
- Vectors and arrays no longer support in-memory coercion.

### Pointers & Types
- **Returning local addresses is a compile error**.
- **Explicitly-aligned pointers are distinct** from unaligned but coerce.
- **Pointers to comptime-only types are no longer comptime-only**.
- **Lazy field analysis** — using a type as a namespace no longer forces resolution of all its fields.

---

## 3. Standard Library Removals & Renames

### Major Removals
- `std.Thread.Pool` → use `std.Io.Group` / `std.Io.async` / `std.Io.concurrent`
- `heap.ThreadSafeAllocator` → `heap.ArenaAllocator` is now lock-free thread-safe on its own
- `SegmentedList`
- `meta.declList`
- `builtin.subsystem`
- `std.once`
- `Io.GenericWriter`, `Io.AnyWriter`, `Io.null_writer`, `Io.CountingReader`
- `Thread.Mutex.Recursive`
- `fs.getAppDataDir`
- Most `std.posix` and `std.os.windows` medium-level abstractions
- All `*Z`, `*W`, `*Wasi` file system variants

### High-Impact Renames
| Old | New |
|-----|-----|
| `std.fs.Dir` | `std.Io.Dir` |
| `std.fs.File` | `std.Io.File` |
| `fs.File.read` / `readv` | `std.Io.File.readStreaming` |
| `fs.File.write` / `writev` | `std.Io.File.writeStreaming` |
| `fs.File.seekTo` / `seekBy` | `std.Io.File.Reader.seekTo` / `seekBy` |
| `fs.File.getEndPos` | `std.Io.File.length` |
| `fs.File.setEndPos` | `std.Io.File.setLength` |
| `fs.File.chmod` | `std.Io.File.setPermissions` |
| `fs.File.chown` | `std.Io.File.setOwner` |
| `fs.File.updateTimes` | `std.Io.File.setTimestamps` / `setTimestampsNow` |
| `fs.Dir.makeDir` | `std.Io.Dir.createDir` |
| `fs.Dir.makePath` | `std.Io.Dir.createDirPath` |
| `fs.Dir.rename` | `std.Io.Dir.rename` (takes two `Dir` params + `Io`) |
| `fs.realpath` | `std.Io.Dir.realPathFileAbsolute` |
| `fs.realpathAlloc` | `std.Io.Dir.realPathFileAbsoluteAlloc` |
| `fs.selfExePath` | `std.process.executablePath` |
| `fs.selfExeDirPath` | `std.process.executableDirPath` |
| `std.process.getCwd` | `std.process.currentPath` |
| `std.process.getCwdAlloc` | `std.process.currentPathAlloc` |
| `std.mem.indexOf*` | `std.mem.find*` |

### Containers
- `ArrayHashMap` / `AutoArrayHashMap` / `StringArrayHashMap` (managed) → **removed**
- `AutoArrayHashMapUnmanaged` → `array_hash_map.Auto`
- `StringArrayHashMapUnmanaged` → `array_hash_map.String`
- `ArrayHashMapUnmanaged` → `array_hash_map.Custom`
- `PriorityQueue` / `PriorityDequeue` no longer store an `Allocator`. Methods: `add`→`push`, `remove`→`pop`.

### Error Sets
- `error.RenameAcrossMountPoints` → `error.CrossDevice`
- `error.NotSameFileSystem` → `error.CrossDevice`
- `error.SharingViolation` → `error.FileBusy`
- `error.EnvironmentVariableNotFound` → `error.EnvironmentVariableMissing`
- `fs.Dir.readFileAlloc` limit reached → `error.StreamTooLong`

### Memory / MMap
- `std.posix.mlock` / `mlock2` / `mlockall` → `std.process.lockMemory` / `lockMemoryAll`
- `mmap` / `mprotect` flags now use struct booleans: `.{ .READ = true, .WRITE = true }`

### Debug Info / Stack Traces
- `std.debug.captureStackTrace` → `std.debug.captureCurrentStackTrace`
- `std.debug.dumpStackTrace` → `std.debug.dumpCurrentStackTrace`
- `std.debug.writeStackTrace` / `std.debug.writeCurrentStackTrace` now take `Io.Terminal`

---

## 4. Build System Changes

- **`@cImport` migration**: use `b.addTranslateC(...)`.
- **Local overrides**: `zig build --fork=/path/to/pkg` overrides any dependency.
- **Packages fetched into `zig-pkg/`** (project-local), then recompressed into global cache.
- **`--test-timeout <duration>`**: kills and restarts the test runner.
- **`--error-style {verbose,verbose_clear,minimal,minimal_clear}`**: replaces `--prominent-compile-errors`.
- **`--multiline-errors {indent,newline,none}`**: controls multi-line error formatting.
- **Temporary files**: `b.makeTempPath()` and `addRemoveDirTree` removed.
