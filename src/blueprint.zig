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

/// Blueprint storage file format header structure.
///
/// To extend, create a packed struct `<something>HeaderExtension` and add it as last field to this struct.
/// Bump `blueprintVersion` variable to indicate file format change.
/// Add serialization logic for `<something>HeaderExtension` to `store` and `load` methods
/// alongside version check to load that part of header only for files with version that supports it.
/// If you are adding new data segment, add serialization and deserialization logic to
/// `Blueprint.store` and `Blueprint.load` methods.
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
	pub fn load(self: *@This(), inputBuffer: []u8) usize {
		var offset: usize = 0;

		inline for(@typeInfo(@This()).@"struct".fields) |field| {
			switch(field.type) {
				u16 => {
					@field(self, field.name) = std.mem.readInt(u16, inputBuffer[offset..][0..@sizeOf(u16)], .big);
					offset += @sizeOf(u16);
				},
				u32 => {
					@field(self, field.name) = std.mem.readInt(u32, inputBuffer[offset..][0..@sizeOf(u32)], .big);
					offset += @sizeOf(u32);
				},
				BlueprintCompression => {
					@field(self, field.name) = @enumFromInt(std.mem.readInt(u16, inputBuffer[offset..][0..@sizeOf(u16)], .big));
					offset += @sizeOf(u16);
				},
				else => unreachable,
			}
		}
		return offset;
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

		var decompressedWriter = BinaryWriter.initCapacity(externalAllocator, .big, decompressedDataSizeBytes);
		defer decompressedWriter.deinit();

		self.storeBlockPalette(&decompressedWriter, blockPalette);
		self.storeBlockArray(&decompressedWriter, gameIdToBlueprintId);

		const compressedData: []u8 = self.compressOutputBuffer(allocator, decompressedWriter.data.items, header.compression);
		defer allocator.free(compressedData);
		std.debug.assert(compressedData.len != 0);

		var outputWriter = BinaryWriter.initCapacity(externalAllocator, .big, header.getHeaderSizeBytes() + compressedData.len);
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
		const allocator = main.stackAllocator;

		std.debug.assert(inputBuffer.len > 2);
		var header: FileHeader = .{};
		var rawDataOffset: usize = 0;

		rawDataOffset += header.load(inputBuffer);
		std.debug.assert(rawDataOffset > 0);

		if(header.version > blueprintVersion) {
			std.log.err("Blueprint version {d} is not supported. Current version is {d}.", .{header.version, blueprintVersion});
			return;
		}

		var decompressedData = try self.decompressInputBuffer(allocator, inputBuffer[rawDataOffset..], header);
		defer allocator.free(decompressedData);
		std.debug.assert(decompressedData.len > 0);

		var palette = allocator.alloc([]const u8, header.paletteBlockCount);
		defer allocator.free(palette);

		var decompressedDataOffset: usize = 0;

		for(0..@intCast(header.paletteBlockCount)) |index| {
			const blockNameSize = std.mem.readInt(BlockIdSizeType, decompressedData[decompressedDataOffset..][0..@sizeOf(BlockIdSizeType)], .big);
			decompressedDataOffset += @sizeOf(BlockIdSizeType);

			const blockName = decompressedData[decompressedDataOffset..][0..blockNameSize];
			palette[index] = blockName;
			decompressedDataOffset += blockNameSize;
		}

		var blueprintIdToGameIdMap = allocator.alloc(u16, header.paletteBlockCount);
		defer allocator.free(blueprintIdToGameIdMap);

		for(palette, 0..) |blockName, blueprintBlockId| {
			const gameBlockId = main.blocks.parseBlock(blockName).typ;
			blueprintIdToGameIdMap[blueprintBlockId] = gameBlockId;
		}

		for(0..header.getBlockArraySize()) |_| {
			const blueprintBlockRaw = std.mem.readInt(BlockStorageType, decompressedData[decompressedDataOffset..][0..@sizeOf(BlockStorageType)], .big);
			decompressedDataOffset += @sizeOf(BlockStorageType);

			const blueprintBlock = Block.fromInt(blueprintBlockRaw);
			const gameBlockId = blueprintIdToGameIdMap[blueprintBlock.typ];

			self.blocks.append(.{.typ = gameBlockId, .data = blueprintBlock.data});
		}
		std.debug.assert(decompressedDataOffset == decompressedData.len);
		std.debug.assert(self.blocks.items.len == header.getBlockArraySize());
		std.debug.assert(self.blocks.items.len != 0);

		self.sizeX = @intCast(header.blockArraySizeX);
		std.debug.assert(self.sizeX != 0);

		self.sizeY = @intCast(header.blockArraySizeY);
		std.debug.assert(self.sizeY != 0);

		self.sizeZ = @intCast(header.blockArraySizeZ);
		std.debug.assert(self.sizeZ != 0);
	}
	fn decompressInputBuffer(_: @This(), allocator: NeverFailingAllocator, compressedData: []u8, header: FileHeader) ![]u8 {
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
