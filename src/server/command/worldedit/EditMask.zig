const std = @import("std");

const main = @import("main");
const AliasTable = main.utils.AliasTable;
const Block = main.blocks.Block;
const ListUnmanaged = main.ListUnmanaged;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

const separator = ',';
const inverse = '!';
const tag = '#';
const property = '@';

entries: ListUnmanaged(Entry),

const Entry = struct {
	inner: Inner,
	isInverse: bool,

	const Inner = union(enum) {
		block: struct {typ: u16, data: ?u16},
		blockTag: []const u8,
		property: Property,

		const Property = enum {transparent, collide, solid, selectable, degradable, viewThrough, allowOres, isEntity};

		fn initFromString(allocator: NeverFailingAllocator, specifier: []const u8) !Inner {
			switch(specifier[0]) {
				tag => {
					const blockTag = specifier[1..];
					if(blockTag.len == 0) return error.MaskSyntaxError;
					return .{.blockTag = allocator.dupe(u8, blockTag)};
				},
				property => {
					const propertyName = specifier[1..];
					const propertyValue = std.meta.stringToEnum(Property, propertyName) orelse return error.MaskSyntaxError;
					return .{.property = propertyValue};
				},
				else => {
					const block = main.blocks.parseBlock2(specifier) orelse return error.MaskSyntaxError;
					return .{.block = .{.typ = block.typ, .data = block.data}};
				},
			}
		}

		fn deinit(self: Inner, allocator: NeverFailingAllocator) void {
			switch(self) {
				.blockTag => |t| allocator.free(t),
				else => {},
			}
		}

		fn match(self: Inner, block: Block) bool {
			switch(self) {
				.block => return block.typ == self.block.typ and (self.block.data == null or block.data == self.block.data),
				.blockTag => |desired| for(block.blockTags()) |current| {
					if(current == desired) return true;
				},
				.property => |prop| return switch(prop) {
					.transparent => block.transparent(),
				},
			}
		}
	};

	fn initFromString(allocator: NeverFailingAllocator, specifier: []const u8) !Entry {
		switch(specifier[0]) {
			inverse => {
				const entry = try Inner.initFromString(allocator, specifier[1..]);
				return .{.inner = entry, .isInverse = true};
			},
			else => {
				const entry = try Inner.initFromString(allocator, specifier);
				return .{.inner = entry, .isInverse = true};
			},
		}
	}

	fn deinit(self: Entry, allocator: NeverFailingAllocator) void {
		self.inner.deinit(allocator);
	}

	pub fn match(self: Entry, block: Block) bool {
		const isMatch = self.inner.match(block);
		if(self.isInverse) {
			return !isMatch;
		}
		return isMatch;
	}
};

pub fn initFromString(allocator: NeverFailingAllocator, source: []const u8) !@This() {
	var specifiers = std.mem.splitScalar(u8, source, separator);

	var entries: ListUnmanaged(Entry) = .{};
	errdefer entries.deinit(allocator);

	while(specifiers.next()) |specifier| {
		if(specifier.len == 0) continue;
		const entry = try Entry.initFromString(allocator, specifier);
		entries.append(allocator, entry);
	}

	return .{.entries = entries};
}

pub fn deinit(self: @This(), allocator: NeverFailingAllocator) void {
	for(self.entries.items) |e| {
		e.deinit(allocator);
	}
	self.entries.deinit(allocator);
}
