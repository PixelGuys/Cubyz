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
		const data = main.files.read(main.stackAllocator, path) catch {
			return self;
		};
		defer main.stackAllocator.free(data);
		self.load(path, data) catch {
			std.log.err("Corrupted region file: {s}", .{path});
			if(@errorReturnTrace()) |trace| std.log.info("{}", .{trace});
		};
		return self;
	}

	fn load(self: *RegionFile, path: []const u8, data: []const u8) !void {
		var reader = BinaryReader.init(data, .big);

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

		var writer = BinaryWriter.initCapacity(main.stackAllocator, .big, totalSize + headerSize);
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

		main.files.makeDir(folder) catch |err| {
			std.log.err("Error while writing to file {s}: {s}", .{path, @errorName(err)});
		};

		main.files.write(path, writer.data.items) catch |err| {
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
	const path: []const u8 = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/chunks", .{server.world.?.name}) catch unreachable;
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
	const CompressionAlgo = enum(u32) {
		deflate_with_position = 0,
		deflate = 1,
		uniform = 2,
		deflate_with_8bit_palette = 3,
		_,
	};
	pub fn compressChunk(allocator: main.heap.NeverFailingAllocator, ch: *chunk.Chunk, allowLossy: bool) []const u8 {
		if(ch.data.paletteLength == 1) {
			var writer = BinaryWriter.initCapacity(allocator, .big, @sizeOf(CompressionAlgo) + @sizeOf(u32));

			writer.writeEnum(CompressionAlgo, .uniform);
			writer.writeInt(u32, ch.data.palette[0].toInt());

			return writer.data.toOwnedSlice();
		}
		if(ch.data.paletteLength < 256) {
			var uncompressedData: [chunk.chunkVolume]u8 = undefined;
			var solidMask: [chunk.chunkSize*chunk.chunkSize]u32 = undefined;
			for(0..chunk.chunkVolume) |i| {
				uncompressedData[i] = @intCast(ch.data.data.getValue(i));
				if(allowLossy) {
					if(ch.data.palette[uncompressedData[i]].solid()) {
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

			var writer = BinaryWriter.initCapacity(allocator, .big, @sizeOf(CompressionAlgo) + @sizeOf(u8) + @sizeOf(u32)*ch.data.paletteLength + compressedData.len);

			writer.writeEnum(CompressionAlgo, .deflate_with_8bit_palette);
			writer.writeInt(u8, @intCast(ch.data.paletteLength));

			for(0..ch.data.paletteLength) |i| {
				writer.writeInt(u32, ch.data.palette[i].toInt());
			}
			writer.writeSlice(compressedData);
			return writer.data.toOwnedSlice();
		}
		var uncompressedWriter = BinaryWriter.initCapacity(main.stackAllocator, .big, chunk.chunkVolume*@sizeOf(u32));
		defer uncompressedWriter.deinit();

		for(0..chunk.chunkVolume) |i| {
			uncompressedWriter.writeInt(u32, ch.data.getValue(i).toInt());
		}
		const compressedData = main.utils.Compression.deflate(main.stackAllocator, uncompressedWriter.data.items, .default);
		defer main.stackAllocator.free(compressedData);

		var compressedWriter = BinaryWriter.initCapacity(allocator, .big, @sizeOf(CompressionAlgo) + compressedData.len);

		compressedWriter.writeEnum(CompressionAlgo, .deflate);
		compressedWriter.writeSlice(compressedData);

		return compressedWriter.data.toOwnedSlice();
	}

	pub fn decompressChunk(ch: *chunk.Chunk, _data: []const u8) !void {
		std.debug.assert(ch.data.paletteLength == 1);

		var reader = BinaryReader.init(_data, .big);
		const compressionAlgorithm = try reader.readEnum(CompressionAlgo);

		switch(compressionAlgorithm) {
			.deflate, .deflate_with_position => {
				if(compressionAlgorithm == .deflate_with_position) _ = try reader.readSlice(16);
				const decompressedData = main.stackAllocator.alloc(u8, chunk.chunkVolume*@sizeOf(u32));
				defer main.stackAllocator.free(decompressedData);

				const decompressedLength = try main.utils.Compression.inflateTo(decompressedData, reader.remaining);
				if(decompressedLength != chunk.chunkVolume*@sizeOf(u32)) return error.corrupted;

				var decompressedReader = BinaryReader.init(decompressedData, .big);

				for(0..chunk.chunkVolume) |i| {
					ch.data.setValue(i, main.blocks.Block.fromInt(try decompressedReader.readInt(u32)));
				}
			},
			.deflate_with_8bit_palette => {
				const paletteLength = try reader.readInt(u8);

				ch.data.deinit();
				ch.data.initCapacity(paletteLength);

				for(0..paletteLength) |i| {
					ch.data.palette[i] = main.blocks.Block.fromInt(try reader.readInt(u32));
				}

				const decompressedData = main.stackAllocator.alloc(u8, chunk.chunkVolume);
				defer main.stackAllocator.free(decompressedData);

				const decompressedLength = try main.utils.Compression.inflateTo(decompressedData, reader.remaining);
				if(decompressedLength != chunk.chunkVolume) return error.corrupted;

				for(0..chunk.chunkVolume) |i| {
					ch.data.setRawValue(i, decompressedData[i]);
				}
			},
			.uniform => {
				ch.data.palette[0] = main.blocks.Block.fromInt(try reader.readInt(u32));
			},
			_ => {
				return error.corrupted;
			},
		}
	}
};
