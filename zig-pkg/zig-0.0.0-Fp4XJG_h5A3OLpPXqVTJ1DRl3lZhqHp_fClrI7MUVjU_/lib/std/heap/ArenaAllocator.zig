//! This allocator takes an existing allocator, wraps it, and provides an interface where
//! you can allocate and then free it all together. Calls to free an individual item only
//! free the item if it was the most recent allocation, otherwise calls to free do
//! nothing.
//!
//! The `Allocator` implementation provided is threadsafe, given that `child_allocator`
//! is threadsafe as well.
const ArenaAllocator = @This();

child_allocator: Allocator,
state: State,

/// Inner state of ArenaAllocator. Can be stored rather than the entire ArenaAllocator
/// as a memory-saving optimization.
///
/// Default initialization of this struct is deprecated; use `init` instead.
pub const State = struct {
    used_list: ?*Node = null,
    free_list: ?*Node = null,

    pub const init: State = .{
        .used_list = null,
        .free_list = null,
    };

    pub fn promote(state: State, child_allocator: Allocator) ArenaAllocator {
        return .{
            .child_allocator = child_allocator,
            .state = state,
        };
    }
};

pub fn allocator(arena: *ArenaAllocator) Allocator {
    return .{
        .ptr = arena,
        .vtable = &.{
            .alloc = alloc,
            .resize = resize,
            .remap = remap,
            .free = free,
        },
    };
}

pub fn init(child_allocator: Allocator) ArenaAllocator {
    return State.init.promote(child_allocator);
}

/// Not threadsafe.
pub fn deinit(arena: ArenaAllocator) void {
    // NOTE: When changing this, make sure `reset()` is adjusted accordingly!

    for ([_]?*Node{ arena.state.used_list, arena.state.free_list }) |first_node| {
        var it = first_node;
        while (it) |node| {
            // this has to occur before the free because the free frees node
            it = node.next;
            arena.child_allocator.rawFree(node.allocatedSliceUnsafe(), .of(Node), @returnAddress());
        }
    }
}

/// Queries the current memory use of this arena.
/// This will **not** include the storage required for internal keeping.
///
/// Not threadsafe.
pub fn queryCapacity(arena: ArenaAllocator) usize {
    var capacity: usize = 0;
    for ([_]?*Node{ arena.state.used_list, arena.state.free_list }) |first_node| {
        capacity += countListCapacity(first_node);
    }
    return capacity;
}
fn countListCapacity(first_node: ?*Node) usize {
    var capacity: usize = 0;
    var it = first_node;
    while (it) |node| : (it = node.next) {
        // Compute the actually allocated size excluding the
        // linked list node.
        capacity += node.size.toInt() - @sizeOf(Node);
    }
    return capacity;
}

