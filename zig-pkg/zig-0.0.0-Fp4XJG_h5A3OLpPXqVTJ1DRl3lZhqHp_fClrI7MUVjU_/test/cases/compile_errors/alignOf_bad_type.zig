export fn entry0() usize {
    return @alignOf(noreturn);
}
const S = struct { a: u32, b: noreturn };
export fn entry1() usize {
    return @alignOf(S);
}

// error
//
// :2:21: error: no align available for uninstantiable type 'noreturn'
// :6:21: error: no align available for uninstantiable type 'tmp.S'
// :4:11: note: struct declared here
