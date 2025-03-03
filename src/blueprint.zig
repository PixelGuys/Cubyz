const std = @import("std");

const main = @import("main.zig");
const Compression = main.utils.Compression;
const ZonElement = @import("zon.zig").ZonElement;
const vec = main.vec;
const Vec3i = vec.Vec3i;

const mesh_storage = main.renderer.mesh_storage;
const Block = main.blocks.Block;
const NeverFailingAllocator = main.utils.NeverFailingAllocator;
const User = main.server.User;

pub const blueprintVersion = 0;
pub const GameIdToBlueprintIdMapType = std.AutoHashMap(u16, u16);
const BlockIdSizeType = u32;
const BlockStorageType = u32;

pub const BlueprintCompression = enum (u16) {
	DeflateFast,
	DeflateDefault,
	DeflateBest,
};

pub const FileHeader = packed struct {
	version: u16,
	compression: BlueprintCompression,
	paletteBlockCount: u16,
	blockArraySizeX: u16,
	blockArraySizeY: u16,
	blockArraySizeZ: u16,

	pub fn store(self: @This(), outputBuffer: []u8) usize {
		var offset: usize = 0;
		inline for(@typeInfo(@This()).@"struct".fields) |field| {
			switch (field.type) {
				u16 => {
					std.mem.writeInt(u16, outputBuffer[offset..][0..@sizeOf(u16)], @field(self, field.name), .big);
					offset += @sizeOf(u16);
				},
				BlueprintCompression => {
					std.mem.writeInt(u16, outputBuffer[offset..][0..@sizeOf(u16)], @intFromEnum(@field(self, field.name)), .big);
					offset += @sizeOf(u16);
				},
				else => unreachable,
			}
		}
		return offset;
	}
	pub fn getSizeBytes(_: @This()) usize {
		var size: usize = 0;
		inline for(@typeInfo(@This()).@"struct".fields) |field| {
			size += @sizeOf(field.type);
		}
		return size;
	}
};

