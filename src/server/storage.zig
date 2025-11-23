const std = @import("std");
const Atomic = std.atomic.Value;

const main = @import("main");
const chunk = main.chunk;
const server = @import("server.zig");

const utils = main.utils;
const BinaryWriter = utils.BinaryWriter;
const BinaryReader = utils.BinaryReader;

pub const RegionFile = struct { // MARK: RegionFile
	const version = 0;
	pub const regionShift = 2;
	pub const regionSize = 1 << regionShift;
	pub const regionVolume = 1 << 3*regionShift;

	const headerSize = 8 + regionSize*regionSize*regionSize*@sizeOf(u32);

	chunks: [regionVolume][]u8 = @splat(&.{}),
	pos: chunk.ChunkPosition,
	mutex: std.Thread.Mutex = .{},
	modified: bool = false,
	refCount: Atomic(u16) = .init(1),
	storedInHashMap: bool = false,
	saveFolder: []const u8,

	pub fn getIndex(x: usize, y: usize, z: usize) usize {
		std.debug.assert(x < regionSize and y < regionSize and z < regionSize);
		return ((x*regionSize) + y)*regionSize + z;
	}

	pub fn init(pos: chunk.ChunkPosition, saveFolder: []const u8) *RegionFile {
		std.debug.assert(pos.wx & (1 << chunk.chunkShift + regionShift) - 1 == 0);
		std.debug.assert(pos.wy & (1 << chunk.chunkShift + regionShift) - 1 == 0);
		std.debug.assert(pos.wz & (1 << chunk.chunkShift + regionShift) - 1 == 0);
		const self = main.globalAllocator.create(RegionFile);
		self.* = .{
			.pos = pos,
			.saveFolder = main.globalAllocator.dupe(u8, saveFolder),
		};

		const path = std.fmt.allocPrint(main.stackAllocator.allocator, "{s}/{}/{}/{}/{}.region", .{saveFolder, pos.voxelSize, pos.wx, pos.wy, pos.wz}) catch unreachable;
		defer main.stackAllocator.free(path);
		const data = main.files.cubyzDir().read(main.stackAllocator, path) catch {
			return self;
		};
		defer main.stackAllocator.free(data);
		self.load(path, data) catch {
			std.log.err("Corrupted region file: {s}", .{path});
			if(@errorReturnTrace()) |trace| std.log.info("{f}", .{std.debug.FormatStackTrace{.stack_trace = trace.*, .tty_config = .no_color}});
		};
		return self;
	}

	fn load(self: *RegionFile, path: []const u8, data: []const u8) !void {
		var reader = BinaryReader.init(data);

		const fileVersion = try reader.readInt(u32);
		const fileSize = try reader.readInt(u32);

		if(fileVersion != version) {
			std.log.err("Region file {s} has incorrect version {}. Requires version {}.", .{path, fileVersion, version});
			return error.corrupted;
		}

		var chunkDataLengths: [regionVolume]u32 = undefined;
		var totalSize: usize = 0;
		for(0..regionVolume) |i| {
			const size = try reader.readInt(u32);
			chunkDataLengths[i] = size;
			totalSize += size;
		}

		if(fileSize != reader.remaining.len or totalSize != fileSize) {
			return error.corrupted;
		}

		for(0..regionVolume) |j| {
			const chunkDataLength = chunkDataLengths[j];
			if(chunkDataLength != 0) {
				self.chunks[j] = main.globalAllocator.dupe(u8, try reader.readSlice(chunkDataLength));
			}
		}
		if(reader.remaining.len != 0) {
			return error.corrupted;
		}
	}

	pub fn deinit(self: *RegionFile) void {
		std.debug.assert(self.refCount.raw == 0);
		std.debug.assert(!self.modified);
		for(self.chunks) |ch| {
			main.globalAllocator.free(ch);
		}
		main.globalAllocator.free(self.saveFolder);
		main.globalAllocator.destroy(self);
	}

	pub fn increaseRefCount(self: *RegionFile) void {
		const prevVal = self.refCount.fetchAdd(1, .monotonic);
		std.debug.assert(prevVal != 0);
	}

	pub fn decreaseRefCount(self: *RegionFile) void {
		const prevVal = self.refCount.fetchSub(1, .monotonic);
		std.debug.assert(prevVal != 0);
		if(prevVal == 1) {
			if(self.modified) {
				self.store();
			}
			self.deinit();
		} else if(prevVal == 2) {
			tryHashmapDeinit(self);
		}
	}

	pub fn store(self: *RegionFile) void {
		self.mutex.lock();
		defer self.mutex.unlock();
		self.modified = false;

		var totalSize: usize = 0;
		for(self.chunks) |ch| {
			totalSize += ch.len;
		}
		if(totalSize > std.math.maxInt(u32)) {
			std.log.err("Size of region file {} is too big to be stored", .{self.pos});
			return;
		}

		var writer = BinaryWriter.initCapacity(main.stackAllocator, totalSize + headerSize);
		defer writer.deinit();

		writer.writeInt(u32, version);
		writer.writeInt(u32, @intCast(totalSize));

		for(0..regionVolume) |i| {
			writer.writeInt(u32, @intCast(self.chunks[i].len));
		}
		for(0..regionVolume) |i| {
			writer.writeSlice(self.chunks[i]);
		}
		std.debug.assert(writer.data.items.len == totalSize + headerSize);

		const path = std.fmt.allocPrint(main.stackAllocator.allocator, "{s}/{}/{}/{}/{}.region", .{self.saveFolder, self.pos.voxelSize, self.pos.wx, self.pos.wy, self.pos.wz}) catch unreachable;
		defer main.stackAllocator.free(path);
		const folder = std.fmt.allocPrint(main.stackAllocator.allocator, "{s}/{}/{}/{}", .{self.saveFolder, self.pos.voxelSize, self.pos.wx, self.pos.wy}) catch unreachable;
		defer main.stackAllocator.free(folder);

		main.files.cubyzDir().makePath(folder) catch |err| {
			std.log.err("Error while writing to file {s}: {s}", .{path, @errorName(err)});
		};

		main.files.cubyzDir().write(path, writer.data.items) catch |err| {
			std.log.err("Error while writing to file {s}: {s}", .{path, @errorName(err)});
		};
	}

	pub fn storeChunk(self: *RegionFile, ch: []const u8, relX: usize, relY: usize, relZ: usize) void {
		self.mutex.lock();
		defer self.mutex.unlock();
		const index = getIndex(relX, relY, relZ);
		self.chunks[index] = main.globalAllocator.realloc(self.chunks[index], ch.len);
		@memcpy(self.chunks[index], ch);
		if(!self.modified) {
			self.modified = true;
			self.increaseRefCount();
			main.server.world.?.queueRegionFileUpdateAndDecreaseRefCount(self);
		}
	}

	pub fn getChunk(self: *RegionFile, allocator: main.heap.NeverFailingAllocator, relX: usize, relY: usize, relZ: usize) ?[]const u8 {
		self.mutex.lock();
		defer self.mutex.unlock();
		const index = getIndex(relX, relY, relZ);
		const ch = self.chunks[index];
		if(ch.len == 0) return null;
		return allocator.dupe(u8, ch);
	}
};

