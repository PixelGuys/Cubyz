export fn entry1() void {
    _ = @sizeOf(packed struct(u32) {
        x: u1,
        y: u24,
        z: u4,
    });
}
export fn entry2() void {
    _ = @sizeOf(packed struct(i31) {
        x: u4,
        y: u24,
        z: u4,
    });
}

export fn entry3() void {
    _ = @sizeOf(packed struct(void) {
        x: void,
    });
}

export fn entry4() void {
    _ = @sizeOf(packed struct(void) {});
}

export fn entry5() void {
    _ = @sizeOf(packed struct(noreturn) {});
}

export fn entry6() void {
    _ = @sizeOf(packed struct(f64) {
        x: u32,
        y: f32,
    });
}

export fn entry7() void {
    _ = @sizeOf(packed struct(*u32) {
        x: u4,
        y: u24,
        z: u4,
    });
}

// error
//
// :2:24: error: backing integer bit width does not match total bit width of fields
// :2:31: note: backing integer 'u32' has bit width '32'
// :2:24: note: struct fields have total bit width '29'
// :9:24: error: backing integer bit width does not match total bit width of fields
// :9:31: note: backing integer 'i31' has bit width '31'
// :9:24: note: struct fields have total bit width '32'
// :17:31: error: expected backing integer type, found 'void'
// :23:31: error: expected backing integer type, found 'void'
// :27:31: error: expected backing integer type, found 'noreturn'
// :31:31: error: expected backing integer type, found 'f64'
// :38:31: error: expected backing integer type, found '*u32'
