const std = @import("std");
const Io = std.Io;

const zell = @import("zell");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    _ = args;

    const io = init.io;

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    var grid = try zell.init(init.gpa, stdout_writer, 80, 24);
    defer grid.deinit();

    try grid.start();
    defer {
        grid.stop() catch {};
    }

    // ── Step 1: Draw a rainbow header ───────────────────────────────
    const title = "  ZELL  —  terminal cell rendering  ";
    const palette = [_]u8{ 196, 202, 208, 214, 220, 226, 190, 154, 118, 82, 46, 47, 48, 49, 50, 51, 45, 39, 33, 27, 21, 20, 19, 18, 17, 196, 202, 208, 214, 220, 226, 190, 154, 118, 82, 46, 47 };
    for (title, 0..) |ch, col| {
        try grid.put(col, 0, zell.Cell{ .char = ch, .fg = 0, .bg = palette[col % palette.len] });
    }
    try grid.flush();
    try io.sleep(.fromSeconds(1), .awake);

    // ── Step 2: Draw style examples (incremental, only changed cells) ──
    const examples = [_]struct { label: []const u8, cell: zell.Cell }{
        .{ .label = "Normal     ", .cell = .{ .char = 'H', .fg = 15 } },
        .{ .label = "Bold       ", .cell = .{ .char = 'H', .fg = 15, .bold = true } },
        .{ .label = "Italic     ", .cell = .{ .char = 'H', .fg = 15, .italic = true } },
        .{ .label = "Underline  ", .cell = .{ .char = 'H', .fg = 15, .underline = true } },
        .{ .label = "Reverse    ", .cell = .{ .char = 'H', .fg = 15, .bg = 7, .reverse = true } },
        .{ .label = "Bold+Italic", .cell = .{ .char = 'H', .fg = 15, .bold = true, .italic = true } },
        .{ .label = "All styles ", .cell = .{ .char = 'H', .fg = 15, .bold = true, .italic = true, .underline = true } },
    };
    for (examples, 0..) |ex, row| {
        for (ex.label, 0..) |ch, col| {
            try grid.put(col, @intCast(2 + row), zell.Cell{ .char = ch, .fg = 8 });
        }
        try grid.put(13, @intCast(2 + row), ex.cell);
    }
    try grid.flush();
    try io.sleep(.fromSeconds(1), .awake);

    // ── Step 3: Fill a block of color (one row at a time, visual effect) ──
    for (5..16) |row| {
        for (0..40) |col| {
            const hue: u8 = @intCast(16 + (col + row) % 216);
            try grid.put(col, row, zell.Cell{ .char = ' ', .bg = hue });
        }
        try grid.flush();
        try io.sleep(.fromMilliseconds(100), .awake);
    }

    try io.sleep(.fromSeconds(1), .awake);

    // ── Step 4: RESIZE to 40x15, redraw something completely different ──
    try grid.resize(40, 15);

    const message = "resized! 40x15 -- everything must redraw";
    for (message, 0..) |ch, col| {
        try grid.put(col, 0, zell.Cell{ .char = ch, .fg = 0, .bg = 47 });
    }
    try grid.flush();
    try io.sleep(.fromSeconds(1), .awake);

    // ── Step 5: Draw a pattern on the smaller grid ──
    for (2..grid.height) |row| {
        for (0..grid.width) |col| {
            const hue: u8 = @intCast(16 + col * 6);
            try grid.put(col, row, zell.Cell{
                .char = @intCast('A' + (col + row) % 26),
                .fg = hue,
                .bold = col % 2 == 0,
            });
        }
        try grid.flush();
        try io.sleep(.fromMilliseconds(50), .awake);
    }

    try io.sleep(.fromSeconds(1), .awake);

    // ── Step 6: RESIZE again to 80x24, draw a finale ──
    try grid.resize(80, 24);

    const goodbye = "  done. zell works!  ";
    for (goodbye, 0..) |ch, col| {
        try grid.put(col, 11, zell.Cell{ .char = ch, .fg = 0, .bg = 82 });
    }
    for (0..80) |col| {
        try grid.put(col, 12, zell.Cell{ .char = '▀', .fg = 82, .bg = 0 });
    }

    // footer
    const footer = "  exiting in 2 seconds...  ";
    for (footer, 0..) |ch, col| {
        try grid.put(col, 23, zell.Cell{ .char = ch, .fg = 0, .bg = 8 });
    }

    try grid.flush();
    try io.sleep(.fromSeconds(2), .awake);

    try grid.stop();
    try stdout_writer.flush();
}
