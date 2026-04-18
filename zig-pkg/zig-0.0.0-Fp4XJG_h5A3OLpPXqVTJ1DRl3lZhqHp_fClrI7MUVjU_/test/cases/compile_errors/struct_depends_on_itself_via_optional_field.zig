const LhsExpr = struct {
    rhsExpr: ?AstObject,
};
const AstObject = union {
    lhsExpr: LhsExpr,
};
export fn entry() void {
    const lhsExpr = LhsExpr{ .rhsExpr = null };
    const obj = AstObject{ .lhsExpr = lhsExpr };
    _ = obj;
}

// error
//
// error: dependency loop with length 2
// :2:14: note: type 'tmp.LhsExpr' depends on type 'tmp.AstObject' for field declared here
// :5:14: note: type 'tmp.AstObject' depends on type 'tmp.LhsExpr' for field declared here
// note: eliminate any one of these dependencies to break the loop
