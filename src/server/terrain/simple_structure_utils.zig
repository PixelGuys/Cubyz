const std = @import("std");
const main = @import("main");
const ZonElement = main.ZonElement;
const AliasTable = main.utils.AliasTable;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

pub const BlockSelector = struct {
	blocks: AliasTable(Entry),

	const Entry = struct {
		block: main.blocks.Block,
		chance: f32,
	};

	pub fn parse(allocator: NeverFailingAllocator, zon: ZonElement, defaultBlock: []const u8) BlockSelector {
		var items: []Entry = undefined;
		switch(zon) {
			.string, .stringOwned => {
				items = allocator.alloc(Entry, 1);
				items[0] = .{
					.block = main.blocks.parseBlock(zon.as([]const u8, "")),
					.chance = 1.0,
				};
			},
			.array => {
				items = allocator.alloc(Entry, zon.array.items.len);
				for (0.., items) |i, *item| {
					const element = zon.array.items[i];
					if(element == .string or element == .stringOwned) {
						item.* = .{
							.block = main.blocks.parseBlock(element.as([]const u8, "")),
							.chance = 1.0,
						};
					} else if(element == .object) {
						item.* = .{
							.block = main.blocks.parseBlock(element.get([]const u8, "block", "")),
							.chance = element.get(f32, "chance", 1.0),
						};
					}
				}
			},
			else => {
				items = allocator.alloc(Entry, 1);
				items[0] = .{
					.block = main.blocks.parseBlock(defaultBlock),
					.chance = 1.0,
				};
			}
		}
		return .{
			.blocks = .init(allocator, items),
		};
	}

	pub fn getBlock(self: *const BlockSelector, seed: *u64) main.blocks.Block {
		return self.blocks.sample(seed).block;
	}
};