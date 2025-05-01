const std = @import("std");

const main = @import("main");
const Compression = main.utils.Compression;
const ZonElement = @import("zon.zig").ZonElement;
const vec = main.vec;
const Vec3i = vec.Vec3i;

const Array3D = main.utils.Array3D;
const Block = main.blocks.Block;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const User = main.server.User;
const ServerChunk = main.chunk.ServerChunk;
const Degrees = main.rotation.Degrees;

const GameIdToBlueprintIdMapType = std.AutoHashMap(u16, u16);
const BlockIdSizeType = u32;
const BlockStorageType = u32;

const BinaryWriter = main.utils.BinaryWriter;
const BinaryReader = main.utils.BinaryReader;

pub const blueprintVersion = 0;
var voidType: ?u16 = null;

pub const BlueprintCompression = enum(u16) {
	deflate,
};

pub const Blueprint = struct {
	blocks: Array3D(Block),

	pub fn init(allocator: NeverFailingAllocator) Blueprint {
		return .{.blocks = .init(allocator, 0, 0, 0)};
	}
	pub fn deinit(self: Blueprint, allocator: NeverFailingAllocator) void {
		self.blocks.deinit(allocator);
	}
	pub fn clone(self: *Blueprint, allocator: NeverFailingAllocator) Blueprint {
		return .{.blocks = self.blocks.clone(allocator)};
	}
	pub fn rotateZ(self: Blueprint, allocator: NeverFailingAllocator, angle: Degrees) Blueprint {
		var new = Blueprint{
			.blocks = switch(angle) {
				.@"0", .@"180" => .init(allocator, self.blocks.width, self.blocks.depth, self.blocks.height),
				.@"90", .@"270" => .init(allocator, self.blocks.depth, self.blocks.width, self.blocks.height),
			},
		};

		for(0..self.blocks.width) |xOld| {
			for(0..self.blocks.depth) |yOld| {
				const xNew, const yNew = switch(angle) {
					.@"0" => .{xOld, yOld},
					.@"90" => .{new.blocks.width - yOld - 1, xOld},
					.@"180" => .{new.blocks.width - xOld - 1, new.blocks.depth - yOld - 1},
					.@"270" => .{yOld, new.blocks.depth - xOld - 1},
				};

				for(0..self.blocks.height) |z| {
					const block = self.blocks.get(xOld, yOld, z);
					new.blocks.set(xNew, yNew, z, block.rotateZ(angle));
				}
			}
		}
		return new;
	}

	const CaptureResult = union(enum) {
		success: Blueprint,
		failure: struct {pos: Vec3i, message: []const u8},
	};

	pub fn capture(allocator: NeverFailingAllocator, pos1: Vec3i, pos2: Vec3i) CaptureResult {
		const startX = @min(pos1[0], pos2[0]);
		const startY = @min(pos1[1], pos2[1]);
		const startZ = @min(pos1[2], pos2[2]);

		const endX = @max(pos1[0], pos2[0]);
		const endY = @max(pos1[1], pos2[1]);
		const endZ = @max(pos1[2], pos2[2]);

		const sizeX: u32 = @intCast(endX - startX + 1);
		const sizeY: u32 = @intCast(endY - startY + 1);
		const sizeZ: u32 = @intCast(endZ - startZ + 1);

		const self = Blueprint{.blocks = .init(allocator, sizeX, sizeY, sizeZ)};

		for(0..sizeX) |x| {
			const worldX = startX +% @as(i32, @intCast(x));

			for(0..sizeY) |y| {
				const worldY = startY +% @as(i32, @intCast(y));

				for(0..sizeZ) |z| {
					const worldZ = startZ +% @as(i32, @intCast(z));

					const maybeBlock = main.server.world.?.getBlock(worldX, worldY, worldZ);
					if(maybeBlock) |block| {
						self.blocks.set(x, y, z, block);
					} else {
						return .{.failure = .{.pos = .{worldX, worldY, worldZ}, .message = "Chunk containing block not loaded."}};
					}
				}
			}
		}
		return .{.success = self};
	}

	pub const PasteMode = enum {all, degradable};

	pub fn pasteInGeneration(self: Blueprint, pos: Vec3i, chunk: *ServerChunk, mode: PasteMode) void {
		switch(mode) {
			inline else => |comptimeMode| _pasteInGeneration(self, pos, chunk, comptimeMode),
		}
	}

	fn _pasteInGeneration(self: Blueprint, pos: Vec3i, chunk: *ServerChunk, comptime mode: PasteMode) void {
		const blueprintOffset = @max(@as(Vec3i, @splat(0)), -pos);
		const chunkOffset = @max(@as(Vec3i, @splat(0)), pos);

		const indexEndX: i32 = @min(@as(i32, @intCast(chunk.super.width)) - chunkOffset[0], @as(i32, @intCast(self.blocks.width)) - blueprintOffset[0]);
		const indexEndY: i32 = @min(@as(i32, @intCast(chunk.super.width)) - chunkOffset[1], @as(i32, @intCast(self.blocks.depth)) - blueprintOffset[1]);
		const indexEndZ: i32 = @min(@as(i32, @intCast(chunk.super.width)) - chunkOffset[2], @as(i32, @intCast(self.blocks.height)) - blueprintOffset[2]);

		var indexX: i32 = 0;
		while(indexX < indexEndX) : (indexX += chunk.super.pos.voxelSize) {
			var indexY: i32 = 0;
			while(indexY < indexEndY) : (indexY += chunk.super.pos.voxelSize) {
				var indexZ: i32 = 0;
				while(indexZ < indexEndZ) : (indexZ += chunk.super.pos.voxelSize) {
					const blueprintX: usize = @intCast(indexX + blueprintOffset[0]);
					const blueprintY: usize = @intCast(indexY + blueprintOffset[1]);
					const blueprintZ: usize = @intCast(indexZ + blueprintOffset[2]);

					const block = self.blocks.get(blueprintX, blueprintY, blueprintZ);

					if(block.typ == voidType) continue;

					const chunkX = indexX + chunkOffset[0];
					const chunkY = indexY + chunkOffset[1];
					const chunkZ = indexZ + chunkOffset[2];
					switch(mode) {
						.all => chunk.updateBlockInGeneration(chunkX, chunkY, chunkZ, block),
						.degradable => chunk.updateBlockIfDegradable(chunkX, chunkY, chunkZ, block),
					}
				}
			}
		}
	}

	pub const PasteFlags = struct {
		preserveVoid: bool = false,
	};

	pub fn paste(self: Blueprint, pos: Vec3i, flags: PasteFlags) void {
		const startX = pos[0];
		const startY = pos[1];
		const startZ = pos[2];

		for(0..self.blocks.width) |x| {
			const worldX = startX +% @as(i32, @intCast(x));

			for(0..self.blocks.depth) |y| {
				const worldY = startY +% @as(i32, @intCast(y));

				for(0..self.blocks.height) |z| {
					const worldZ = startZ +% @as(i32, @intCast(z));

					const block = self.blocks.get(x, y, z);
					if(block.typ != voidType or flags.preserveVoid)
						_ = main.server.world.?.updateBlock(worldX, worldY, worldZ, block);
				}
			}
		}
	}
	pub fn load(allocator: NeverFailingAllocator, inputBuffer: []u8) !Blueprint {
		var compressedReader = BinaryReader.init(inputBuffer);
		const version = try compressedReader.readInt(u16);

		if(version > blueprintVersion) {
			std.log.err("Blueprint version {d} is not supported. Current version is {d}.", .{version, blueprintVersion});
			return error.UnsupportedVersion;
		}
		const compression = try compressedReader.readEnum(BlueprintCompression);
		const blockPaletteSizeBytes = try compressedReader.readInt(u32);
		const paletteBlockCount = try compressedReader.readInt(u16);
		const width = try compressedReader.readInt(u16);
		const depth = try compressedReader.readInt(u16);
		const height = try compressedReader.readInt(u16);

		const self = Blueprint{.blocks = .init(allocator, width, depth, height)};

		const decompressedData = try self.decompressBuffer(compressedReader.remaining, blockPaletteSizeBytes, compression);
		defer main.stackAllocator.free(decompressedData);
		var decompressedReader = BinaryReader.init(decompressedData);

		const palette = try loadBlockPalette(main.stackAllocator, paletteBlockCount, &decompressedReader);
		defer main.stackAllocator.free(palette);

		const blueprintIdToGameIdMap = makeBlueprintIdToGameIdMap(main.stackAllocator, palette);
		defer main.stackAllocator.free(blueprintIdToGameIdMap);

		for(self.blocks.mem) |*block| {
			const blueprintBlockRaw = try decompressedReader.readInt(BlockStorageType);

			const blueprintBlock = Block.fromInt(blueprintBlockRaw);
			const gameBlockId = blueprintIdToGameIdMap[blueprintBlock.typ];

			block.* = .{.typ = gameBlockId, .data = blueprintBlock.data};
		}
		return self;
	}
	pub fn store(self: Blueprint, allocator: NeverFailingAllocator) []u8 {
		var gameIdToBlueprintId = self.makeGameIdToBlueprintIdMap(main.stackAllocator);
		defer gameIdToBlueprintId.deinit();
		std.debug.assert(gameIdToBlueprintId.count() != 0);

		var uncompressedWriter = BinaryWriter.init(main.stackAllocator);
		defer uncompressedWriter.deinit();

		const blockPaletteSizeBytes = storeBlockPalette(gameIdToBlueprintId, &uncompressedWriter);

		for(self.blocks.mem) |block| {
			const blueprintBlock: BlockStorageType = Block.toInt(.{.typ = gameIdToBlueprintId.get(block.typ).?, .data = block.data});
			uncompressedWriter.writeInt(BlockStorageType, blueprintBlock);
		}

		const compressed = self.compressOutputBuffer(main.stackAllocator, uncompressedWriter.data.items);
		defer main.stackAllocator.free(compressed.data);

		var outputWriter = BinaryWriter.initCapacity(allocator, @sizeOf(i16) + @sizeOf(BlueprintCompression) + @sizeOf(u32) + @sizeOf(u16)*4 + compressed.data.len);

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
	fn makeBlueprintIdToGameIdMap(allocator: NeverFailingAllocator, palette: [][]const u8) []u16 {
		var blueprintIdToGameIdMap = allocator.alloc(u16, palette.len);

		for(palette, 0..) |blockName, blueprintBlockId| {
			const gameBlockId = main.blocks.parseBlock(blockName).typ;
			blueprintIdToGameIdMap[blueprintBlockId] = gameBlockId;
		}
		return blueprintIdToGameIdMap;
	}
	fn makeGameIdToBlueprintIdMap(self: Blueprint, allocator: NeverFailingAllocator) GameIdToBlueprintIdMapType {
		var gameIdToBlueprintId: GameIdToBlueprintIdMapType = .init(allocator.allocator);

		for(self.blocks.mem) |block| {
			const result = gameIdToBlueprintId.getOrPut(block.typ) catch unreachable;
			if(!result.found_existing) {
				result.value_ptr.* = @intCast(gameIdToBlueprintId.count() - 1);
			}
		}

		return gameIdToBlueprintId;
	}
	fn loadBlockPalette(allocator: NeverFailingAllocator, paletteBlockCount: usize, reader: *BinaryReader) ![][]const u8 {
		var palette = allocator.alloc([]const u8, paletteBlockCount);

		for(0..@intCast(paletteBlockCount)) |index| {
			const blockNameSize = try reader.readInt(BlockIdSizeType);
			const blockName = try reader.readSlice(blockNameSize);
			palette[index] = blockName;
		}
		return palette;
	}
	fn storeBlockPalette(map: GameIdToBlueprintIdMapType, writer: *BinaryWriter) usize {
		var blockPalette = main.stackAllocator.alloc([]const u8, map.count());
		defer main.stackAllocator.free(blockPalette);

		var iterator = map.iterator();
		while(iterator.next()) |entry| {
			const block = Block{.typ = entry.key_ptr.*, .data = 0};
			const blockId = block.id();
			blockPalette[entry.value_ptr.*] = blockId;
		}

		std.log.info("Blueprint block palette:", .{});

		for(0..blockPalette.len) |index| {
			const blockName = blockPalette[index];
			std.log.info("palette[{d}]: {s}", .{index, blockName});

			writer.writeInt(BlockIdSizeType, @intCast(blockName.len));
			writer.writeSlice(blockName);
		}

		return writer.data.items.len;
	}
	fn decompressBuffer(self: Blueprint, data: []const u8, blockPaletteSizeBytes: usize, compression: BlueprintCompression) ![]u8 {
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
	fn compressOutputBuffer(_: Blueprint, allocator: NeverFailingAllocator, decompressedData: []u8) struct {mode: BlueprintCompression, data: []u8} {
		const compressionMode: BlueprintCompression = .deflate;
		switch(compressionMode) {
			.deflate => {
				return .{.mode = .deflate, .data = Compression.deflate(allocator, decompressedData, .default)};
			},
		}
	}
};

pub fn registerVoidBlock(block: Block) void {
	voidType = block.typ;
	std.debug.assert(voidType != 0);
}

pub fn getVoidBlock() Block {
	return Block{.typ = voidType.?, .data = 0};
}
