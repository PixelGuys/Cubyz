const Opaque = opaque {};
const Untagged = @Union(.auto, null, &.{"foo"}, &.{Opaque}, &.{.{}});
export fn entry() usize {
    return @sizeOf(Untagged);
}

// error
//
// :2:49: error: cannot directly embed opaque type 'tmp.Opaque' in union
// :2:49: note: opaque types have unknown size
// :1:16: note: opaque declared here
