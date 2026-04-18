const S = struct { x: u32 };
export fn entry1() void {
    const s = asm volatile (""
        : [_] "=r" (-> S),
    );
    _ = s;
}
export fn entry2() void {
    var s: S = undefined;
    asm volatile (""
        : [_] "=r" (s),
    );
}

const U = union { x: u32 };
export fn entry3() void {
    const u = asm volatile (""
        : [_] "=r" (-> U),
    );
    _ = u;
}
export fn entry4() void {
    var u: U = undefined;
    asm volatile (""
        : [_] "=r" (u),
    );
}

// error
//
// :4:24: error: invalid inline assembly output type; 'tmp.S' does not have a guaranteed in-memory layout
// :1:11: note: struct declared here
// :11:21: error: invalid inline assembly output type; 'tmp.S' does not have a guaranteed in-memory layout
// :1:11: note: struct declared here
// :18:24: error: invalid inline assembly output type; 'tmp.U' does not have a guaranteed in-memory layout
// :15:11: note: union declared here
// :25:21: error: invalid inline assembly output type; 'tmp.U' does not have a guaranteed in-memory layout
// :15:11: note: union declared here