pub const ResetMode = union(enum) {
    /// Releases all allocated memory in the arena.
    free_all,
    /// This will pre-heat the arena for future allocations by allocating a
    /// large enough buffer for all previously done allocations.
    /// Preheating will speed up the allocation process by invoking the backing allocator
    /// less often than before. If `reset()` is used in a loop, this means that after the
    /// biggest operation, no memory allocations are performed anymore.
    retain_capacity,
    /// This is the same as `retain_capacity`, but the memory will be shrunk to
    /// this value if it exceeds the limit.
    retain_with_limit: usize,
};
/// Resets the arena allocator and frees all allocated memory.
///
/// `mode` defines how the currently allocated memory is handled.
/// See the variant documentation for `ResetMode` for the effects of each mode.
///
/// The function will return whether the reset operation was successful or not.
/// If the reallocation  failed `false` is returned. The arena will still be fully
/// functional in that case, all memory is released. Future allocations just might
/// be slower.
///
/// Not threadsafe.
///
/// NOTE: If `mode` is `free_all`, the function will always return `true`.
pub fn reset(arena: *ArenaAllocator, mode: ResetMode) bool {
    // Some words on the implementation:
    // The reset function can be implemented with two basic approaches:
    // - Counting how much bytes were allocated since the last reset, and storing that
    //   information in State. This will make reset fast and alloc only a teeny tiny bit
    //   slower.
    // - Counting how much bytes were allocated by iterating the chunk linked list. This
    //   will make reset slower, but alloc() keeps the same speed when reset() as if reset()
    //   would not exist.
    //
    // The second variant was chosen for implementation, as with more and more calls to reset(),
    // the function will get faster and faster. At one point, the complexity of the function
    // will drop to amortized O(1), as we're only ever having a single chunk that will not be
    // reallocated, and we're not even touching the backing allocator anymore.
    //
    // Thus, only the first hand full of calls to reset() will actually need to iterate the linked
    // list, all future calls are just taking the first node, and only resetting the `end_index`
    // value.

    const limit: ?usize = switch (mode) {
        .retain_capacity => null,
        .retain_with_limit => |limit| limit,
        .free_all => 0,
    };
    if (limit == 0) {
        // just reset when we don't have anything to reallocate
        arena.deinit();
        arena.state = .init;
        return true;
    }

    const used_capacity = countListCapacity(arena.state.used_list);
    const free_capacity = countListCapacity(arena.state.free_list);

    const new_used_capacity = if (limit) |lim| @min(lim, used_capacity) else used_capacity;
    const new_free_capacity = if (limit) |lim| @min(lim - new_used_capacity, free_capacity) else free_capacity;

    var ok = true;

    for (
        [_]*?*Node{ &arena.state.used_list, &arena.state.free_list },
        [_]usize{ new_used_capacity, new_free_capacity },
    ) |first_node_ptr, new_capacity| {
        // Free all nodes except for the last one
        var it = first_node_ptr.*;
        const node: *Node = while (it) |node| {
            // this has to occur before the free because the free frees node
            it = node.next;
            if (it == null) break node;
            arena.child_allocator.rawFree(node.allocatedSliceUnsafe(), .of(Node), @returnAddress());
        } else {
            continue;
        };
        const allocated_slice = node.allocatedSliceUnsafe();

        // Align backwards to always stay below limit.
        const new_size = mem.alignBackward(usize, @sizeOf(Node) + new_capacity, 2);

        if (new_size == @sizeOf(Node)) {
            arena.child_allocator.rawFree(allocated_slice, .of(Node), @returnAddress());
            first_node_ptr.* = null;
            continue;
        }

        node.end_index = 0;
        first_node_ptr.* = node;

        if (allocated_slice.len == new_size) {
            // perfect, no need to invoke the child_allocator
            continue;
        }

        if (arena.child_allocator.rawResize(allocated_slice, .of(Node), new_size, @returnAddress())) {
            // successful resize
            node.size = .fromInt(new_size);
        } else {
            // manual realloc
            const new_ptr = arena.child_allocator.rawAlloc(new_size, .of(Node), @returnAddress()) orelse {
                // we failed to preheat the arena properly, signal this to the user.
                ok = false;
                continue;
            };
            arena.child_allocator.rawFree(allocated_slice, .of(Node), @returnAddress());
            const new_first_node: *Node = @ptrCast(@alignCast(new_ptr));
            new_first_node.* = .{
                .size = .fromInt(new_size),
                .end_index = 0,
                .next = null,
            };
            first_node_ptr.* = new_first_node;
        }
    }

    return ok;
}

/// Concurrent accesses to node pointers generally have to have acquire/release
/// semantics to guarantee that newly allocated notes are in a valid state when
/// being inserted into a list. Exceptions are possible, e.g. a cmpxchg loop that
/// never accesses the node returned on failure can use monotonic semantics on
/// failure, but must still use release semantics on success to protect the node
/// it's trying to push.
const Node = struct {
    /// Only meant to be accessed indirectly via the methods supplied by this type,
    /// except if the node is owned by the thread accessing it.
    /// Must always be an even number to accommodate `resize` bit.
    size: Size,
    /// Any increase of `end_index` has to use acquire semantics;
    /// any decrease of `end_index` that invalidates (formerly) active allocations
    /// has to use release semantics.
    /// This guarantees that all accesses to memory that's about to be freed
    /// happen-before the free is published.
    /// Since `size` can only grow and never shrink, memory access depending on
    /// any `end_index` <= any `size` can never be OOB.
    end_index: usize,
    /// This field should only be accessed if the node is owned by the thread
    /// accessing it.
    next: ?*Node,

    const Size = packed struct(usize) {
        resizing: bool,
        _: @Int(.unsigned, @bitSizeOf(usize) - 1) = 0,

        fn fromInt(int: usize) Size {
            assert(int >= @sizeOf(Node));
            const size: Size = @bitCast(int);
            assert(!size.resizing);
            return size;
        }

        fn toInt(size: Size) usize {
            var int = size;
            int.resizing = false;
            return @bitCast(int);
        }

        comptime {
            assert(Size{ .resizing = true } == @as(Size, @bitCast(@as(usize, 1))));
        }
    };

    fn loadBuf(node: *Node) []u8 {
        // `size` can only ever grow, so the buffer returned by this function is
        // always valid memory.
        const size = @atomicLoad(Size, &node.size, .monotonic);
        return @as([*]u8, @ptrCast(node))[0..size.toInt()][@sizeOf(Node)..];
    }

    /// Returns allocated slice or `null` if node is already (being) resized.
    fn beginResize(node: *Node) ?[]u8 {
        const size = @atomicRmw(Size, &node.size, .Or, .{ .resizing = true }, .acquire); // syncs with release in `endResize`
        if (size.resizing) return null;
        return @as([*]u8, @ptrCast(node))[0..size.toInt()];
    }

    fn endResize(node: *Node, size: usize, prev_size: usize) void {
        assert(size >= prev_size); // nodes must not shrink
        assert(@atomicLoad(Size, &node.size, .unordered).toInt() == prev_size);
        return @atomicStore(Size, &node.size, .fromInt(size), .release); // syncs with acquire in `beginResize`
    }

    /// Not threadsafe.
    fn allocatedSliceUnsafe(node: *Node) []u8 {
        return @as([*]u8, @ptrCast(node))[0..node.size.toInt()];
    }
};

