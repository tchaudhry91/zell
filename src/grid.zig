const std = @import("std");
const cell = @import("cell.zig");

const csi = "\x1b[";

pub fn init(allocator: std.mem.Allocator, writer: *std.Io.Writer, width: usize, height: usize) !Grid {
    const current: []cell.Cell = try allocator.alloc(cell.Cell, width * height);
    errdefer allocator.free(current);
    @memset(current, cell.EMPTY);
    const desired: []cell.Cell = try allocator.alloc(cell.Cell, width * height);
    errdefer allocator.free(desired);
    @memset(desired, cell.EMPTY);
    return .{
        .allocator = allocator,
        .width = width,
        .height = height,
        .current = current,
        .desired = desired,
        .writer = writer,
    };
}

pub const Grid = struct {
    width: usize,
    height: usize,
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    desired: []cell.Cell,
    current: []cell.Cell,

    pub fn deinit(self: *Grid) void {
        self.allocator.free(self.desired);
        self.allocator.free(self.current);
    }

    pub fn start(self: *Grid) !void {
        try self.writer.print("{s}?1049h", .{csi});
        try self.writer.print("{s}?25l", .{csi});
    }

    pub fn stop(self: *Grid) !void {
        try self.writer.print("{s}?1049l", .{csi});
        try self.writer.print("{s}?25h", .{csi});
    }

    pub fn put(self: *Grid, x: usize, y: usize, c: cell.Cell) !void {
        if ((x >= self.width) or (y >= self.height)) {
            return error.CoordinatesOutOfBounds;
        }
        self.desired[self.calcOffsetFromCoordinates(x, y)] = c;
    }

    pub fn flush(self: *Grid) !void {
        // Diff against current
        var diffs = try std.ArrayList(usize).initCapacity(self.allocator, (self.width * self.height));
        defer diffs.deinit(self.allocator);

        for (self.current, self.desired, 0..) |current, desired, i| {
            if (current != desired) {
                // This comparison is enough for packed structs
                diffs.appendAssumeCapacity(i);
            }
        }
        for (diffs.items) |i| {
            const coords = calcCoordinatesFromOffset(self, i);
            try writeCharJumpSequence(self.writer, coords.x, coords.y);
            try writeCharSequence(self.writer, &self.desired[i]);
        }
        try self.writer.flush();

        @memcpy(self.current, self.desired);
    }

    pub fn resize(self: *Grid, width: usize, height: usize) !void {
        self.deinit();
        self.* = try init(self.allocator, self.writer, width, height);
        try self.writer.print("{s}2J", .{csi});
    }

    inline fn writeCharJumpSequence(writer: *std.Io.Writer, x: usize, y: usize) !void {
        try writer.print("{s}{d};{d}H", .{ csi, y + 1, x + 1 });
    }

    fn writeCharSequence(writer: *std.Io.Writer, c: *cell.Cell) !void {
        // optimize this later
        const attrs = [_]struct { name: []const u8, code: u8 }{
            .{ .name = "bold", .code = 1 },
            .{ .name = "italic", .code = 3 },
            .{ .name = "underline", .code = 4 },
            .{ .name = "reverse", .code = 7 },
        };
        try writer.print("{s}0", .{csi}); // Reset
        inline for (attrs) |attr| {
            if (@field(c, attr.name)) {
                try writer.print(";{d}", .{attr.code});
            }
        }
        if (c.fg != 0) {
            try writer.print(";38;5;{d}", .{c.fg});
        }
        if (c.bg != 0) {
            try writer.print(";48;5;{d}", .{c.bg});
        }
        try writer.print("m{u}", .{c.char});
    }

    inline fn calcOffsetFromCoordinates(self: *Grid, x: usize, y: usize) usize {
        return (x) + (y * self.width);
    }

    inline fn calcCoordinatesFromOffset(self: *Grid, offset: usize) struct { x: usize, y: usize } {
        return .{
            .x = offset % self.width,
            .y = offset / self.width,
        };
    }
};
