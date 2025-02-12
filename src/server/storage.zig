const std = @import("std");
const Atomic = std.atomic.Value;

const main = @import("root");
const chunk = main.chunk;
const server = @import("server.zig");

pub const RegionFile = struct { // MARK: RegionFile
	const version = 0;
	pub const regionShift = 2;
	pub const regionSize = 1 << regionShift;
	pub const regionVolume = 1 << 3*regionShift;

	const headerSize = 8 + regionSize*regionSize*regionSize*@sizeOf(u32);

	chunks: [regionVolume][]u8 = .{&.{}} ** regionVolume,
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
		std.debug.assert(pos.wx & (1 << chunk.chunkShift+regionShift)-1 == 0);
		std.debug.assert(pos.wy & (1 << chunk.chunkShift+regionShift)-1 == 0);
		std.debug.assert(pos.wz & (1 << chunk.chunkShift+regionShift)-1 == 0);
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
		if(data.len < headerSize) {
			std.log.err("Region file {s} is too small", .{path});
			return self;
		}
		var i: usize = 0;
		const fileVersion = std.mem.readInt(u32, data[i..][0..4], .big);
		i += 4;
		const fileSize = std.mem.readInt(u32, data[i..][0..4], .big);
		i += 4;
		if(fileVersion != version) {
			std.log.err("Region file {s} has incorrect version {}. Requires version {}.", .{path, fileVersion, version});
			return self;
		}
		var sizes: [regionVolume] u32 = undefined;
		var totalSize: usize = 0;
		for(0..regionVolume) |j| {
			const size = std.mem.readInt(u32, data[i..][0..4], .big);
			i += 4;
			sizes[j] = size;
			totalSize += size;
		}
		std.debug.assert(i == headerSize);
		if(fileSize != data.len - i or totalSize != fileSize) {
			std.log.err("Region file {s} is corrupted", .{path});
		}
		for(0..regionVolume) |j| {
			const size = sizes[j];
			if(size != 0) {
				self.chunks[j] = main.globalAllocator.alloc(u8, size);
				@memcpy(self.chunks[j], data[i..][0..size]);
				i += size;
			}
		}
		std.debug.assert(i == data.len);
		return self;
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

		const data = main.stackAllocator.alloc(u8, totalSize + headerSize);
		defer main.stackAllocator.free(data);
		var i: usize = 0;
		std.mem.writeInt(u32, data[i..][0..4], version, .big);
		i += 4;
		std.mem.writeInt(u32, data[i..][0..4], @intCast(totalSize), .big);
		i += 4;
		for(0..regionVolume) |j| {
			std.mem.writeInt(u32, data[i..][0..4], @intCast(self.chunks[j].len), .big);
			i += 4;
		}
		std.debug.assert(i == headerSize);

		for(0..regionVolume) |j| {
			const size = self.chunks[j].len;
			@memcpy(data[i..][0..size], self.chunks[j]);
			i += size;
		}
		std.debug.assert(i == data.len);

		const path = std.fmt.allocPrint(main.stackAllocator.allocator, "{s}/{}/{}/{}/{}.region", .{self.saveFolder, self.pos.voxelSize, self.pos.wx, self.pos.wy, self.pos.wz}) catch unreachable;
		defer main.stackAllocator.free(path);
		const folder = std.fmt.allocPrint(main.stackAllocator.allocator, "{s}/{}/{}/{}", .{self.saveFolder, self.pos.voxelSize, self.pos.wx, self.pos.wy}) catch unreachable;
		defer main.stackAllocator.free(folder);

		main.files.makeDir(folder) catch |err| {
			std.log.err("Error while writing to file {s}: {s}", .{path, @errorName(err)});
		};

		main.files.write(path, data) catch |err| {
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

	pub fn getChunk(self: *RegionFile, allocator: main.utils.NeverFailingAllocator, relX: usize, relY: usize, relZ: usize) ?[]const u8 {
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
	const compare = chunk.ChunkPosition {
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
	pub fn compressChunk(allocator: main.utils.NeverFailingAllocator, ch: *chunk.Chunk, allowLossy: bool) []const u8 {
		if(ch.data.paletteLength == 1) {
			const data = allocator.alloc(u8, 8);
			std.mem.writeInt(u32, data[0..4], @intFromEnum(CompressionAlgo.uniform), .big);
			std.mem.writeInt(u32, data[4..8], ch.data.palette[0].toInt(), .big);
			return data;
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

			const data = allocator.alloc(u8, 4 + 1 + 4*ch.data.paletteLength + compressedData.len);
			std.mem.writeInt(i32, data[0..4], @intFromEnum(CompressionAlgo.deflate_with_8bit_palette), .big);
			data[4] = @intCast(ch.data.paletteLength);
			for(0..ch.data.paletteLength) |i| {
				std.mem.writeInt(u32, data[5 + 4*i..][0..4], ch.data.palette[i].toInt(), .big);
			}
			@memcpy(data[5 + 4*ch.data.paletteLength..], compressedData);
			return data;
		}
		var uncompressedData: [chunk.chunkVolume*@sizeOf(u32)]u8 = undefined;
		for(0..chunk.chunkVolume) |i| {
			std.mem.writeInt(u32, uncompressedData[4*i..][0..4], ch.data.getValue(i).toInt(), .big);
		}
		const compressedData = main.utils.Compression.deflate(main.stackAllocator, &uncompressedData, .default);
		defer main.stackAllocator.free(compressedData);
		const data = allocator.alloc(u8, 4 + compressedData.len);

		@memcpy(data[4..], compressedData);
		std.mem.writeInt(i32, data[0..4], @intFromEnum(CompressionAlgo.deflate), .big);
		return data;
	}

	pub fn decompressChunk(ch: *chunk.Chunk, _data: []const u8) error{corrupted}!void {
		std.debug.assert(ch.data.paletteLength == 1);
		var data = _data;
		if(data.len < 4) return error.corrupted;
		const algo: CompressionAlgo = @enumFromInt(std.mem.readInt(u32, data[0..4], .big));
		data = data[4..];
		switch(algo) {
			.deflate, .deflate_with_position => {
				if(algo == .deflate_with_position) data = data[16..];
				const _inflatedData = main.stackAllocator.alloc(u8, chunk.chunkVolume*4);
				defer main.stackAllocator.free(_inflatedData);
				const _inflatedLen = main.utils.Compression.inflateTo(_inflatedData, data[0..]) catch return error.corrupted;
				if(_inflatedLen != chunk.chunkVolume*4) {
					return error.corrupted;
				}
				data = _inflatedData;
				for(0..chunk.chunkVolume) |i| {
					ch.data.setValue(i, main.blocks.Block.fromInt(std.mem.readInt(u32, data[0..4], .big)));
					data = data[4..];
				}
			},
			.deflate_with_8bit_palette => {
				const paletteLength = data[0];
				data = data[1..];
				ch.data.deinit();
				ch.data.initCapacity(paletteLength);
				for(0..paletteLength) |i| {
					ch.data.palette[i] = main.blocks.Block.fromInt(std.mem.readInt(u32, data[0..4], .big));
					data = data[4..];
				}
				const _inflatedData = main.stackAllocator.alloc(u8, chunk.chunkVolume);
				defer main.stackAllocator.free(_inflatedData);
				const _inflatedLen = main.utils.Compression.inflateTo(_inflatedData, data[0..]) catch return error.corrupted;
				if(_inflatedLen != chunk.chunkVolume) {
					return error.corrupted;
				}
				data = _inflatedData;
				for(0..chunk.chunkVolume) |i| {
					ch.data.setRawValue(i, data[i]);
				}
			},
			.uniform => {
				ch.data.palette[0] = main.blocks.Block.fromInt(std.mem.readInt(u32, data[0..4], .big));
			},
			_ => {
				return error.corrupted;
			},
		}
	}
};
