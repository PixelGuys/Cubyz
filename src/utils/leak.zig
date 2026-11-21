const std = @import("std");
const builtin = @import("builtin");

const main = @import("main");

const traceCount = 10;

const Identifier = struct {
	pointer: ?*const anyopaque,
	allocator: union(enum) {
		pipeline,
		vulkanBuffer,
		vulkanImage,
	},
};

var allocationHashMap: std.AutoHashMapUnmanaged(Identifier, [traceCount]usize) = .empty;

pub fn registerAllocation(identifier: Identifier) void {
	if (!builtin.mode.runtimeSafety()) return;
	const result = allocationHashMap.getOrPut(std.heap.page_allocator, identifier) catch @panic("OOM");
	if (result.found_existing) {
		// TODO
	}
	const st = std.debug.captureCurrentStackTrace(.{.first_address = @returnAddress()}, result.value_ptr);
	@memset(result.value_ptr[@min(st.return_addresses.len, traceCount)..], 0);
}

pub fn freeAllocation(identifier: Identifier) void {
	if (!builtin.mode.runtimeSafety()) return;
	std.debug.assert(allocationHashMap.remove(identifier));
}

fn getTrace(trace: *[traceCount]usize) std.debug.FormatStackTrace {
	var len: usize = 0;
	while (len < traceCount and trace[len] != 0) {
		len += 1;
	}
	return .{
		.stack_trace = .{
			.return_addresses = trace[0..len],
			.skipped = if (len < traceCount) .none else .unknown,
		},
		.terminal_mode = std.log.terminalMode(),
	};
}

pub fn checkForLeaks() bool {
	var foundLeak = false;
	var iterator = allocationHashMap.iterator();
	while (iterator.next()) |elem| {
		std.log.err("Leaked item from {} allocator: {f}", .{
			elem.key_ptr.allocator,
			getTrace(elem.value_ptr),
		});
		foundLeak = true;
	}
	return foundLeak;
}

test "no leak" {
	registerAllocation(.{.allocator = .vulkanBuffer, .pointer = @ptrFromInt(1)});
	freeAllocation(.{.allocator = .vulkanBuffer, .pointer = @ptrFromInt(1)});
	try std.testing.expect(!checkForLeaks());
}

test "leak" {
	registerAllocation(.{.allocator = .vulkanBuffer, .pointer = @ptrFromInt(1)});
	try std.testing.expect(checkForLeaks());
}

test "different allocator same address" {
	registerAllocation(.{.allocator = .vulkanBuffer, .pointer = @ptrFromInt(1)});
	registerAllocation(.{.allocator = .vulkanImage, .pointer = @ptrFromInt(1)});
	freeAllocation(.{.allocator = .vulkanBuffer, .pointer = @ptrFromInt(1)});
	freeAllocation(.{.allocator = .vulkanImage, .pointer = @ptrFromInt(1)});
	try std.testing.expect(!checkForLeaks());
}
