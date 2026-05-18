# zell

A tiny, dependency-free terminal rendering library for Zig.

zell gives you a grid of cells, a double buffer, and a diff engine. You call
`put`. It calls the terminal. No dependencies beyond the Zig standard library.

## Demo

```sh
zig build run
```

This runs a Matrix-style rain animation built on top of zell — a useful
stress-test for the diff engine and a nice way to see it in action.

## Installation

### Zig package manager

```sh
zig fetch --save https://github.com/tchaudhry/zell/archive/refs/heads/main.tar.gz
```

Then in your `build.zig`:

```zig
const zell_dep = b.dependency("zell", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("zell", zell_dep.module("zell"));
```

### Vendoring

Clone or copy `src/` into your project. It's three files with zero dependencies.

## API

```zig
const zell = @import("zell");
```

| Function | Description |
|---|---|
| `zell.init(allocator, writer, width, height)` | Create a `Grid` — a double-buffered cell grid. |
| `grid.put(x, y, cell)` | Write a cell into the back buffer at position `(x, y)`. |
| `grid.clear()` | Reset the back buffer to empty cells. |
| `grid.flush()` | Diff the back buffer against the front buffer, emit minimal ANSI escapes, then swap buffers. |
| `grid.resize(w, h)` | Resize the grid to new dimensions (discards cells outside the new bounds). |
| `grid.start()` / `grid.stop()` | Enter/exit the alternate screen buffer. |
| `grid.deinit()` | Free all memory. |

### The `Cell` type

```zig
pub const Cell = packed struct {
    char: u21,          // Unicode codepoint
    fg: u9,             // 256-color foreground (COLOR_DEFAULT = 256)
    bg: u9,             // 256-color background
    bold: bool,
    italic: bool,
    underline: bool,
    reverse: bool,
};
```

`COLOR_DEFAULT` (value `256`) means "use the terminal's default color."
`Cell.EMPTY` is a space character with default colors and no attributes.

## Example

```zig
const std = @import("std");
const zell = @import("zell");

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    // Set up buffered stdout
    var buf: [8192]u8 = undefined;
    var file_writer: std.Io.File.Writer = .init(.stdout(), io, &buf);
    const writer = &file_writer.interface;

    // Create a 40×10 grid
    var grid = try zell.init(init.gpa, writer, 40, 10);
    defer grid.deinit();

    try grid.start();
    defer grid.stop() catch {};

    // Draw some cells
    try grid.put(2, 1, .{ .char = 'H', .fg = 196 });  // red 'H'
    try grid.put(3, 1, .{ .char = 'i', .fg = 46 });   // green 'i'
    try grid.put(10, 5, .{ .char = '🦀', .fg = 208, .bold = true }); // bold orange crab

    // Flush diffs to the terminal
    try grid.flush();

    // Wait for Enter
    _ = try io.stdin().reader(io).readByte();
}
```

## Design

zell deliberately does **not**:

- Decide _what_ to draw — that's your job
- Handle terminal resize events (SIGWINCH) — you detect resize, you call `resize()`
- Re-layout or re-render after resize — cells outside new bounds are lost
- Handle keyboard/mouse input
- Manage scrollback — it always uses the alternate screen buffer

See [SPEC.md](SPEC.md) for the full design rationale.

## License

MIT — see [LICENSE](LICENSE).