fn loadFirstNode(arena: *ArenaAllocator) ?*Node {
    return @atomicLoad(?*Node, &arena.state.used_list, .acquire); // syncs with release in successful `tryPushNode`
}

const PushResult = union(enum) {
    success,
    failure: ?*Node,
};
fn tryPushNode(arena: *ArenaAllocator, node: *Node) PushResult {
    assert(node != node.next);
    if (@cmpxchgStrong( // strong because retrying means discarding a fitting node -> expensive
        ?*Node,
        &arena.state.used_list,
        node.next,
        node,
        .release, // syncs with acquire in failure path or `loadFirstNode`
        .acquire, // syncs with release in success path
    )) |old_node| {
        return .{ .failure = old_node };
    } else {
        return .success;
    }
}

fn stealFreeList(arena: *ArenaAllocator) ?*Node {
    // We don't need acq_rel here because we're always swapping in `null`, so
    // there's no node we'd need to release.
    return @atomicRmw(?*Node, &arena.state.free_list, .Xchg, null, .acquire); // syncs with release in `pushFreeList`
}

fn pushFreeList(arena: *ArenaAllocator, first: *Node, last: *Node) void {
    assert(first != last.next);
    assert(first != first.next);
    assert(last != last.next);
    while (@cmpxchgWeak(
        ?*Node,
        &arena.state.free_list,
        last.next,
        first,
        .release, // syncs with acquire in `stealFreeList`
        .monotonic, // we never access any fields of `old_free_list`, we only care about the pointer
    )) |old_free_list| {
        last.next = old_free_list;
    }
}

fn alignedIndex(buf_ptr: [*]u8, end_index: usize, alignment: Alignment) usize {
    // Wrapping arithmetic to avoid overflows since `end_index` isn't bounded by
    // `size`. This is always ok since the max alignment in byte units is also
    // the max value of `usize` so wrapped values are correctly aligned anyway.
    return alignment.forward(@intFromPtr(buf_ptr) +% end_index) -% @intFromPtr(buf_ptr);
}

