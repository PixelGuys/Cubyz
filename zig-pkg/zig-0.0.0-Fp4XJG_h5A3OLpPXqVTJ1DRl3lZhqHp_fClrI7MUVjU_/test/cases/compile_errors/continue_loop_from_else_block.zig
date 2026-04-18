export fn entry1() void {
    var x: u32 = 0;
    result: while (x < 5) : (x += 1) {} else {
        continue :result;
    }
}

export fn entry2() void {
    result: for (0..5) |_| {} else {
        continue :result;
    }
}

// error
//
// :4:9: error: continue outside of loop or labeled switch expression
// :10:9: error: continue outside of loop or labeled switch expression
