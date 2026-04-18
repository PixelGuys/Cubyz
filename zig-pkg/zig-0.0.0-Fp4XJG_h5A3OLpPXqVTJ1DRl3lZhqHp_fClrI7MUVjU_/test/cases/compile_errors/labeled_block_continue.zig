export fn foo() void {
    const result: u32 = b: {
        continue :b 123;
    };
    _ = result;
}

// error
//
// :3:9: error: continue outside of loop or labeled switch expression