fn alloc(ctx: *anyopaque, n: usize, alignment: Alignment, ret_addr: usize) ?[*]u8 {
    const arena: *ArenaAllocator = @ptrCast(@alignCast(ctx));
    _ = ret_addr;

    assert(n > 0);

    var cur_first_node = arena.loadFirstNode();

    var cur_new_node: ?*Node = null;
    defer if (cur_new_node) |node| {
        node.next = null; // optimize for empty free list
        arena.pushFreeList(node, node);
    };

    retry: while (true) {
        const first_node: ?*Node, const prev_size: usize = first_node: {
            const node = cur_first_node orelse break :first_node .{ null, 0 };
            const buf = node.loadBuf();

            // To avoid using a CAS loop in the hot path we atomically increase
            // `end_index` by a large enough amount to be able to always provide
            // the required alignment within the reserved memory. To recover the
            // space this potentially wastes we try to subtract the 'overshoot'
            // with a single cmpxchg afterwards, which may fail.

            const alignable = n + alignment.toByteUnits() - 1;
            const end_index = @atomicRmw(usize, &node.end_index, .Add, alignable, .acquire); // acquire any memory that may have been freed
            const aligned_index = alignedIndex(buf.ptr, end_index, alignment);
            assert(end_index + alignable >= aligned_index + n);
            if (end_index + alignable != aligned_index + n) {
                _ = @cmpxchgStrong(
                    usize,
                    &node.end_index,
                    end_index + alignable,
                    aligned_index + n,
                    .monotonic, // no need to release alignment padding; there's no one accessing it!
                    .monotonic,
                );
            }

            if (aligned_index + n > buf.len) break :first_node .{ node, buf.len };
            return buf[aligned_index..][0..n].ptr;
        };

        resize: {
            // Before attempting to get our hands on a new node, we try to resize
            // the one we're currently holding. This is an exclusive operation;
            // if another thread is already in this section we can never resize.

            const node = first_node orelse break :resize;
            const allocated_slice = node.beginResize() orelse break :resize;
            var size = allocated_slice.len;
            defer node.endResize(size, allocated_slice.len);

            const buf = allocated_slice[@sizeOf(Node)..];
            const end_index = @atomicLoad(usize, &node.end_index, .monotonic);
            const aligned_index = alignedIndex(buf.ptr, end_index, alignment);
            const new_size = mem.alignForward(usize, @sizeOf(Node) + aligned_index + n, 2);

            if (new_size <= allocated_slice.len) {
                // A `resize` or `free` call managed to sneak in and we need to
                // guarantee that `size` is only ever increased; retry!
                continue :retry;
            }

            if (arena.child_allocator.rawResize(allocated_slice, .of(Node), new_size, @returnAddress())) {
                size = new_size;

                // strong because a spurious failure could result in suboptimal
                // usage of this node
                if (null == @cmpxchgStrong(
                    usize,
                    &node.end_index,
                    end_index,
                    aligned_index + n,
                    .acquire, // acquire any memory that may have been freed
                    .monotonic,
                )) {
                    const new_buf = allocated_slice.ptr[0..new_size][@sizeOf(Node)..];
                    return new_buf[aligned_index..][0..n].ptr;
                }
            }
        }

        // We need a new node! First, we search `free_list` for one that's big
        // enough, if we don't find one there we fall back to allocating a new
        // node with `child_allocator` (if we haven't already done that!).

        from_free_list: {
            // We 'steal' the entire free list to operate on it without other
            // threads getting up into our business.
            // This is a rather pragmatic approach, but since the free list isn't
            // used very frequently it's fine performance-wise, even under load.
            // Also this avoids the ABA problem; stealing the list with an atomic
            // swap doesn't introduce any potentially stale `next` pointers.

            const free_list = arena.stealFreeList() orelse break :from_free_list;

            const first_free: *Node, const last_free: *Node, const node: *Node, const prev: ?*Node = find: {
                var best_fit_prev: ?*Node = null;
                var best_fit: ?*Node = null;
                var best_fit_diff: usize = std.math.maxInt(usize);

                var it_prev: ?*Node = null;
                var it: ?*Node = free_list;
                while (it) |node| : ({
                    it_prev = node;
                    it = node.next;
                }) {
                    assert(!node.size.resizing);
                    const buf = node.allocatedSliceUnsafe()[@sizeOf(Node)..];
                    const aligned_index = alignedIndex(buf.ptr, 0, alignment);

                    const diff = aligned_index + n -| buf.len;
                    if (diff < best_fit_diff) {
                        best_fit_prev = it_prev;
                        best_fit = node;
                        best_fit_diff = diff;
                    }
                }

                break :find .{ free_list, it_prev.?, best_fit.?, best_fit_prev };
            };

            const aligned_index, const need_resize = aligned_index: {
                const buf = node.allocatedSliceUnsafe()[@sizeOf(Node)..];
                const aligned_index = alignedIndex(buf.ptr, 0, alignment);
                break :aligned_index .{ aligned_index, aligned_index + n > buf.len };
            };

            if (need_resize) {
                // Ideally we want to use all nodes in `free_list` eventually,
                // so even if none fit we'll try to resize the one that was the
                // closest to being large enough.
                const new_size = mem.alignForward(usize, @sizeOf(Node) + aligned_index + n, 2);
                if (arena.child_allocator.rawResize(node.allocatedSliceUnsafe(), .of(Node), new_size, @returnAddress())) {
                    node.size = .fromInt(new_size);
                } else {
                    arena.pushFreeList(first_free, last_free);
                    break :from_free_list; // we couldn't find a fitting free node
                }
            }

            const buf = node.allocatedSliceUnsafe()[@sizeOf(Node)..];
            const old_next = node.next;

            node.end_index = aligned_index + n;
            node.next = first_node;

            switch (arena.tryPushNode(node)) {
                .success => {
                    // Finish removing node from free list.
                    if (prev) |p| p.next = old_next;

                    // Push remaining stolen free list back onto `arena.state.free_list`.
                    const new_first_free = if (node == first_free) old_next else first_free;
                    const new_last_free = if (node == last_free) prev else last_free;
                    if (new_first_free) |first| {
                        const last = new_last_free.?;
                        arena.pushFreeList(first, last);
                    }

                    return buf[aligned_index..][0..n].ptr;
                },
                .failure => |old_first_node| {
                    // restore free list to as we found it
                    node.next = old_next;
                    arena.pushFreeList(first_free, last_free);

                    cur_first_node = old_first_node;
                    continue :retry; // there's a new first node; retry!
                },
            }
        }

        const new_node: *Node = new_node: {
            if (cur_new_node) |new_node| {
                break :new_node new_node;
            } else {
                @branchHint(.cold);
            }

            const size: Node.Size = size: {
                const min_size = @sizeOf(Node) + alignment.toByteUnits() + n;
                const big_enough_size = prev_size + min_size + 16;
                const size = mem.alignForward(usize, big_enough_size + big_enough_size / 2, 2);
                break :size .fromInt(size);
            };
            const ptr = arena.child_allocator.rawAlloc(size.toInt(), .of(Node), @returnAddress()) orelse
                return null;
            const new_node: *Node = @ptrCast(@alignCast(ptr));
            new_node.* = .{
                .size = size,
                .end_index = undefined, // set below
                .next = undefined, // set below
            };
            cur_new_node = new_node;
            break :new_node new_node;
        };

        const buf = new_node.allocatedSliceUnsafe()[@sizeOf(Node)..];
        const aligned_index = alignedIndex(buf.ptr, 0, alignment);
        assert(new_node.size.toInt() >= @sizeOf(Node) + aligned_index + n);

        new_node.end_index = aligned_index + n;
        new_node.next = first_node;

        switch (arena.tryPushNode(new_node)) {
            .success => {
                cur_new_node = null;
                return buf[aligned_index..][0..n].ptr;
            },
            .failure => |old_first_node| {
                cur_first_node = old_first_node;
            },
        }
    }
}

