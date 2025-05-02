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
const Tag = main.Tag;

const GameIdToBlueprintIdMapType = std.AutoHashMap(u16, u16);
const BlockIdSizeType = u32;
const BlockStorageType = u32;

const BinaryWriter = main.utils.BinaryWriter;
const BinaryReader = main.utils.BinaryReader;

const AliasTable = main.utils.AliasTable;
const ListUnmanaged = main.ListUnmanaged;

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
	pub fn clone(self: Blueprint, allocator: NeverFailingAllocator) Blueprint {
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
	pub fn set(self: *Blueprint, pattern: Pattern, mask: ?Mask) void {
		for(0..self.blocks.width) |x| {
			for(0..self.blocks.depth) |y| {
				for(0..self.blocks.height) |z| {
					if(mask) |_mask| if(!_mask.match(self.blocks.get(x, y, z))) continue;
					self.blocks.set(x, y, z, pattern.blocks.sample(&main.seed).block);
				}
			}
		}
	}
};

pub const Pattern = struct {
	blocks: AliasTable(Entry),

	const Entry = struct {
		block: Block,
		chance: f32,
	};

	pub fn initFromString(allocator: NeverFailingAllocator, source: []const u8) !@This() {
		var specifiers = std.mem.splitScalar(u8, source, ',');
		var totalWeight: f32 = 0;

		var weightedEntries: ListUnmanaged(struct {block: Block, weight: f32}) = .{};
		defer weightedEntries.deinit(main.stackAllocator);

		while(specifiers.next()) |specifier| {
			var iterator = std.mem.splitScalar(u8, specifier, '%');

			var weight: f32 = undefined;
			var block = main.blocks.parseBlock(iterator.rest());

			const first = iterator.first();

			weight = std.fmt.parseFloat(f32, first) catch blk: {
				// To distinguish somehow between mistyped numeric values and actual block IDs we check for addon name separator.
				if(!std.mem.containsAtLeastScalar(u8, first, 1, ':')) return error.PatternSyntaxError;
				block = main.blocks.parseBlock(first);
				break :blk 1.0;
			};
			totalWeight += weight;
			weightedEntries.append(main.stackAllocator, .{.block = block, .weight = weight});
		}

		const entries = allocator.alloc(Entry, weightedEntries.items.len);
		for(weightedEntries.items, 0..) |entry, i| {
			entries[i] = .{.block = entry.block, .chance = entry.weight/totalWeight};
		}

		return .{.blocks = .init(allocator, entries)};
	}

	pub fn deinit(self: @This(), allocator: NeverFailingAllocator) void {
		self.blocks.deinit(allocator);
		allocator.free(self.blocks.items);
	}
};

pub const Mask = struct {
	entries: ListUnmanaged(Entry),

	pub const separator = ',';
	pub const inverse = '!';
	pub const tag = '$';
	pub const property = '@';

	const Entry = struct {
		inner: Inner,
		isInverse: bool,

		const Inner = union(enum) {
			block: struct {typ: u16, data: ?u16},
			blockTag: Tag,
			property: Property,

			const Property = enum {transparent, collide, solid, selectable, degradable, viewThrough, allowOres, isEntity};

			fn initFromString(specifier: []const u8) !Inner {
				switch(specifier[0]) {
					tag => {
						const blockTag = specifier[1..];
						if(blockTag.len == 0) return error.MaskSyntaxError;
						return .{.blockTag = Tag.find(blockTag)};
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

			fn match(self: Inner, block: Block) bool {
				return switch(self) {
					.block => block.typ == self.block.typ and (self.block.data == null or block.data == self.block.data),
					.blockTag => |desired| {
						for(block.blockTags()) |current| {
							if(desired == current) return true;
						}
						return false;
					},
					.property => |prop| return switch(prop) {
						.transparent => block.transparent(),
						.collide => block.collide(),
						.solid => block.solid(),
						.selectable => block.selectable(),
						.degradable => block.degradable(),
						.viewThrough => block.viewThrough(),
						.allowOres => block.allowOres(),
						.isEntity => block.entityDataClass() != null,
					},
				};
			}
		};

		fn initFromString(specifier: []const u8) !Entry {
			switch(specifier[0]) {
				inverse => {
					const entry = try Inner.initFromString(specifier[1..]);
					return .{.inner = entry, .isInverse = true};
				},
				else => {
					const entry = try Inner.initFromString(specifier);
					return .{.inner = entry, .isInverse = false};
				},
			}
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
			const entry = try Entry.initFromString(specifier);
			entries.append(allocator, entry);
		}

		return .{.entries = entries};
	}

	pub fn deinit(self: @This(), allocator: NeverFailingAllocator) void {
		self.entries.deinit(allocator);
	}

	pub fn match(self: @This(), block: Block) bool {
		for(self.entries.items) |e| {
			if(e.match(block)) return true;
		}
		return false;
	}
};

pub fn registerVoidBlock(block: Block) void {
	voidType = block.typ;
	std.debug.assert(voidType != 0);
}