pub const Blueprint = struct {
	blocks: main.List(Block),
	sizeX: usize,
	sizeY: usize,
	sizeZ: usize,

	pub fn init(allocator: NeverFailingAllocator) @This() {
		return Blueprint{
			.blocks = .init(allocator),
			.sizeX = 0,
			.sizeY = 0,
			.sizeZ = 0,
		};
	}
	pub fn deinit(self: *@This()) void {
		self.blocks.deinit();
	}
	pub fn clear(self: *@This()) void {
		self.sizeX = 0;
		self.sizeY = 0;
		self.sizeZ = 0;
		self.blocks.clearRetainingCapacity();
	}
	pub fn capture(self: *@This(), pos1: Vec3i, pos2: Vec3i) void {
		self.clear();

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

		for(0..sizeX) |offsetX| {
			const worldX = startX + @as(i32, @intCast(offsetX));

			for(0..sizeY) |offsetY| {
				const worldY = startY + @as(i32, @intCast(offsetY));

				for(0..sizeZ) |offsetZ| {
					const worldZ = startZ + @as(i32, @intCast(offsetZ));

					const block = main.server.world.?.getBlock(worldX, worldY, worldZ) orelse Block{.typ = 0, .data = 0};
					self.blocks.append(block);
				}
			}
		}
	}
	pub fn paste(self: @This(), pos: Vec3i) void {
		const startX = pos[0];
		const startY = pos[1];
		const startZ = pos[2];

		const sizeX: usize = self.sizeX;
		const sizeY: usize = self.sizeY;
		const sizeZ: usize = self.sizeZ;

		var blockIndex: usize = 0;

		for(0..sizeX) |offsetX| {
			const worldX = startX + @as(i32, @intCast(offsetX));

			for(0..sizeY) |offsetY| {
				const worldY = startY + @as(i32, @intCast(offsetY));

				for(0..sizeZ) |offsetZ| {
					const worldZ = startZ + @as(i32, @intCast(offsetZ));

					const block = self.blocks.items[blockIndex];
					mesh_storage.updateBlock(worldX, worldY, worldZ, block);
					_ = main.server.world.?.updateBlock(worldX, worldY, worldZ, block);

					blockIndex += 1;
				}
			}
		}
	}
	pub fn store(self: @This(), externalAllocator: NeverFailingAllocator) []u8 {
		const allocator = main.stackAllocator;
		std.debug.assert(self.sizeX != 0);
		std.debug.assert(self.sizeY != 0);
		std.debug.assert(self.sizeZ != 0);

		var gameIdToBlueprintId = self.makeGameIdToBlueprintIdMap(allocator);
		defer gameIdToBlueprintId.deinit();
		std.debug.assert(gameIdToBlueprintId.count() != 0);

		const blockPalette = self.packBlockPalette(allocator, gameIdToBlueprintId);
		defer allocator.free(blockPalette);
		std.debug.assert(gameIdToBlueprintId.count() == blockPalette.len);

		const blockPaletteSizeBytes = self.getBlockPaletteSize(blockPalette);
		const blockArraySizeBytes: usize = self.getBlockArraySize();
		const uncompressedDataSizeBytes = blockPaletteSizeBytes + blockArraySizeBytes;
		std.debug.assert(uncompressedDataSizeBytes != 0);

		var data = allocator.alloc(u8, uncompressedDataSizeBytes);
		defer allocator.free(data);
		{
			var offset: usize = 0;
			offset += self.storeBlockPalette(data[offset..], blockPalette);
			std.debug.assert(offset == blockPaletteSizeBytes);

			offset += self.storeBlockArray(data[offset..], gameIdToBlueprintId);
			std.debug.assert(offset == uncompressedDataSizeBytes);
		}
		const compression = BlueprintCompression.DeflateDefault;
		const compressedData: []u8 = self.compressOutputBuffer(allocator, data, compression);
		defer allocator.free(compressedData);
		std.debug.assert(compressedData.len != 0);

		const header = FileHeader{
			.version = blueprintVersion,
			.compression = compression,
			.paletteBlockCount = @truncate(gameIdToBlueprintId.count()),
			.blockArraySizeX = @truncate(self.sizeX),
			.blockArraySizeY = @truncate(self.sizeY),
			.blockArraySizeZ = @truncate(self.sizeZ),
		};

		const headerSizerBytes = header.getSizeBytes();
		const outputBufferSize = headerSizerBytes + compressedData.len;
		var outputBuffer = externalAllocator.alloc(u8, outputBufferSize);

		var offset: usize = 0;
		offset += header.store(outputBuffer);
		std.debug.assert(offset == headerSizerBytes);

		@memcpy(outputBuffer[offset..][0..compressedData.len], compressedData);

		return outputBuffer;
	}
	fn makeGameIdToBlueprintIdMap(self: @This(), allocator: NeverFailingAllocator) GameIdToBlueprintIdMapType {
		var gameIdToBlueprintId: GameIdToBlueprintIdMapType = .init(allocator.allocator);

		for(self.blocks.items) |block| {
			const result = gameIdToBlueprintId.getOrPut(block.typ) catch unreachable;
			if(!result.found_existing) {
				result.value_ptr.* = @truncate(gameIdToBlueprintId.count() - 1);
			}
		}

		return gameIdToBlueprintId;
	}
	fn packBlockPalette(_: @This(), allocator: NeverFailingAllocator, map: GameIdToBlueprintIdMapType) [][]const u8 {
		var blockPalette = allocator.alloc([]const u8, map.count());

		var iterator = map.iterator();
		while(iterator.next()) |entry| {
			const block = Block{.typ = entry.key_ptr.*, .data = 0};
			const blockId = block.id();
			blockPalette[entry.value_ptr.*] = blockId;
		}
		return blockPalette;
	}
	fn getBlockPaletteSize(_: @This(), palette: [][]const u8) usize {
		var total: usize = 0;
		for(palette) |blockName| {
			total += @sizeOf(BlockIdSizeType) + blockName.len;
		}
		return total;
	}
	fn getBlockArraySize(self: @This()) usize {
		return self.sizeX * self.sizeY * self.sizeZ * @sizeOf(Block);
	}
	fn storeBlockPalette(_: @This(), outputBuffer: []u8, blockPalette: [][]const u8) usize {
		var offset: usize = 0;
		std.log.info("Blueprint block palette:", .{});

		for(0..blockPalette.len) |index| {
			const blockName = blockPalette[index];
			std.log.info("palette[{d}]: {s}", .{index, blockName});

			std.mem.writeInt(BlockIdSizeType, outputBuffer[offset..][0..@sizeOf(BlockIdSizeType)], @truncate(blockName.len), .big);
			offset += @sizeOf(BlockIdSizeType);

			@memcpy(outputBuffer[offset..][0..blockName.len], blockName);
			offset += blockName.len;
		}
		return offset;
	}
	fn storeBlockArray(self: @This(), outputBuffer: []u8, map: GameIdToBlueprintIdMapType) usize {
		var offset: usize = 0;
		for(self.blocks.items) |block| {
			const blueprintBlock: BlockStorageType = (Block{.typ = map.get(block.typ).?, .data = block.data}).toInt();
			std.mem.writeInt(BlockStorageType, outputBuffer[offset..][0..@sizeOf(BlockStorageType)], blueprintBlock, .big);
			offset += @sizeOf(BlockStorageType);
		}
		return offset;
	}
	fn compressOutputBuffer(_: @This(), allocator: NeverFailingAllocator, uncompressedData: []u8, compressionMode: BlueprintCompression) []u8 {
		switch(compressionMode) {
			.DeflateFast => {
				return Compression.deflate(allocator, uncompressedData, .fast);
			},
			.DeflateDefault => {
				return Compression.deflate(allocator, uncompressedData, .default);
			},
			.DeflateBest => {
				return Compression.deflate(allocator, uncompressedData, .best);
			},
		}
	}
};
