pub const Cell = packed struct {
    char: u21, // 21 bits
    fg: u8, // 21 + 8 = 29 bits
    bg: u8, // 29 + 8 = 37 bits
    bold: bool, // 37 + 1 = 38 bits
    italic: bool, // 38 + 1 = 39 bits
    underline: bool, // 39 + 1 = 40 bits
    reverse: bool, // 40 + 1  = 41 bits
    _padding: u23 = 0,
};