// MARK: cache
const cacheSize = 1 << 8; // Must be a power of 2!
const cacheMask = cacheSize - 1;
const associativity = 8;
var cache: main.utils.Cache(RegionFile, cacheSize, associativity, cacheDeinit) = .{};
const HashContext = struct {
	pub fn hash(_: HashContext, a: chunk.ChunkPosition) u64 {
		return a.hashCode();
	}
	pub fn eql(_: HashContext, a: chunk.ChunkPosition, b: chunk.ChunkPosition) bool {
		return std.meta.eql(a, b);
	}
};
var stillUsedHashMap: std.HashMap(chunk.ChunkPosition, *RegionFile, HashContext, 50) = undefined;
var hashMapMutex: std.Thread.Mutex = .{};

fn cacheDeinit(region: *RegionFile) void {
	if(region.refCount.load(.monotonic) != 1) { // Someone else might still use it, so we store it in the hashmap.
		hashMapMutex.lock();
		defer hashMapMutex.unlock();
		region.storedInHashMap = true;
		stillUsedHashMap.put(region.pos, region) catch unreachable;
	} else {
		region.decreaseRefCount();
	}
}
fn cacheInit(pos: chunk.ChunkPosition) *RegionFile {
	hashMapMutex.lock();
	if(stillUsedHashMap.fetchRemove(pos)) |kv| {
		const region = kv.value;
		region.storedInHashMap = false;
		hashMapMutex.unlock();
		return region;
	}
	hashMapMutex.unlock();
	const path: []const u8 = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/chunks", .{server.world.?.path}) catch unreachable;
	defer main.stackAllocator.free(path);
	return RegionFile.init(pos, path);
}
fn tryHashmapDeinit(region: *RegionFile) void {
	{
		hashMapMutex.lock();
		defer hashMapMutex.unlock();
		if(!region.storedInHashMap) return;
		std.debug.assert(stillUsedHashMap.fetchRemove(region.pos).?.value == region);
		region.storedInHashMap = false;
	}
	std.debug.assert(region.refCount.load(.unordered) == 1);
	region.decreaseRefCount();
}