fn resize(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) bool {
    const arena: *ArenaAllocator = @ptrCast(@alignCast(ctx));
    _ = alignment;
    _ = ret_addr;

    assert(memory.len > 0);
    assert(new_len > 0);

    const node = arena.loadFirstNode().?;
    const buf_ptr = @as([*]u8, @ptrCast(node)) + @sizeOf(Node);

    const cur_end_index = @atomicLoad(usize, &node.end_index, .monotonic);

    if (buf_ptr + cur_end_index != memory.ptr + memory.len) {
        // It's not the most recent allocation, so it cannot be expanded,
        // but it's fine if they want to make it smaller.
        return new_len <= memory.len;
    }

    if (new_len <= memory.len) {
        const new_end_index = cur_end_index - (memory.len - new_len);
        assert(buf_ptr + new_end_index == memory.ptr + new_len);

        _ = @cmpxchgStrong(
            usize,
            &node.end_index,
            cur_end_index,
            new_end_index,
            .release, // release freed memory
            .monotonic,
        );
        return true; // Shrinking allocations should always succeed.
    }

    // Saturating arithmetic because `end_index` is not guaranteed to be `<= size`.
    // The allocation we're trying to resize *could* belong to a different node!
    if (node.loadBuf().len -| cur_end_index >= new_len - memory.len) {
        const new_end_index = cur_end_index + (new_len - memory.len);
        assert(buf_ptr + new_end_index == memory.ptr + new_len);

        return null == @cmpxchgStrong(
            usize,
            &node.end_index,
            cur_end_index,
            new_end_index,
            .acquire, // acquire any memory that may have been freed
            .monotonic,
        );
    }

    return false;
}

fn remap(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
    return if (resize(ctx, memory, alignment, new_len, ret_addr)) memory.ptr else null;
}

fn free(ctx: *anyopaque, memory: []u8, alignment: Alignment, ret_addr: usize) void {
    const arena: *ArenaAllocator = @ptrCast(@alignCast(ctx));
    _ = alignment;
    _ = ret_addr;

    assert(memory.len > 0);

    const node = arena.loadFirstNode().?;
    const buf_ptr = @as([*]u8, @ptrCast(node)) + @sizeOf(Node);

    const cur_end_index = @atomicLoad(usize, &node.end_index, .monotonic);

    if (buf_ptr + cur_end_index != memory.ptr + memory.len) {
        // Not the most recent allocation; we cannot free it.
        return;
    }

    const new_end_index = cur_end_index - memory.len;
    assert(buf_ptr + new_end_index == memory.ptr);

    _ = @cmpxchgStrong(
        usize,
        &node.end_index,
        cur_end_index,
        new_end_index,
        .release, // release freed memory
        .monotonic,
    );
}

const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;

test "reset with preheating" {
    var arena_allocator = ArenaAllocator.init(std.testing.allocator);
    defer arena_allocator.deinit();
    // provides some variance in the allocated data
    var rng_src = std.Random.DefaultPrng.init(std.testing.random_seed);
    const random = rng_src.random();
    var rounds: usize = 25;
    while (rounds > 0) {
        rounds -= 1;
        _ = arena_allocator.reset(.retain_capacity);
        var alloced_bytes: usize = 0;
        const total_size: usize = random.intRangeAtMost(usize, 256, 16384);
        while (alloced_bytes < total_size) {
            const size = random.intRangeAtMost(usize, 16, 256);
            const alignment: Alignment = .@"32";
            const slice = try arena_allocator.allocator().alignedAlloc(u8, alignment, size);
            try std.testing.expect(alignment.check(@intFromPtr(slice.ptr)));
            try std.testing.expectEqual(size, slice.len);
            alloced_bytes += slice.len;
        }
    }
}

test "reset while retaining a buffer" {
    var arena_allocator = ArenaAllocator.init(std.testing.allocator);
    defer arena_allocator.deinit();
    const a = arena_allocator.allocator();

    // Create two internal buffers
    _ = try a.alloc(u8, 1);
    _ = try a.alloc(u8, 1000);

    try std.testing.expect(arena_allocator.state.used_list != null);

    // Check that we have at least two buffers
    try std.testing.expect(arena_allocator.state.used_list.?.next != null);

    // This retains the first allocated buffer
    try std.testing.expect(arena_allocator.reset(.{ .retain_with_limit = 2 }));
    try std.testing.expect(arena_allocator.state.used_list.?.next == null);
    try std.testing.expectEqual(2, arena_allocator.queryCapacity());
}

