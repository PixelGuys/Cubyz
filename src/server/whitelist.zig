const std = @import("std");
const main = @import("main");
const ZonElement = main.ZonElement;

pub const JoinFilter = struct {
	neverFailingAllocator: main.heap.NeverFailingAllocator = undefined,
	whitelisted: bool = undefined,

	pub const mayJoinState = enum { default, whitelisted, blacklisted };

	pub fn init(allocator: main.heap.NeverFailingAllocator, worldData: ZonElement) *JoinFilter {
		var joinFilter = allocator.create(JoinFilter);
		errdefer allocator.destroy(joinFilter);
		joinFilter.neverFailingAllocator = allocator;
		joinFilter.load(worldData);
		return joinFilter;
	}

	pub fn deinit(self: *JoinFilter) void {
		self.*.neverFailingAllocator.destroy(self);
	}

	pub fn load(self: *JoinFilter, worldData: ZonElement) void {
		self.*.whitelisted = worldData.get(bool, "whitelisted", false);
	}

	pub fn playerMayJoin(self: *JoinFilter, mayJoin: mayJoinState) bool {
		return switch (mayJoin) {
			.default => !self.*.whitelisted,
			.whitelisted => true,
			.blacklisted => false,
		};
	}
};
