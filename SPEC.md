# zell — Specification

zell is a tiny, dependency-free terminal cell-rendering library for Zig.

It gives you a grid of cells, a double buffer, and a diff engine. You call `put`. It calls the terminal.

## What it does
- Allocate a cell grid, width × height
- Accept `put(cell, x, y)` calls into a back buffer
- On `flush()`, diff the back buffer against the front buffer, emit the minimal set of ANSI escape sequences to bring the terminal into sync, and swap the buffers

## What it does NOT do
- Decide what to draw, or when to draw it
- Handle terminal resize events (SIGWINCH) — the app detects resize and calls `resize(w, h)` itself
- Re-layout or re-render content after resize — if the grid shrinks, cells outside the new bounds are simply lost
- Handle input (keyboard, mouse, etc.)
- Manage scrollback or the "main" terminal screen — it always uses the alternate screen buffer

## Goals
- Correct and fast diff-based rendering
- Minimal API surface: init, put, resize, flush, deinit
- Teach Zig 0.16.0 by doing the hard parts here
