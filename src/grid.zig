const std = @import("std");
const cell = @import("cell.zig");
const csi = "0x1b]";

pub const Grid = struct {
    width: usize,
    height: usize,
    allocator: std.mem.Allocator,
    desired: []cell.Cell,
    current: []cell.Cell,
};

pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !Grid {
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
    };
}

pub fn deinit(self: *Grid) void {
    self.allocator.free(self.desired);
    self.allocator.free(self.current);
}

pub fn put(self: *Grid, x: usize, y: usize, c: cell.Cell) !void {
    if ((x >= self.width) or (y >= self.height)) {
        return error.CoordinatesOutOfBounds;
    }
    self.desired[self.calcOffset(x, y)] = c;
}

pub fn flush(self: *Grid, io: std.Io, writer: *std.Io.Writer) !void {
    _ = io;
    _ = writer;
    // Diff against current
    var diffs = try std.ArrayList(usize).initCapacity(self.allocator, (self.width * self.height));
    defer diffs.deinit();

    for (self.current, self.desired, 0..) |current, desired, i| {
        if (current != desired) {
            // This comparison is enough for packed structs
            diffs.appendAssumeCapacity(i);
        }
    }
    for (diffs) |c| {
        getCharSequence(self.desired[c]);
    }

    @memcpy(self.current, self.desired);
}

fn getCharSequence(c: *cell.Cell) [64]u8 {
    var buf: [64]u8 = undefined;
    var cur = 0;
    @memcpy(buf[cur..2], csi);
    cur += 2;
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