test "fuzz multi threaded" {
    @disableInstrumentation();
    if (@import("builtin").single_threaded) return error.SkipZigTest;

    const gpa = std.heap.smp_allocator;

    var io_instance: std.Io.Threaded = .init(gpa, .{});
    defer io_instance.deinit();

    var arena_state: ArenaAllocator.State = .init;
    // No need to deinit arena_state, all allocations are in `sample_buffer`!

    const buffer_size = FuzzContext.max_alloc_count * FuzzContext.max_alloc_size;

    const control_buffer = try gpa.alloc(u8, buffer_size);
    defer gpa.free(control_buffer);
    var control_instance: std.heap.FixedBufferAllocator = .init(control_buffer);

    const sample_buffer = try gpa.alloc(u8, buffer_size);
    defer gpa.free(sample_buffer);
    var sample_instance: FuzzAllocator = .init(sample_buffer);

    try std.testing.fuzz(FuzzContext.Init{
        .threaded_instance = &io_instance,
        .arena_state = &arena_state,
        .control_instance = &control_instance,
        .sample_instance = &sample_instance,
    }, fuzzMultiThreaded, .{});
}

fn fuzzMultiThreaded(fuzz_init: FuzzContext.Init, smith: *std.testing.Smith) anyerror!void {
    @disableInstrumentation();
    const testing = std.testing;
    const io = fuzz_init.threaded_instance.io();

    fuzz_init.sample_instance.prepareFailures(smith);

    const control_allocator = fuzz_init.control_instance.threadSafeAllocator();
    const sample_child_allocator = fuzz_init.sample_instance.allocator();

    var arena_instance = fuzz_init.arena_state.*.promote(sample_child_allocator);
    defer fuzz_init.arena_state.* = arena_instance.state;

    var ctx: FuzzContext = .init(
        control_allocator,
        arena_instance.allocator(),
    );
    defer ctx.deinit();

    var group: std.Io.Group = .init;
    defer group.cancel(io);

    var n_allocs: usize = 0;
    var n_actions: usize = 0;
    while (!smith.eosWeightedSimple(99, 1) and n_actions < FuzzContext.max_action_count) {
        errdefer comptime unreachable;

        const weights: []const testing.Smith.Weight = if (n_allocs == FuzzContext.max_alloc_count)
            &.{
                .value(FuzzContext.Action, .resize, 1),
                .value(FuzzContext.Action, .remap, 1),
                .value(FuzzContext.Action, .free, 1),
            }
        else
            &.{
                .value(FuzzContext.Action, .resize, 1),
                .value(FuzzContext.Action, .remap, 1),
                .value(FuzzContext.Action, .free, 1),
                .value(FuzzContext.Action, .alloc, 3),
            };
        switch (smith.valueWeighted(FuzzContext.Action, weights)) {
            .alloc => {
                const alloc_index = n_allocs;
                n_allocs += 1;
                ctx.allocs[alloc_index].common.len = .free;
                group.concurrent(io, FuzzContext.doOneAlloc, .{
                    &ctx,
                    nextLen(smith),
                    smith.valueRangeAtMost(
                        Alignment,
                        .@"1",
                        .fromByteUnits(2 * std.heap.page_size_max),
                    ),
                    @enumFromInt(alloc_index),
                }) catch unreachable;
            },
            .resize => group.concurrent(io, FuzzContext.doOneResize, .{ &ctx, nextLen(smith) }) catch unreachable,
            .remap => group.concurrent(io, FuzzContext.doOneRemap, .{ &ctx, nextLen(smith) }) catch unreachable,
            .free => group.concurrent(io, FuzzContext.doOneFree, .{&ctx}) catch unreachable,
        }
        n_actions += 1;
    }

    try group.await(io);
    try ctx.check(n_allocs);

    // This also covers the `deinit` logic since `free_all` uses it internally.

    const old_capacity = arena_instance.queryCapacity();
    const reset_mode: ResetMode = switch (smith.value(@typeInfo(ResetMode).@"union".tag_type.?)) {
        .free_all => .free_all,
        .retain_capacity => .retain_capacity,
        .retain_with_limit => .{ .retain_with_limit = smith.value(usize) },
    };
    const ok = arena_instance.reset(reset_mode);
    const new_capacity = arena_instance.queryCapacity();
    switch (reset_mode) {
        .free_all => {
            try testing.expect(ok);
            try testing.expectEqual(0, new_capacity);
            fuzz_init.sample_instance.reset();
        },
        .retain_with_limit => |limit| if (ok) try testing.expect(new_capacity <= limit),
        .retain_capacity => if (ok) try testing.expectEqual(old_capacity, new_capacity),
    }

    fuzz_init.control_instance.reset();
}
fn nextLen(smith: *std.testing.Smith) @typeInfo(FuzzContext.Alloc.Len).@"enum".tag_type {
    @disableInstrumentation();
    const BackingInt = @typeInfo(FuzzContext.Alloc.Len).@"enum".tag_type;
    return smith.valueRangeAtMost(BackingInt, 1, FuzzContext.max_alloc_size);
}

