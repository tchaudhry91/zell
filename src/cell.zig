pub const Cell = packed struct {
    char: u21, // 21 bits
    fg: u9 = COLOR_DEFAULT, // 21 + 9 = 30
    bg: u9 = COLOR_DEFAULT, // 30 + 9 = 39
    bold: bool = false, // 39 + 1 = 40 bits
    italic: bool = false, // 40 + 1 = 41 bits
    underline: bool = false, // 41 + 1 = 42 bits
    reverse: bool = false, // 42 + 1  = 43 bits
    _padding: u21 = 0, // pad to 64 bits
};

pub const COLOR_DEFAULT: u9 = 256;
pub const EMPTY: Cell = .{ .char = ' ' };
