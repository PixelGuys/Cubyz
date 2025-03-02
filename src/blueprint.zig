const std = @import("std");

const main = @import("main.zig");
const ZonElement = @import("zon.zig").ZonElement;
const vec = main.vec;
const Vec3i = vec.Vec3i;

const mesh_storage = main.renderer.mesh_storage;
const Block = main.blocks.Block;
const NeverFailingAllocator = main.utils.NeverFailingAllocator;
const User = main.server.User;

var arena: main.utils.NeverFailingArenaAllocator = undefined;
pub var arenaAllocator: NeverFailingAllocator = undefined;


pub fn init() void {
	arena = .init(main.globalAllocator);
	arenaAllocator = arena.allocator();
}

pub fn deinit() void {
	arena.deinit();
}

pub const Blueprint = struct {
	palette: std.StringHashMap(u16),
	blocks: main.List(u32),
	sizeX: usize,
	sizeY: usize,
	sizeZ: usize,

	pub fn init(allocator: NeverFailingAllocator) *Blueprint {
		const self = allocator.create(Blueprint);
		self.* = Blueprint {
			.palette = .init(allocator.allocator),
			.blocks = .init(allocator),
			.sizeX = 0,
			.sizeY = 0,
			.sizeZ = 0,
		};
		return self;
	}

	pub fn deinit(self: *Blueprint) void {
		self.palette.deinit();
		self.blocks.deinit();

		const allocator = self.palette.allocator;
		allocator.destroy(self);
	}
	pub fn capture(allocator: NeverFailingAllocator, pos1: Vec3i, pos2: Vec3i) !*Blueprint {
		var self = Blueprint.init(allocator);
		errdefer self.deinit();

		const startX = @min(pos1[0], pos2[0]);
		const startY = @min(pos1[1], pos2[1]);
		const startZ = @min(pos1[2], pos2[2]);

		const endX = @max(pos1[0], pos2[0]);
		const endY = @max(pos1[1], pos2[1]);
		const endZ = @max(pos1[2], pos2[2]);

		const sizeX: usize = @intCast(@abs(endX - startX + 1));
		const sizeY: usize = @intCast(@abs(endY - startY + 1));
		const sizeZ: usize = @intCast(@abs(endZ - startZ + 1));

		self.sizeX = sizeX;
		self.sizeY = sizeY;
		self.sizeZ = sizeZ;

		for (0..sizeX) |offsetX| {
			const worldX = startX + @as(i32, @intCast(offsetX));

			for (0..sizeY) |offsetY| {
				const worldY = startY + @as(i32, @intCast(offsetY));

				for (0..sizeZ) |offsetZ| {
					const worldZ = startZ + @as(i32, @intCast(offsetZ));

					const block = main.server.world.?.getBlock(worldX, worldY, worldZ) orelse Block{.typ = 0, .data = 0};
					const blockId = block.id();
					if (!self.palette.contains(blockId)) {
						self.palette.put(blockId, @as(u16, @truncate(self.palette.count()))) catch unreachable;
					}

					const blueprintBlockTyp = self.palette.get(blockId) orelse unreachable;
					const blueprintBlock = Block{.typ = blueprintBlockTyp, .data = block.data};

					self.blocks.append(@as(u32, @bitCast(blueprintBlock)));
					std.log.info(
						"Block at ({}, {}, {}) {}:{} => {}:{}",
						.{worldX, worldY, worldZ, block.typ, block.data, blueprintBlock.typ, blueprintBlock.data}
					);
				}
			}
		}
		return self;
	}
	pub fn paste(self: @This(), pos: Vec3i) void {
		const startX = pos[0];
		const startY = pos[1];
		const startZ = pos[2];

		const sizeX: usize = self.sizeX;
		const sizeY: usize = self.sizeY;
		const sizeZ: usize = self.sizeZ;

		var blockIndex: usize = 0;

		var reverseBlockTypMap = std.AutoHashMap(u16, u16).init(main.stackAllocator.allocator);
		defer reverseBlockTypMap.deinit();

		var paletteIterator = self.palette.iterator();
		while(paletteIterator.next()) |entry| {
			const gamePaletteBlock = main.blocks.parseBlock(entry.key_ptr.*);
			reverseBlockTypMap.put(entry.value_ptr.*, gamePaletteBlock.typ) catch unreachable;
		}

		for (0..sizeX) |offsetX| {
			const worldX = startX + @as(i32, @intCast(offsetX));

			for (0..sizeY) |offsetY| {
				const worldY = startY + @as(i32, @intCast(offsetY));

				for (0..sizeZ) |offsetZ| {
					const worldZ = startZ + @as(i32, @intCast(offsetZ));

					const blueprintBlock = Block.fromInt(self.blocks.items[blockIndex]);
					const gameBlockTyp = reverseBlockTypMap.get(blueprintBlock.typ) orelse unreachable;
					const gameBlock = Block{.typ = gameBlockTyp, .data = blueprintBlock.data};

					mesh_storage.updateBlock(worldX, worldY, worldZ, gameBlock);
					_ = main.server.world.?.updateBlock(worldX, worldY, worldZ, gameBlock);

					blockIndex += 1;
				}
			}
		}
	}
	pub fn toZon(self: *@This(), allocator: NeverFailingAllocator) ZonElement {
		var zon = ZonElement.initObject(allocator);
		errdefer zon.free(allocator);

		zon.put("sizeX", self.sizeX);
		zon.put("sizeY", self.sizeY);
		zon.put("sizeZ", self.sizeZ);

		var paletteZon = ZonElement.initObject(allocator);
		var paletteIterator = self.palette.iterator();
		while(paletteIterator.next()) |entry| {
			paletteZon.put(entry.key_ptr.*, entry.value_ptr.*);
		}
		zon.put("palette", paletteZon);

		var blocksZon = ZonElement.initArray(allocator);
		for (self.blocks.items) |block| {
			blocksZon.append(block);
		}
		zon.put("blocks", blocksZon);

		return zon;
	}
};
