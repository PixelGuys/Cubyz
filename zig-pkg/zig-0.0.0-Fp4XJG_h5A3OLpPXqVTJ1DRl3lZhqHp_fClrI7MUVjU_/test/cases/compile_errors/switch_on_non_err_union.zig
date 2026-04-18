pub fn main() void {
    false catch |err| switch (err) {
        else => {},
    };
}

// error
//
// :2:11: error: expected error union type, found 'bool'
