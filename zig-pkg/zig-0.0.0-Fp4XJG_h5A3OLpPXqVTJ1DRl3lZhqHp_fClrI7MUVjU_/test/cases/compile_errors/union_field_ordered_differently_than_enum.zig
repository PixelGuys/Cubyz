const Tag = enum { a, b };

const Union = union(Tag) {
    b,
    a,
};

const BaseUnion = union(enum) {
    a,
    b,
};

const GeneratedTagUnion = union(@typeInfo(BaseUnion).@"union".tag_type.?) {
    b,
    a,
};

export fn entry() usize {
    return @sizeOf(Union) + @sizeOf(GeneratedTagUnion);
}

// error
//
// :3:15: error: union field order does not match tag enum field order
// :5:5: note: union field 'a' is index 1
// :1:20: note: enum field 'a' is index 0