const FuzzContext = struct {
    control_allocator: Allocator,
    sample_allocator: Allocator,

    last_alloc_index: Alloc.Index,
    allocs: [max_alloc_count]Alloc,

    const max_alloc_count = 64;
    const max_action_count = 2 * max_alloc_count;

    const max_alloc_size = 16 << 10;

    const Alloc = struct {
        control_ptr: [*]u8,
        sample_ptr: [*]u8,
        common: packed struct(usize) {
            len: Len,
            alignment: Alignment,
            _: @Int(.unsigned, padding_bits) = 0,
        },

        const Len = enum(@Int(.unsigned, len_bits)) {
            free = (1 << len_bits) - 1,
            _,
        };
        const len_bits = @min(64, @bitSizeOf(usize)) - @bitSizeOf(Alignment);
        const padding_bits = @bitSizeOf(usize) - (len_bits + @bitSizeOf(Alignment));

        const Index = enum(usize) {
            none = std.math.maxInt(usize),
            _,
        };
    };

    const Action = enum {
        alloc,
        resize,
        remap,
        free,
    };

    const Init = struct {
        threaded_instance: *std.Io.Threaded,
        arena_state: *ArenaAllocator.State,
        control_instance: *std.heap.FixedBufferAllocator,
        sample_instance: *FuzzAllocator,
    };

    fn init(
        control_allocator: Allocator,
        sample_allocator: Allocator,
    ) FuzzContext {
        @disableInstrumentation();
        return .{
            .control_allocator = control_allocator,
            .sample_allocator = sample_allocator,
            .last_alloc_index = .none,
            .allocs = undefined,
        };
    }

    fn deinit(ctx: *FuzzContext) void {
        @disableInstrumentation();
        ctx.* = undefined;
    }

    fn check(ctx: *const FuzzContext, n_allocs: usize) !void {
        @disableInstrumentation();
        for (ctx.allocs[0..n_allocs]) |allocation| {
            const len: usize = switch (allocation.common.len) {
                .free => continue,
                _ => |len| @intFromEnum(len),
            };
            const control = allocation.control_ptr[0..len];
            const sample = allocation.sample_ptr[0..len];
            try std.testing.expectEqualSlices(u8, control, sample);
        }
    }

    fn doOneAlloc(ctx: *FuzzContext, len: usize, alignment: Alignment, index: Alloc.Index) void {
        @disableInstrumentation();
        assert(ctx.allocs[@intFromEnum(index)].common.len == .free);

        const control_ptr = ctx.control_allocator.rawAlloc(len, alignment, @returnAddress()) orelse
            return;
        const sample_ptr = ctx.sample_allocator.rawAlloc(len, alignment, @returnAddress()) orelse {
            ctx.control_allocator.rawFree(control_ptr[0..len], alignment, @returnAddress());
            return;
        };

        ctx.allocs[@intFromEnum(index)] = .{
            .control_ptr = control_ptr,
            .sample_ptr = sample_ptr,
            .common = .{
                .len = @enumFromInt(len),
                .alignment = alignment,
            },
        };

        for (control_ptr[0..len], sample_ptr[0..len], 0..) |*control, *sample, i| {
            control.* = @truncate(i);
            sample.* = @truncate(i);
        }

        @atomicStore(Alloc.Index, &ctx.last_alloc_index, index, .release);
    }
    fn doOneResize(ctx: *FuzzContext, new_len: usize) void {
        @disableInstrumentation();

        const index = @atomicRmw(Alloc.Index, &ctx.last_alloc_index, .Xchg, .none, .acquire);
        if (index == .none) return;

        const allocation = &ctx.allocs[@intFromEnum(index)];
        assert(allocation.common.len != .free);
        const memory = allocation.sample_ptr[0..@intFromEnum(allocation.common.len)];
        const alignment = allocation.common.alignment;

        assert(alignment.check(@intFromPtr(allocation.control_ptr)));
        assert(alignment.check(@intFromPtr(allocation.sample_ptr)));

        // Since `resize` is fallible, we have to ensure that `control_allocator`
        // is always successful by reserving the memory we need beforehand.
        const new_control_ptr = ctx.control_allocator.rawAlloc(new_len, alignment, @returnAddress()) orelse
            return;
        if (ctx.sample_allocator.rawResize(memory, alignment, new_len, @returnAddress())) {
            const old_control = allocation.control_ptr[0..memory.len];
            const overlap = @min(memory.len, new_len);
            @memcpy(new_control_ptr[0..overlap], old_control[0..overlap]);
            ctx.control_allocator.rawFree(old_control, alignment, @returnAddress());
        } else {
            ctx.control_allocator.rawFree(new_control_ptr[0..new_len], alignment, @returnAddress());
            return;
        }

        ctx.allocs[@intFromEnum(index)] = .{
            .control_ptr = new_control_ptr,
            .sample_ptr = memory.ptr,
            .common = .{
                .len = @enumFromInt(new_len),
                .alignment = alignment,
            },
        };

        if (new_len > memory.len) {
            for (
                allocation.control_ptr[memory.len..new_len],
                allocation.sample_ptr[memory.len..new_len],
                0..,
            ) |*control, *sample, i| {
                control.* = @truncate(i);
                sample.* = @truncate(i);
            }
        }

        @atomicStore(Alloc.Index, &ctx.last_alloc_index, index, .release);
    }
    fn doOneRemap(ctx: *FuzzContext, new_len: usize) void {
        @disableInstrumentation();
        return doOneResize(ctx, new_len);
    }
    fn doOneFree(ctx: *FuzzContext) void {
        @disableInstrumentation();

        const index = @atomicRmw(Alloc.Index, &ctx.last_alloc_index, .Xchg, .none, .acquire);
        if (index == .none) return;

        const allocation = &ctx.allocs[@intFromEnum(index)];
        assert(allocation.common.len != .free);
        const len: usize = @intFromEnum(allocation.common.len);
        const alignment = allocation.common.alignment;

        assert(alignment.check(@intFromPtr(allocation.control_ptr)));
        assert(alignment.check(@intFromPtr(allocation.sample_ptr)));

        ctx.control_allocator.rawFree(allocation.control_ptr[0..len], alignment, @returnAddress());
        ctx.sample_allocator.rawFree(allocation.sample_ptr[0..len], alignment, @returnAddress());

        ctx.allocs[@intFromEnum(index)] = .{
            .control_ptr = undefined,
            .sample_ptr = undefined,
            .common = .{
                .len = .free,
                .alignment = .@"1",
            },
        };
    }
};

