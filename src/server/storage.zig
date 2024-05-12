const std = @import("std");
const Atomic = std.atomic.Value;

const main = @import("root");
const chunk = main.chunk;
const server = @import("server.zig");

pub const RegionFile = struct {
	const version = 0;
	pub const regionShift = 2;
	pub const regionSize = 1 << regionShift;
	pub const regionVolume = 1 << 3*regionShift;

	const headerSize = 8 + regionSize*regionSize*regionSize*@sizeOf(u32);

	chunks: [regionVolume][]u8 = .{&.{}} ** regionVolume,
	pos: chunk.ChunkPosition,
	mutex: std.Thread.Mutex = .{},
	modified: bool = false,
	refCount: Atomic(u16) = Atomic(u16).init(1),
	saveFolder: []const u8,

	fn getIndex(x: usize, y: usize, z: usize) usize {
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
		self.modified = true;
		const index = getIndex(relX, relY, relZ);
		self.chunks[index] = main.globalAllocator.realloc(self.chunks[index], ch.len);
		@memcpy(self.chunks[index], ch);
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


const cacheSize = 1 << 8; // Must be a power of 2!
const cacheMask = cacheSize - 1;
const associativity = 8;
var cache: main.utils.Cache(RegionFile, cacheSize, associativity, RegionFile.decreaseRefCount) = .{};

fn cacheInit(pos: chunk.ChunkPosition) *RegionFile {
	const path: []const u8 = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/chunks", .{server.world.?.name}) catch unreachable;
	defer main.stackAllocator.free(path);
	return RegionFile.init(pos, path);
}

pub fn init() void {
}

pub fn deinit() void {
	cache.clear();
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

pub const ChunkCompression = struct {
	const CompressionAlgo = enum(u32) {
		deflate = 0, // TODO: Investigate if palette compression (or palette compression with huffman coding) is more efficient.
		_, // TODO: Add more algorithms for specific cases like uniform chunks.
	};
	pub fn compressChunk(allocator: main.utils.NeverFailingAllocator, ch: *chunk.Chunk) []const u8 {
		main.utils.assertLocked(&ch.mutex);
		var uncompressedData: [chunk.chunkVolume*@sizeOf(u32)]u8 = undefined;
		for(0..chunk.chunkVolume) |i| {
			std.mem.writeInt(u32, uncompressedData[4*i..][0..4], ch.data.getValue(i).toInt(), .big);
		}
		const compressedData = main.utils.Compression.deflate(main.stackAllocator, &uncompressedData);
		defer main.stackAllocator.free(compressedData);
		const data = allocator.alloc(u8, 20 + compressedData.len);
		@memcpy(data[20..], compressedData);
		std.mem.writeInt(i32, data[0..4], @intFromEnum(CompressionAlgo.deflate), .big);
		std.mem.writeInt(i32, data[4..8], ch.pos.wx, .big);
		std.mem.writeInt(i32, data[8..12], ch.pos.wy, .big);
		std.mem.writeInt(i32, data[12..16], ch.pos.wz, .big);
		std.mem.writeInt(i32, data[16..20], ch.pos.voxelSize, .big);
		return data;
	}

	pub fn decompressChunk(_data: []const u8) error{corrupted}!*chunk.Chunk {
		var data = _data;
		if(data.len < 4) return error.corrupted;
		const algo: CompressionAlgo = @enumFromInt(std.mem.readInt(u32, data[0..4], .big));
		data = data[4..];
		switch(algo) {
			.deflate => {
				if(data.len < 16) return error.corrupted;
				const pos = chunk.ChunkPosition{
					.wx = std.mem.readInt(i32, data[0..4], .big),
					.wy = std.mem.readInt(i32, data[4..8], .big),
					.wz = std.mem.readInt(i32, data[8..12], .big),
					.voxelSize = @intCast(std.mem.readInt(i32, data[12..16], .big)),
				};
				const _inflatedData = main.stackAllocator.alloc(u8, chunk.chunkVolume*4);
				defer main.stackAllocator.free(_inflatedData);
				const _inflatedLen = main.utils.Compression.inflateTo(_inflatedData, data[16..]) catch return error.corrupted;
				if(_inflatedLen != chunk.chunkVolume*4) {
					return error.corrupted;
				}
				data = _inflatedData;
				const ch = chunk.Chunk.init(pos);
				for(0..chunk.chunkVolume) |i| {
					ch.data.setValue(i, main.blocks.Block.fromInt(std.mem.readInt(u32, data[0..4], .big)));
					data = data[4..];
				}
				return ch;
			},
			_ => {
				return error.corrupted;
			},
		}
	}
};