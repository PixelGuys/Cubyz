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

	pub const PasteMode = enum {all, degradable};

	pub fn pasteInGeneration(self: Blueprint, pos: Vec3i, chunk: *ServerChunk, mode: PasteMode) void {
		switch(mode) {
			inline else => |comptimeMode| _pasteInGeneration(self, pos, chunk, comptimeMode),
		}
	}

	fn _pasteInGeneration(self: Blueprint, pos: Vec3i, chunk: *ServerChunk, comptime mode: PasteMode) void {
		const indexEndX: i32 = @min(@as(i32, chunk.super.width) - pos[0], @as(i32, @intCast(self.blocks.width)));
		const indexEndY: i32 = @min(@as(i32, chunk.super.width) - pos[1], @as(i32, @intCast(self.blocks.depth)));
		const indexEndZ: i32 = @min(@as(i32, chunk.super.width) - pos[2], @as(i32, @intCast(self.blocks.height)));

		var indexX: u31 = @max(0, -pos[0]);
		while(indexX < indexEndX) : (indexX += chunk.super.pos.voxelSize) {
			var indexY: u31 = @max(0, -pos[1]);
			while(indexY < indexEndY) : (indexY += chunk.super.pos.voxelSize) {
				var indexZ: u31 = @max(0, -pos[2]);
				while(indexZ < indexEndZ) : (indexZ += chunk.super.pos.voxelSize) {
					const block = self.blocks.get(indexX, indexY, indexZ);

					if(block.typ == voidType) continue;

					const chunkX = indexX + pos[0];
					const chunkY = indexY + pos[1];
					const chunkZ = indexZ + pos[2];
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
		main.items.Inventory.Sync.ServerSide.mutex.lock();
		defer main.items.Inventory.Sync.ServerSide.mutex.unlock();
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
	pub fn load(allocator: NeverFailingAllocator, inputBuffer: []const u8) !Blueprint {
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
			const gameBlockId = main.blocks.getBlockByIdWithMigrations(blockName) catch |err| blk: {
				std.log.err("Couldn't find block with name {s}: {s}. Replacing it with air", .{blockName, @errorName(err)});
				break :blk 0;
			};
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
	pub fn replace(self: *Blueprint, whitelist: ?Mask, blacklist: ?Mask, newBlocks: Pattern) void {
		for(0..self.blocks.width) |x| {
			for(0..self.blocks.depth) |y| {
				for(0..self.blocks.height) |z| {
					const current = self.blocks.get(x, y, z);
					if(whitelist) |m| if(!m.match(current)) continue;
					if(blacklist) |m| if(m.match(current)) continue;
					self.blocks.set(x, y, z, newBlocks.blocks.sample(&main.seed).block);
				}
			}
		}
	}
};

pub const Pattern = struct {
	const weightSeparator = '%';
	const expressionSeparator = ',';

	blocks: AliasTable(Entry),

	const Entry = struct {
		block: Block,
		chance: f32,
	};

	pub fn initFromString(allocator: NeverFailingAllocator, source: []const u8) !@This() {
		var specifiers = std.mem.splitScalar(u8, source, expressionSeparator);
		var totalWeight: f32 = 0;

		var weightedEntries: ListUnmanaged(struct {block: Block, weight: f32}) = .{};
		defer weightedEntries.deinit(main.stackAllocator);

		while(specifiers.next()) |specifier| {
			var blockId = specifier;
			var weight: f32 = 1.0;

			if(std.mem.containsAtLeastScalar(u8, specifier, 1, weightSeparator)) {
				var iterator = std.mem.splitScalar(u8, specifier, weightSeparator);
				const weightString = iterator.first();
				blockId = iterator.rest();

				weight = std.fmt.parseFloat(f32, weightString) catch return error.@"Weight not a valid number";
				if(weight <= 0) return error.@"Weight must be greater than 0";
			}

			_ = main.blocks.getBlockById(blockId) catch return error.@"Block not found";
			const block = main.blocks.parseBlock(blockId);

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
	const AndList = ListUnmanaged(Entry);
	const OrList = ListUnmanaged(AndList);

	entries: OrList,

	const or_ = '|';
	const and_ = '&';
	const inverse = '!';
	const tag = '$';
	const property = '@';

	const Entry = struct {
		inner: Inner,
		isInverse: bool,

		const Inner = union(enum) {
			block: Block,
			blockType: u16,
			blockTag: Tag,
			blockProperty: Property,

			const Property = blk: {
				var tempFields: [@typeInfo(Block).@"struct".decls.len]std.builtin.Type.EnumField = undefined;
				var count = 0;

				for(std.meta.declarations(Block)) |decl| {
					const declInfo = @typeInfo(@TypeOf(@field(Block, decl.name)));
					if(declInfo != .@"fn") continue;
					if(declInfo.@"fn".return_type != bool) continue;
					if(declInfo.@"fn".params.len != 1) continue;

					tempFields[count] = .{.name = decl.name, .value = count};
					count += 1;
				}

				const outFields: [count]std.builtin.Type.EnumField = tempFields[0..count].*;

				break :blk @Type(.{.@"enum" = .{
					.tag_type = u8,
					.fields = &outFields,
					.decls = &.{},
					.is_exhaustive = true,
				}});
			};

			fn initFromString(specifier: []const u8) !Inner {
				return switch(specifier[0]) {
					tag => .{.blockTag = Tag.get(specifier[1..]) orelse return error.TagNotFound},
					property => .{.blockProperty = std.meta.stringToEnum(Property, specifier[1..]) orelse return error.PropertyNotFound},
					else => return try parseBlockLike(specifier),
				};
			}

			fn match(self: Inner, block: Block) bool {
				return switch(self) {
					.block => |desired| block.typ == desired.typ and block.data == desired.data,
					.blockType => |desired| block.typ == desired,
					.blockTag => |desired| block.hasTag(desired),
					.blockProperty => |blockProperty| switch(blockProperty) {
						inline else => |prop| @field(Block, @tagName(prop))(block),
					},
				};
			}
		};

		fn initFromString(specifier: []const u8) !Entry {
			const isInverse = specifier[0] == '!';
			const entry = try Inner.initFromString(specifier[if(isInverse) 1 else 0..]);
			return .{.inner = entry, .isInverse = isInverse};
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
		var result: @This() = .{.entries = .{}};
		errdefer result.deinit(allocator);

		var oredExpressions = std.mem.splitScalar(u8, source, or_);
		while(oredExpressions.next()) |subExpression| {
			if(subExpression.len == 0) return error.MissingExpression;

			var andStorage: AndList = .{};
			errdefer andStorage.deinit(allocator);

			var andedExpressions = std.mem.splitScalar(u8, subExpression, and_);
			while(andedExpressions.next()) |specifier| {
				if(specifier.len == 0) return error.MissingExpression;

				const entry = try Entry.initFromString(specifier);
				andStorage.append(allocator, entry);
			}
			std.debug.assert(andStorage.items.len != 0);

			result.entries.append(allocator, andStorage);
		}
		std.debug.assert(result.entries.items.len != 0);

		return result;
	}

	pub fn deinit(self: @This(), allocator: NeverFailingAllocator) void {
		for(self.entries.items) |andStorage| {
			andStorage.deinit(allocator);
		}
		self.entries.deinit(allocator);
	}

	pub fn match(self: @This(), block: Block) bool {
		for(self.entries.items) |andedExpressions| {
			const status = blk: {
				for(andedExpressions.items) |expression| {
					if(!expression.match(block)) break :blk false;
				}
				break :blk true;
			};

			if(status) return true;
		}
		return false;
	}
};

fn parseBlockLike(block: []const u8) error{DataParsingFailed, IdParsingFailed}!Mask.Entry.Inner {
	if(@import("builtin").is_test) return try Test.parseBlockLikeTest(block);
	const typ = main.blocks.getBlockById(block) catch return error.IdParsingFailed;
	const dataNullable = main.blocks.getBlockData(block) catch return error.DataParsingFailed;
	if(dataNullable) |data| return .{.block = .{.typ = typ, .data = data}};
	return .{.blockType = typ};
}

const Test = struct {
	var parseBlockLikeTest: *const @TypeOf(parseBlockLike) = &defaultParseBlockLike;

	fn defaultParseBlockLike(_: []const u8) !Mask.Entry.Inner {
		unreachable;
	}

	fn @"parseBlockLike 1 null"(_: []const u8) !Mask.Entry.Inner {
		return .{.blockType = 1};
	}
	fn @"parseBlockLike 1 1"(_: []const u8) !Mask.Entry.Inner {
		return .{.block = .{.typ = 1, .data = 1}};
	}

	fn @"parseBlockLike foo or bar"(data: []const u8) !Mask.Entry.Inner {
		if(std.mem.eql(u8, data, "addon:foo")) {
			return .{.block = .{.typ = 1, .data = 0}};
		}
		if(std.mem.eql(u8, data, "addon:bar")) {
			return .{.block = .{.typ = 2, .data = 0}};
		}
		unreachable;
	}
};

test "Mask match block type with any data" {
	Test.parseBlockLikeTest = &Test.@"parseBlockLike 1 null";
	defer Test.parseBlockLikeTest = &Test.defaultParseBlockLike;

	const mask = try Mask.initFromString(main.heap.testingAllocator, "addon:dummy");
	defer mask.deinit(main.heap.testingAllocator);

	try std.testing.expect(mask.match(.{.typ = 1, .data = 0}));
	try std.testing.expect(mask.match(.{.typ = 1, .data = 1}));
	try std.testing.expect(!mask.match(.{.typ = 2, .data = 0}));
}

test "Mask empty negative case" {
	Test.parseBlockLikeTest = &Test.@"parseBlockLike 1 null";
	defer Test.parseBlockLikeTest = &Test.defaultParseBlockLike;

	try std.testing.expectError(error.MissingExpression, Mask.initFromString(main.heap.testingAllocator, ""));
}

test "Mask half-or negative case" {
	Test.parseBlockLikeTest = &Test.@"parseBlockLike 1 null";
	defer Test.parseBlockLikeTest = &Test.defaultParseBlockLike;

	try std.testing.expectError(error.MissingExpression, Mask.initFromString(main.heap.testingAllocator, "addon:dummy|"));
}

test "Mask half-or negative case 2" {
	Test.parseBlockLikeTest = &Test.@"parseBlockLike 1 null";
	defer Test.parseBlockLikeTest = &Test.defaultParseBlockLike;

	try std.testing.expectError(error.MissingExpression, Mask.initFromString(main.heap.testingAllocator, "|addon:dummy"));
}

test "Mask half-and negative case" {
	Test.parseBlockLikeTest = &Test.@"parseBlockLike 1 null";
	defer Test.parseBlockLikeTest = &Test.defaultParseBlockLike;

	try std.testing.expectError(error.MissingExpression, Mask.initFromString(main.heap.testingAllocator, "addon:dummy&"));
}

test "Mask half-and negative case 2" {
	Test.parseBlockLikeTest = &Test.@"parseBlockLike 1 null";
	defer Test.parseBlockLikeTest = &Test.defaultParseBlockLike;

	try std.testing.expectError(error.MissingExpression, Mask.initFromString(main.heap.testingAllocator, "&addon:dummy"));
}

test "Mask inverse match block type with any data" {
	Test.parseBlockLikeTest = &Test.@"parseBlockLike 1 null";
	defer Test.parseBlockLikeTest = &Test.defaultParseBlockLike;

	const mask = try Mask.initFromString(main.heap.testingAllocator, "!addon:dummy");
	defer mask.deinit(main.heap.testingAllocator);

	try std.testing.expect(!mask.match(.{.typ = 1, .data = 0}));
	try std.testing.expect(!mask.match(.{.typ = 1, .data = 1}));
	try std.testing.expect(mask.match(.{.typ = 2, .data = 0}));
}

test "Mask match block type with exact data" {
	Test.parseBlockLikeTest = &Test.@"parseBlockLike 1 1";
	defer Test.parseBlockLikeTest = &Test.defaultParseBlockLike;

	const mask = try Mask.initFromString(main.heap.testingAllocator, "addon:dummy");
	defer mask.deinit(main.heap.testingAllocator);

	try std.testing.expect(!mask.match(.{.typ = 1, .data = 0}));
	try std.testing.expect(mask.match(.{.typ = 1, .data = 1}));
	try std.testing.expect(!mask.match(.{.typ = 2, .data = 1}));
}

test "Mask match type 0 or type 1 with exact data" {
	Test.parseBlockLikeTest = &Test.@"parseBlockLike foo or bar";
	defer Test.parseBlockLikeTest = &Test.defaultParseBlockLike;

	const mask = try Mask.initFromString(main.heap.testingAllocator, "addon:foo|addon:bar");
	defer mask.deinit(main.heap.testingAllocator);

	try std.testing.expect(mask.match(.{.typ = 1, .data = 0}));
	try std.testing.expect(mask.match(.{.typ = 2, .data = 0}));
	try std.testing.expect(!mask.match(.{.typ = 1, .data = 1}));
	try std.testing.expect(!mask.match(.{.typ = 2, .data = 1}));
}

pub fn registerVoidBlock(block: Block) void {
	voidType = block.typ;
	std.debug.assert(voidType != 0);
}

pub fn getVoidBlock() Block {
	return Block{.typ = voidType.?, .data = 0};
}
