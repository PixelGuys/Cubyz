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

const BinaryWriter = main.utils.BinaryWriter;
const BinaryReader = main.utils.BinaryReader;

pub const BlueprintCompression = enum(u16) {
	deflate,
};

pub const FileHeader = packed struct {
	version: u16 = 0,
	compression: BlueprintCompression = .deflate,
	paletteSizeBytes: u32 = 0,
	paletteBlockCount: u16 = 0,
	blockArraySizeX: u16 = 0,
	blockArraySizeY: u16 = 0,
	blockArraySizeZ: u16 = 0,

	pub fn store(self: @This(), writer: *BinaryWriter) void {
		inline for(@typeInfo(@This()).@"struct".fields) |field| {
			switch(field.type) {
				u16, u32 => {
					writer.writeInt(field.type, @field(self, field.name));
				},
				BlueprintCompression => {
					writer.writeEnum(BlueprintCompression, @field(self, field.name));
				},
				else => unreachable,
			}
		}
	}
	pub fn load(self: *@This(), reader: *BinaryReader) !void {
		inline for(@typeInfo(@This()).@"struct".fields) |field| {
			switch(field.type) {
				u16, u32 => {
					@field(self, field.name) = try reader.readInt(field.type);
				},
				BlueprintCompression => {
					@field(self, field.name) = @enumFromInt(try reader.readInt(u16));
				},
				else => unreachable,
			}
		}
	}
	pub fn getBlockArraySize(self: @This()) usize {
		return @as(usize, @intCast(self.blockArraySizeX))*@as(usize, @intCast(self.blockArraySizeY))*@as(usize, @intCast(self.blockArraySizeZ));
	}
	fn getBlockArraySizeBytes(self: @This()) usize {
		return self.getBlockArraySize()*@sizeOf(BlockStorageType);
	}
	pub fn getHeaderSizeBytes(_: @This()) usize {
		var size: usize = 0;
		inline for(@typeInfo(@This()).@"struct".fields) |field| {
			size += @sizeOf(field.type);
		}
		return size;
	}
	pub fn getDecompressedDataSizeBytes(self: @This()) usize {
		return self.paletteSizeBytes + self.getBlockArraySizeBytes();
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
	pub fn capture(self: *@This(), pos1: Vec3i, pos2: Vec3i) ?struct {x: i32, y: i32, z: i32, message: []const u8} {
		self.clear();

		const startX = @min(pos1[0], pos2[0]);
		const startY = @min(pos1[1], pos2[1]);
		const startZ = @min(pos1[2], pos2[2]);

		const endX = @max(pos1[0], pos2[0]);
		const endY = @max(pos1[1], pos2[1]);
		const endZ = @max(pos1[2], pos2[2]);

		const sizeX: usize = @abs(endX - startX + 1);
		const sizeY: usize = @abs(endY - startY + 1);
		const sizeZ: usize = @abs(endZ - startZ + 1);

		self.sizeX = sizeX;
		self.sizeY = sizeY;
		self.sizeZ = sizeZ;

		self.blocks.ensureCapacity(self.sizeX*self.sizeY*self.sizeZ);

		for(0..sizeX) |offsetX| {
			const worldX = startX + @as(i32, @intCast(offsetX));

			for(0..sizeY) |offsetY| {
				const worldY = startY + @as(i32, @intCast(offsetY));

				for(0..sizeZ) |offsetZ| {
					const worldZ = startZ + @as(i32, @intCast(offsetZ));

					const maybeBlock = main.server.world.?.getBlock(worldX, worldY, worldZ);
					if(maybeBlock) |block| {
						self.blocks.appendAssumeCapacity(block);
					} else {
						return .{.x = worldX, .y = worldY, .z = worldZ, .message = "Chunk containing block not loaded."};
					}
				}
			}
		}
		return null;
	}
	pub fn paste(self: @This(), pos: Vec3i) void {
		const startX = pos[0];
		const startY = pos[1];
		const startZ = pos[2];

		var blockIndex: usize = 0;

		for(0..self.sizeX) |offsetX| {
			const worldX = startX + @as(i32, @intCast(offsetX));

			for(0..self.sizeY) |offsetY| {
				const worldY = startY + @as(i32, @intCast(offsetY));

				for(0..self.sizeZ) |offsetZ| {
					const worldZ = startZ + @as(i32, @intCast(offsetZ));

					const block = self.blocks.items[blockIndex];
					_ = main.server.world.?.updateBlock(worldX, worldY, worldZ, block);

					blockIndex += 1;
				}
			}
		}
	}
	pub fn store(self: @This(), allocator: NeverFailingAllocator) []u8 {
		std.debug.assert(self.sizeX != 0);
		std.debug.assert(self.sizeY != 0);
		std.debug.assert(self.sizeZ != 0);

		var gameIdToBlueprintId = self.makeGameIdToBlueprintIdMap(main.stackAllocator);
		defer gameIdToBlueprintId.deinit();
		std.debug.assert(gameIdToBlueprintId.count() != 0);

		const blockPalette = self.packBlockPalette(main.stackAllocator, gameIdToBlueprintId);
		defer main.stackAllocator.free(blockPalette);
		std.debug.assert(gameIdToBlueprintId.count() == blockPalette.len);

		const blockPaletteSizeBytes = self.getBlockPaletteSize(blockPalette);
		const header = FileHeader{
			.version = blueprintVersion,
			.compression = .deflate,
			.paletteSizeBytes = @intCast(blockPaletteSizeBytes),
			.paletteBlockCount = @intCast(gameIdToBlueprintId.count()),
			.blockArraySizeX = @intCast(self.sizeX),
			.blockArraySizeY = @intCast(self.sizeY),
			.blockArraySizeZ = @intCast(self.sizeZ),
		};

		const blockArraySizeBytes = header.getBlockArraySizeBytes();
		const decompressedDataSizeBytes = blockPaletteSizeBytes + blockArraySizeBytes;
		std.debug.assert(decompressedDataSizeBytes != 0);

		var decompressedWriter = BinaryWriter.initCapacity(allocator, .big, decompressedDataSizeBytes);
		defer decompressedWriter.deinit();

		self.storeBlockPalette(&decompressedWriter, blockPalette);
		self.storeBlockArray(&decompressedWriter, gameIdToBlueprintId);

		const compressedData: []u8 = self.compressOutputBuffer(main.stackAllocator, decompressedWriter.data.items, header.compression);
		defer main.stackAllocator.free(compressedData);
		std.debug.assert(compressedData.len != 0);

		var outputWriter = BinaryWriter.initCapacity(allocator, .big, header.getHeaderSizeBytes() + compressedData.len);
		header.store(&outputWriter);
		outputWriter.writeSlice(compressedData);

		return outputWriter.data.toOwnedSlice();
	}
	fn makeGameIdToBlueprintIdMap(self: @This(), allocator: NeverFailingAllocator) GameIdToBlueprintIdMapType {
		var gameIdToBlueprintId: GameIdToBlueprintIdMapType = .init(allocator.allocator);

		for(self.blocks.items) |block| {
			const result = gameIdToBlueprintId.getOrPut(block.typ) catch unreachable;
			if(!result.found_existing) {
				result.value_ptr.* = @intCast(gameIdToBlueprintId.count() - 1);
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
		for(self.blocks.items) |block| {
			const blueprintBlock: BlockStorageType = (Block{.typ = map.get(block.typ).?, .data = block.data}).toInt();
			writer.writeInt(BlockStorageType, blueprintBlock);
		}
	}
	fn compressOutputBuffer(_: @This(), allocator: NeverFailingAllocator, decompressedData: []u8, compressionMode: BlueprintCompression) []u8 {
		switch(compressionMode) {
			.deflate => {
				return Compression.deflate(allocator, decompressedData, .default);
			},
		}
	}
	pub fn load(self: *@This(), inputBuffer: []u8) !void {
		self.clear();
		errdefer self.clear();

		var compressedReader = BinaryReader.init(inputBuffer, .big);
		var header: FileHeader = .{};
		try header.load(&compressedReader);

		if(header.version > blueprintVersion) {
			std.log.err("Blueprint version {d} is not supported. Current version is {d}.", .{header.version, blueprintVersion});
			return;
		}

		const decompressedData = try self.decompressInputBuffer(main.stackAllocator, compressedReader.remaining, header);
		defer main.stackAllocator.free(decompressedData);
		std.debug.assert(decompressedData.len > 0);

		var decompressedReader = BinaryReader.init(decompressedData, .big);

		var palette = main.stackAllocator.alloc([]const u8, header.paletteBlockCount);
		defer main.stackAllocator.free(palette);

		for(0..@intCast(header.paletteBlockCount)) |index| {
			const blockNameSize = try decompressedReader.readInt(BlockIdSizeType);
			const blockName = try decompressedReader.readSlice(blockNameSize);
			palette[index] = blockName;
		}

		var blueprintIdToGameIdMap = main.stackAllocator.alloc(u16, header.paletteBlockCount);
		defer main.stackAllocator.free(blueprintIdToGameIdMap);

		for(palette, 0..) |blockName, blueprintBlockId| {
			const gameBlockId = main.blocks.parseBlock(blockName).typ;
			blueprintIdToGameIdMap[blueprintBlockId] = gameBlockId;
		}

		for(0..header.getBlockArraySize()) |_| {
			const blueprintBlockRaw = try decompressedReader.readInt(BlockStorageType);

			const blueprintBlock = Block.fromInt(blueprintBlockRaw);
			const gameBlockId = blueprintIdToGameIdMap[blueprintBlock.typ];

			self.blocks.append(.{.typ = gameBlockId, .data = blueprintBlock.data});
		}
		std.debug.assert(self.blocks.items.len == header.getBlockArraySize());

		self.sizeX = @intCast(header.blockArraySizeX);
		self.sizeY = @intCast(header.blockArraySizeY);
		self.sizeZ = @intCast(header.blockArraySizeZ);
	}
	fn decompressInputBuffer(_: @This(), allocator: NeverFailingAllocator, compressedData: []const u8, header: FileHeader) ![]u8 {
		const decompressedDataSizeBytes = header.getDecompressedDataSizeBytes();
		std.debug.assert(decompressedDataSizeBytes != 0);

		const decompressedData = allocator.alloc(u8, decompressedDataSizeBytes);
		var sizeAfterDecompression: usize = undefined;

		switch(header.compression) {
			.deflate => {
				sizeAfterDecompression = try Compression.inflateTo(decompressedData, compressedData);
			},
		}
		std.debug.assert(sizeAfterDecompression == decompressedDataSizeBytes);
		return decompressedData;
	}
};