pub fn init() void {
	stillUsedHashMap = .init(main.globalAllocator.allocator);
}

pub fn deinit() void {
	cache.clear();
	stillUsedHashMap.deinit();
}

pub fn loadRegionFileAndIncreaseRefCount(wx: i32, wy: i32, wz: i32, voxelSize: u31) *RegionFile {
	const compare = chunk.ChunkPosition{
		.wx = wx & ~@as(i32, RegionFile.regionSize*voxelSize - 1),
		.wy = wy & ~@as(i32, RegionFile.regionSize*voxelSize - 1),
		.wz = wz & ~@as(i32, RegionFile.regionSize*voxelSize - 1),
		.voxelSize = voxelSize,
	};
	const result = cache.findOrCreate(compare, cacheInit, RegionFile.increaseRefCount);
	return result;
}

pub const ChunkCompression = struct { // MARK: ChunkCompression
	const ChunkCompressionAlgo = enum(u32) {
		deflate_with_position_no_block_entities = 0,
		deflate_no_block_entities = 1,
		uniform = 2,
		deflate_with_8bit_palette_no_block_entities = 3,
		deflate = 4,
		deflate_with_8bit_palette = 5,
	};
	const BlockEntityCompressionAlgo = enum(u8) {
		raw = 0, // TODO: Maybe we need some basic compression at some point. For now this is good enough though.
	};

	const Target = enum {toClient, toDisk};

	pub fn storeChunk(allocator: main.heap.NeverFailingAllocator, ch: *chunk.Chunk, comptime target: Target, allowLossy: bool) []const u8 {
		var writer = BinaryWriter.init(allocator);

		compressBlockData(ch, allowLossy, &writer);
		compressBlockEntityData(ch, target, &writer);

		return writer.data.toOwnedSlice();
	}

	pub fn loadChunk(ch: *chunk.Chunk, comptime side: main.utils.Side, data: []const u8) !void {
		var reader = BinaryReader.init(data);
		try decompressBlockData(ch, &reader);
		try decompressBlockEntityData(ch, side, &reader);
	}

	fn compressBlockData(ch: *chunk.Chunk, allowLossy: bool, writer: *BinaryWriter) void {
		if(ch.data.palette().len == 1) {
			writer.writeEnum(ChunkCompressionAlgo, .uniform);
			writer.writeInt(u32, ch.data.palette()[0].load(.unordered).toInt());
			return;
		}
		if(ch.data.palette().len < 256) {
			var uncompressedData: [chunk.chunkVolume]u8 = undefined;
			var solidMask: [chunk.chunkSize*chunk.chunkSize]u32 = undefined;
			for(0..chunk.chunkVolume) |i| {
				uncompressedData[i] = @intCast(ch.data.impl.raw.data.getValue(i));
				if(allowLossy) {
					const block = ch.data.palette()[uncompressedData[i]].load(.unordered);
					const model = main.blocks.meshes.model(block).model();
					const occluder = model.allNeighborsOccluded and !block.viewThrough();
					if(occluder) {
						solidMask[i >> 5] |= @as(u32, 1) << @intCast(i & 31);
					} else {
						solidMask[i >> 5] &= ~(@as(u32, 1) << @intCast(i & 31));
					}
				}
			}
			if(allowLossy) {
				for(0..32) |x| {
					for(0..32) |y| {
						if(x == 0 or x == 31 or y == 0 or y == 31) {
							continue;
						}
						const index = x*32 + y;
						var colMask = solidMask[index] >> 1 & solidMask[index] << 1 & solidMask[index - 1] & solidMask[index + 1] & solidMask[index - 32] & solidMask[index + 32];
						while(colMask != 0) {
							const z = @ctz(colMask);
							colMask &= ~(@as(u32, 1) << @intCast(z));
							uncompressedData[index*32 + z] = uncompressedData[index*32 + z - 1];
						}
					}
				}
			}
			const compressedData = main.utils.Compression.deflate(main.stackAllocator, &uncompressedData, .default);
			defer main.stackAllocator.free(compressedData);

			writer.writeEnum(ChunkCompressionAlgo, .deflate_with_8bit_palette);
			writer.writeInt(u8, @intCast(ch.data.palette().len));

			for(0..ch.data.palette().len) |i| {
				writer.writeInt(u32, ch.data.palette()[i].load(.unordered).toInt());
			}
			writer.writeVarInt(usize, compressedData.len);
			writer.writeSlice(compressedData);
			return;
		}
		var uncompressedWriter = BinaryWriter.initCapacity(main.stackAllocator, chunk.chunkVolume*@sizeOf(u32));
		defer uncompressedWriter.deinit();

		for(0..chunk.chunkVolume) |i| {
			uncompressedWriter.writeInt(u32, ch.data.getValue(i).toInt());
		}
		const compressedData = main.utils.Compression.deflate(main.stackAllocator, uncompressedWriter.data.items, .default);
		defer main.stackAllocator.free(compressedData);

		writer.writeEnum(ChunkCompressionAlgo, .deflate);
		writer.writeVarInt(usize, compressedData.len);
		writer.writeSlice(compressedData);
	}

	fn decompressBlockData(ch: *chunk.Chunk, reader: *BinaryReader) !void {
		std.debug.assert(ch.data.palette().len == 1);

		const compressionAlgorithm = try reader.readEnum(ChunkCompressionAlgo);

		switch(compressionAlgorithm) {
			.deflate, .deflate_no_block_entities, .deflate_with_position_no_block_entities => {
				if(compressionAlgorithm == .deflate_with_position_no_block_entities) _ = try reader.readSlice(16);
				const decompressedData = main.stackAllocator.alloc(u8, chunk.chunkVolume*@sizeOf(u32));
				defer main.stackAllocator.free(decompressedData);

				const compressedDataLen = if(compressionAlgorithm == .deflate) try reader.readVarInt(usize) else reader.remaining.len;
				const compressedData = try reader.readSlice(compressedDataLen);
				const decompressedLength = try main.utils.Compression.inflateTo(decompressedData, compressedData);
				if(decompressedLength != chunk.chunkVolume*@sizeOf(u32)) return error.corrupted;

				var decompressedReader = BinaryReader.init(decompressedData);

				for(0..chunk.chunkVolume) |i| {
					ch.data.setValue(i, main.blocks.Block.fromInt(try decompressedReader.readInt(u32)));
				}
			},
			.deflate_with_8bit_palette, .deflate_with_8bit_palette_no_block_entities => {
				const paletteLength = try reader.readInt(u8);

				ch.data.deferredDeinit();
				ch.data.initCapacity(paletteLength);

				for(0..paletteLength) |i| {
					ch.data.palette()[i] = .init(main.blocks.Block.fromInt(try reader.readInt(u32)));
				}

				const decompressedData = main.stackAllocator.alloc(u8, chunk.chunkVolume);
				defer main.stackAllocator.free(decompressedData);

				const compressedDataLen = if(compressionAlgorithm == .deflate_with_8bit_palette) try reader.readVarInt(usize) else reader.remaining.len;
				const compressedData = try reader.readSlice(compressedDataLen);

				const decompressedLength = try main.utils.Compression.inflateTo(decompressedData, compressedData);
				if(decompressedLength != chunk.chunkVolume) return error.corrupted;

				for(0..chunk.chunkVolume) |i| {
					ch.data.setRawValue(i, decompressedData[i]);
				}
			},
			.uniform => {
				ch.data.palette()[0] = .init(main.blocks.Block.fromInt(try reader.readInt(u32)));
			},
		}
	}

	pub fn compressBlockEntityData(ch: *chunk.Chunk, comptime target: Target, writer: *BinaryWriter) void {
		ch.blockPosToEntityDataMapMutex.lock();
		defer ch.blockPosToEntityDataMapMutex.unlock();

		if(ch.blockPosToEntityDataMap.count() == 0) return;

		writer.writeEnum(BlockEntityCompressionAlgo, .raw);

		var iterator = ch.blockPosToEntityDataMap.iterator();
		while(iterator.next()) |entry| {
			const index = entry.key_ptr.*;
			const blockEntityIndex = entry.value_ptr.*;
			const block = ch.data.getValue(index);
			const blockEntity = block.blockEntity() orelse continue;

			var tempWriter = BinaryWriter.init(main.stackAllocator);
			defer tempWriter.deinit();

			if(target == .toDisk) {
				blockEntity.onStoreServerToDisk(blockEntityIndex, &tempWriter);
			} else {
				blockEntity.onStoreServerToClient(blockEntityIndex, &tempWriter);
			}

			if(tempWriter.data.items.len == 0) continue;

			writer.writeInt(u16, @intCast(index));
			writer.writeVarInt(usize, tempWriter.data.items.len);
			writer.writeSlice(tempWriter.data.items);
		}
	}

	pub fn decompressBlockEntityData(ch: *chunk.Chunk, comptime side: main.utils.Side, reader: *BinaryReader) !void {
		if(reader.remaining.len == 0) return;

		const compressionAlgo = try reader.readEnum(BlockEntityCompressionAlgo);
		std.debug.assert(compressionAlgo == .raw);

		while(reader.remaining.len != 0) {
			const index = try reader.readInt(u16);
			const pos = ch.getGlobalBlockPosFromIndex(index);
			const dataLength = try reader.readVarInt(usize);

			const blockEntityData = try reader.readSlice(dataLength);
			const block = ch.data.getValue(index);
			const blockEntity = block.blockEntity() orelse {
				std.log.err("Could not load BlockEntity at position {} for block {s}: Block has no block entity", .{pos, block.id()});
				continue;
			};

			var tempReader = BinaryReader.init(blockEntityData);
			if(side == .server) {
				blockEntity.onLoadServer(pos, ch, &tempReader) catch |err| {
					std.log.err("Could not load BlockEntity at position {} for block {s}: {s}", .{pos, block.id(), @errorName(err)});
					continue;
				};
			} else {
				try blockEntity.onLoadClient(pos, ch, &tempReader);
			}
		}
	}
};
