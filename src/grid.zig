const std = @import("std");
const cell = @import("cell.zig");

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

inline fn calcOffset(self: *Grid, x: usize, y: usize) usize {
    return (x) + (y * self.width);
}
