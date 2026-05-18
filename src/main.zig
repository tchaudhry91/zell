const std = @import("std");
const Io = std.Io;
const zell = @import("zell");

const WIDTH = 80;
const HEIGHT = 24;
const FRAMES = 400;
const FRAME_MS = 40;
const TRAIL_MAX: u8 = HEIGHT - 2;

fn trailColor(dist: usize) u9 {
    return switch (dist) {
        0 => 231, // white head
        1 => 82, // bright green
        2, 3 => 46,
        4...7 => 40,
        8...13 => 34,
        14...19 => 28,
        else => 22, // dim tail
    };
}

fn randomChar(rng: std.Random) u21 {
    return '!' + rng.intRangeLessThan(u21, 0, '~' - '!' + 1);
}

const Column = struct {
    head: i32,
    length: u8,
    delay: u32,
};

pub fn main(init: std.process.Init) !void {
    var seed: u64 = undefined;
    init.io.random(std.mem.asBytes(&seed));
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();

    const io = init.io;
    var stdout_buf: [8192]u8 = undefined;
    var file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buf);
    const writer = &file_writer.interface;

    var grid = try zell.init(init.gpa, writer, WIDTH, HEIGHT);
    defer grid.deinit();

    try grid.start();
    defer grid.stop() catch {};

    var cols: [WIDTH]Column = undefined;
    for (&cols) |*col| {
        col.* = .{
            .head = -1,
            .length = rng.intRangeLessThan(u8, 6, TRAIL_MAX),
            .delay = rng.intRangeLessThan(u32, 0, 60),
        };
    }

    for (0..FRAMES) |_| {
        grid.clear();

        for (&cols, 0..) |*col, x| {
            if (col.delay > 0) {
                col.delay -= 1;
                continue;
            }

            col.head += 1;

            for (0..@as(usize, col.length) + 1) |d| {
                const row = col.head - @as(i32, @intCast(d));
                if (row < 0 or row >= HEIGHT) continue;
                try grid.put(x, @intCast(row), .{
                    .char = randomChar(rng),
                    .fg = trailColor(d),
                });
            }

            if (col.head >= @as(i32, HEIGHT) + @as(i32, col.length)) {
                col.head = -1;
                col.delay = rng.intRangeLessThan(u32, 20, 80);
                col.length = rng.intRangeLessThan(u8, 6, TRAIL_MAX);
            }
        }

        try grid.flush();
        try io.sleep(.fromMilliseconds(FRAME_MS), .awake);
    }
}