const FuzzAllocator = struct {
    fba: std.heap.FixedBufferAllocator,
    spurious_failures: [256]u8,
    index: u8,

    fn init(buffer: []u8) FuzzAllocator {
        @disableInstrumentation();
        return .{
            .fba = .init(buffer),
            .spurious_failures = undefined, // set with `preprepareFailures`
            .index = 0,
        };
    }

    fn prepareFailures(fa: *FuzzAllocator, smith: *std.testing.Smith) void {
        @disableInstrumentation();
        const bool_weights: []const std.testing.Smith.Weight = &.{
            .value(u8, 0, 10),
            .value(u8, 1, 1),
        };
        smith.bytesWeighted(&fa.spurious_failures, bool_weights);
        fa.index = 0;
    }

    fn reset(fa: *FuzzAllocator) void {
        @disableInstrumentation();
        fa.fba.reset();
    }

    fn allocator(fa: *FuzzAllocator) Allocator {
        @disableInstrumentation();
        return .{
            .ptr = fa,
            .vtable = &.{
                .alloc = FuzzAllocator.alloc,
                .resize = FuzzAllocator.resize,
                .remap = FuzzAllocator.remap,
                .free = FuzzAllocator.free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: Alignment, ret_addr: usize) ?[*]u8 {
        @disableInstrumentation();
        const fa: *FuzzAllocator = @ptrCast(@alignCast(ctx));
        _ = ret_addr;

        const index = @atomicRmw(u8, &fa.index, .Add, 1, .monotonic);
        if (fa.spurious_failures[index] != 0) return null;
        return fa.fba.threadSafeAllocator().rawAlloc(len, alignment, @returnAddress());
    }

    fn resize(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) bool {
        @disableInstrumentation();
        const fa: *FuzzAllocator = @ptrCast(@alignCast(ctx));
        _ = ret_addr;

        const index = @atomicRmw(u8, &fa.index, .Add, 1, .monotonic);
        if (fa.spurious_failures[index] != 0) return false;
        return fa.fba.threadSafeAllocator().rawResize(memory, alignment, new_len, @returnAddress());
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        @disableInstrumentation();
        const fa: *FuzzAllocator = @ptrCast(@alignCast(ctx));
        _ = ret_addr;

        const index = @atomicRmw(u8, &fa.index, .Add, 1, .monotonic);
        if (fa.spurious_failures[index] != 0) return null;
        return fa.fba.threadSafeAllocator().rawRemap(memory, alignment, new_len, @returnAddress());
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: Alignment, ret_addr: usize) void {
        @disableInstrumentation();
        const fa: *FuzzAllocator = @ptrCast(@alignCast(ctx));
        _ = ret_addr;
        return fa.fba.threadSafeAllocator().rawFree(memory, alignment, @returnAddress());
    }
};
