const std = @import("std");

const main = @import("main.zig");
const Compression = main.utils.Compression;
const ZonElement = @import("zon.zig").ZonElement;
const vec = main.vec;
const Vec3i = vec.Vec3i;

const Array3D = main.utils.Array3D;
const Block = main.blocks.Block;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const User = main.server.User;

pub const blueprintVersion = 0;
pub const GameIdToBlueprintIdMapType = std.AutoHashMap(u16, u16);
const BlockIdSizeType = u32;
const BlockStorageType = u32;

const BinaryWriter = main.utils.BinaryWriter;
const BinaryReader = main.utils.BinaryReader;

pub const BlueprintCompression = enum(u16) {
	deflate,
};

pub const Blueprint = struct {
	blocks: Array3D(Block),

	pub fn init(allocator: NeverFailingAllocator) @This() {
		return Blueprint{.blocks = .init(allocator, 0, 0, 0)};
	}
	pub fn deinit(self: *@This(), allocator: NeverFailingAllocator) void {
		self.blocks.deinit(allocator);
	}
	pub fn clone(self: *@This(), allocator: NeverFailingAllocator) @This() {
		var new = Blueprint.init(allocator);
		new.blocks = self.blocks.clone(allocator);
		return new;
	}
	const CaptureResult = union(enum) {
		success: Blueprint,
		failure: struct {x: i32, y: i32, z: i32, message: []const u8},
	};

	pub fn capture(allocator: NeverFailingAllocator, pos1: Vec3i, pos2: Vec3i) CaptureResult {
		var self = Blueprint{.blocks = undefined};

		const startX = @min(pos1[0], pos2[0]);
		const startY = @min(pos1[1], pos2[1]);
		const startZ = @min(pos1[2], pos2[2]);

		const endX = @max(pos1[0], pos2[0]);
		const endY = @max(pos1[1], pos2[1]);
		const endZ = @max(pos1[2], pos2[2]);

		const sizeX: u32 = @intCast(endX - startX + 1);
		const sizeY: u32 = @intCast(endY - startY + 1);
		const sizeZ: u32 = @intCast(endZ - startZ + 1);

		self.blocks = .init(allocator, sizeX, sizeY, sizeZ);

		for(0..sizeX) |x| {
			const worldX = startX + @as(i32, @intCast(x));

			for(0..sizeY) |y| {
				const worldY = startY + @as(i32, @intCast(y));

				for(0..sizeZ) |z| {
					const worldZ = startZ + @as(i32, @intCast(z));

					const maybeBlock = main.server.world.?.getBlock(worldX, worldY, worldZ);
					if(maybeBlock) |block| {
						self.blocks.set(x, y, z, block);
					} else {
						return .{.failure = .{.x = worldX, .y = worldY, .z = worldZ, .message = "Chunk containing block not loaded."}};
					}
				}
			}
		}
		return .{.success = self};
	}
	pub fn paste(self: @This(), pos: Vec3i) void {
		const startX = pos[0];
		const startY = pos[1];
		const startZ = pos[2];

		for(0..self.blocks.width) |x| {
			const worldX = startX + @as(i32, @intCast(x));

			for(0..self.blocks.depth) |y| {
				const worldY = startY + @as(i32, @intCast(y));

				for(0..self.blocks.height) |z| {
					const worldZ = startZ + @as(i32, @intCast(z));

					const block = self.blocks.get(x, y, z);
					_ = main.server.world.?.updateBlock(worldX, worldY, worldZ, block);
				}
			}
		}
	}
	pub fn store(self: @This(), allocator: NeverFailingAllocator) []u8 {
		var gameIdToBlueprintId = self.makeGameIdToBlueprintIdMap(main.stackAllocator);
		defer gameIdToBlueprintId.deinit();
		std.debug.assert(gameIdToBlueprintId.count() != 0);

		const blockPalette = packBlockPalette(main.stackAllocator, gameIdToBlueprintId);
		defer main.stackAllocator.free(blockPalette);
		std.debug.assert(gameIdToBlueprintId.count() == blockPalette.len);

		var uncompressedWriter = BinaryWriter.init(main.stackAllocator, .big);
		defer uncompressedWriter.deinit();

		self.storeBlockPalette(&uncompressedWriter, blockPalette);
		const blockPaletteSizeBytes = uncompressedWriter.data.items.len;

		self.storeBlockArray(&uncompressedWriter, gameIdToBlueprintId);

		const compressed = self.compressOutputBuffer(main.stackAllocator, uncompressedWriter.data.items);
		defer main.stackAllocator.free(compressed.data);

		var outputWriter = BinaryWriter.initCapacity(allocator, .big, @sizeOf(i16) + @sizeOf(BlueprintCompression) + @sizeOf(u32) + @sizeOf(u16)*4 + compressed.data.len);

		outputWriter.writeInt(u16, blueprintVersion);
		outputWriter.writeEnum(BlueprintCompression, compressed.mode);
		outputWriter.writeInt(u32, @intCast(blockPaletteSizeBytes));
		outputWriter.writeInt(u16, @intCast(gameIdToBlueprintId.count()));
		outputWriter.writeInt(u16, @intCast(self.blocks.width));
		outputWriter.writeInt(u16, @intCast(self.blocks.depth));
		outputWriter.writeInt(u16, @intCast(self.blocks.height));

		outputWriter.writeSlice(compressed.data);

		return outputWriter.data.toOwnedSlice();
	}
	fn makeGameIdToBlueprintIdMap(self: @This(), allocator: NeverFailingAllocator) GameIdToBlueprintIdMapType {
		var gameIdToBlueprintId: GameIdToBlueprintIdMapType = .init(allocator.allocator);

		for(self.blocks.mem) |block| {
			const result = gameIdToBlueprintId.getOrPut(block.typ) catch unreachable;
			if(!result.found_existing) {
				result.value_ptr.* = @intCast(gameIdToBlueprintId.count() - 1);
			}
		}

		return gameIdToBlueprintId;
	}
	fn packBlockPalette(allocator: NeverFailingAllocator, map: GameIdToBlueprintIdMapType) [][]const u8 {
		var blockPalette = allocator.alloc([]const u8, map.count());

		var iterator = map.iterator();
		while(iterator.next()) |entry| {
			const block = Block{.typ = entry.key_ptr.*, .data = 0};
			const blockId = block.id();
			blockPalette[entry.value_ptr.*] = blockId;
		}
		return blockPalette;
	}
	fn storeBlockPalette(_: @This(), writer: *BinaryWriter, blockPalette: [][]const u8) void {
		std.log.info("Blueprint block palette:", .{});

		for(0..blockPalette.len) |index| {
			const blockName = blockPalette[index];
			std.log.info("palette[{d}]: {s}", .{index, blockName});

			writer.writeInt(BlockIdSizeType, @intCast(blockName.len));
			writer.writeSlice(blockName);
		}
	}
	fn storeBlockArray(self: @This(), writer: *BinaryWriter, map: GameIdToBlueprintIdMapType) void {
		for(self.blocks.mem) |block| {
			const blueprintBlock: BlockStorageType = (Block{.typ = map.get(block.typ).?, .data = block.data}).toInt();
			writer.writeInt(BlockStorageType, blueprintBlock);
		}
	}
	fn compressOutputBuffer(_: @This(), allocator: NeverFailingAllocator, decompressedData: []u8) struct {mode: BlueprintCompression, data: []u8} {
		const compressionMode: BlueprintCompression = .deflate;
		switch(compressionMode) {
			.deflate => {
				return .{.mode = .deflate, .data = Compression.deflate(allocator, decompressedData, .default)};
			},
		}
	}
	pub fn load(allocator: NeverFailingAllocator, inputBuffer: []u8) !@This() {
		var self = Blueprint{.blocks = undefined};

		var compressedReader = BinaryReader.init(inputBuffer, .big);
		const version = try compressedReader.readInt(u16);

		if(version > blueprintVersion) {
			std.log.err("Blueprint version {d} is not supported. Current version is {d}.", .{version, blueprintVersion});
			return error.UnsupportedVersion;
		}
		const compression = try compressedReader.readEnum(BlueprintCompression);
		const blockPaletteSizeBytes = try compressedReader.readInt(u32);
		const paletteBlockCount = try compressedReader.readInt(u16);
		const width: u32 = @intCast(try compressedReader.readInt(u16));
		const depth: u32 = @intCast(try compressedReader.readInt(u16));
		const height: u32 = @intCast(try compressedReader.readInt(u16));

		self.blocks = .init(allocator, width, depth, height);

		const decompressedData = try self.decompressBuffer(compressedReader.remaining, blockPaletteSizeBytes, compression);
		defer main.stackAllocator.free(decompressedData);
		var decompressedReader = BinaryReader.init(decompressedData, .big);

		const palette = try unpackBlockPalette(main.stackAllocator, paletteBlockCount, &decompressedReader);
		defer main.stackAllocator.free(palette);

		const blueprintIdToGameIdMap = makeBlueprintIdToGameIdMap(main.stackAllocator, palette);
		defer main.stackAllocator.free(blueprintIdToGameIdMap);

		for(0..self.blocks.width) |x| {
			for(0..self.blocks.depth) |y| {
				for(0..self.blocks.height) |z| {
					const blueprintBlockRaw = try decompressedReader.readInt(BlockStorageType);

					const blueprintBlock = Block.fromInt(blueprintBlockRaw);
					const gameBlockId = blueprintIdToGameIdMap[blueprintBlock.typ];

					self.blocks.set(x, y, z, .{.typ = gameBlockId, .data = blueprintBlock.data});
				}
			}
		}
		return self;
	}
	fn decompressBuffer(self: *@This(), data: []const u8, blockPaletteSizeBytes: usize, compression: BlueprintCompression) ![]u8 {
		const blockArraySizeBytes = self.blocks.width*self.blocks.depth*self.blocks.height*@sizeOf(BlockStorageType);
		const decompressedDataSizeBytes = blockPaletteSizeBytes + blockArraySizeBytes;

		const decompressedData = main.stackAllocator.alloc(u8, decompressedDataSizeBytes);

		switch(compression) {
			.deflate => {
				const sizeAfterDecompression = try Compression.inflateTo(decompressedData, data);
				std.debug.assert(sizeAfterDecompression == decompressedDataSizeBytes);
			},
		}
		return decompressedData;
	}
	fn unpackBlockPalette(allocator: NeverFailingAllocator, paletteBlockCount: usize, reader: *BinaryReader) ![][]const u8 {
		var palette = allocator.alloc([]const u8, paletteBlockCount);

		for(0..@intCast(paletteBlockCount)) |index| {
			const blockNameSize = try reader.readInt(BlockIdSizeType);
			const blockName = try reader.readSlice(blockNameSize);
			palette[index] = blockName;
		}
		return palette;
	}
	fn makeBlueprintIdToGameIdMap(allocator: NeverFailingAllocator, palette: [][]const u8) []u16 {
		var blueprintIdToGameIdMap = allocator.alloc(u16, palette.len);

		for(palette, 0..) |blockName, blueprintBlockId| {
			const gameBlockId = main.blocks.parseBlock(blockName).typ;
			blueprintIdToGameIdMap[blueprintBlockId] = gameBlockId;
		}
		return blueprintIdToGameIdMap;
	}
};
