const std = @import("std");

const chunk = @import("chunk.zig");
const Neighbor = chunk.Neighbor;
const graphics = @import("graphics.zig");
const main = @import("main");
const vec = @import("vec.zig");
const Vec3i = vec.Vec3i;
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;
const Vec2f = vec.Vec2f;
const Mat4f = vec.Mat4f;

const FaceData = main.renderer.chunk_meshing.FaceData;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const Box = main.game.collision.Box;

var quadSSBO: graphics.SSBO = undefined;

pub const QuadInfo = extern struct {
	normal: [3]f32 align(16),
	corners: [4][3]f32,
	cornerUV: [4][2]f32 align(8),
	textureSlot: u32,
	opaqueInLod: u32 = 0,

	pub fn normalVec(self: QuadInfo) Vec3f {
		return self.normal;
	}
	pub fn cornerVec(self: QuadInfo, i: usize) Vec3f {
		return self.corners[i];
	}
	pub fn cornerUvVec(self: QuadInfo, i: usize) Vec2f {
		return self.cornerUV[i];
	}
};

const ExtraQuadInfo = struct {
	faceNeighbor: ?Neighbor,
	isFullQuad: bool,
	hasOnlyCornerVertices: bool,
	alignedNormalDirection: ?Neighbor,
};

const gridSize = 4096;
const collisionGridSize = 16;
const CollisionGridInteger = std.meta.Int(.unsigned, collisionGridSize);

fn snapToGrid(x: anytype) @TypeOf(x) {
	const T = @TypeOf(x);
	const Vec = @Vector(x.len, std.meta.Child(T));
	const int = @as(@Vector(x.len, i32), @intFromFloat(std.math.round(@as(Vec, x)*@as(Vec, @splat(gridSize)))));
	return @as(Vec, @floatFromInt(int))/@as(Vec, @splat(gridSize));
}

const Triangle = struct {
	vertex: [3]usize,
	normal: usize,
	uvs: [3]usize,
};

const Quad = struct {
	vertex: [4]usize,
	normal: usize,
	uvs: [4]usize,
};

pub const ModelIndex = enum(u32) {
	_,

	pub fn model(self: ModelIndex) *const Model {
		return &models.items()[@intFromEnum(self)];
	}
	pub fn add(self: ModelIndex, offset: u32) ModelIndex {
		return @enumFromInt(@intFromEnum(self) + offset);
	}
};

pub const QuadIndex = enum(u16) {
	_,

	pub fn quadInfo(self: QuadIndex) *const QuadInfo {
		return &quads.items[@intFromEnum(self)];
	}

	pub fn extraQuadInfo(self: QuadIndex) *const ExtraQuadInfo {
		return &extraQuadInfos.items[@intFromEnum(self)];
	}
};

pub const Model = struct {
	min: Vec3f,
	max: Vec3f,
	internalQuads: []QuadIndex,
	neighborFacingQuads: [6][]QuadIndex,
	isNeighborOccluded: [6]bool,
	allNeighborsOccluded: bool,
	noNeighborsOccluded: bool,
	hasNeighborFacingQuads: bool,
	collision: []Box,

	fn getFaceNeighbor(quad: *const QuadInfo) ?chunk.Neighbor {
		var allZero: @Vector(3, bool) = .{true, true, true};
		var allOne: @Vector(3, bool) = .{true, true, true};
		for(quad.corners) |corner| {
			allZero = @select(bool, allZero, corner == @as(Vec3f, @splat(0)), allZero); // vector and TODO: #14306
			allOne = @select(bool, allOne, corner == @as(Vec3f, @splat(1)), allOne); // vector and TODO: #14306
		}
		if(allZero[0]) return .dirNegX;
		if(allZero[1]) return .dirNegY;
		if(allZero[2]) return .dirDown;
		if(allOne[0]) return .dirPosX;
		if(allOne[1]) return .dirPosY;
		if(allOne[2]) return .dirUp;
		return null;
	}

	fn fullyOccludesNeighbor(quad: *const QuadInfo) bool {
		var zeroes: @Vector(3, u32) = .{0, 0, 0};
		var ones: @Vector(3, u32) = .{0, 0, 0};
		for(quad.corners) |corner| {
			zeroes += @select(u32, corner == @as(Vec3f, @splat(0)), .{1, 1, 1}, .{0, 0, 0});
			ones += @select(u32, corner == @as(Vec3f, @splat(1)), .{1, 1, 1}, .{0, 0, 0});
		}
		// For full coverage there will 2 ones and 2 zeroes for two components, while the other one is constant.
		const hasTwoZeroes = zeroes == @Vector(3, u32){2, 2, 2};
		const hasTwoOnes = ones == @Vector(3, u32){2, 2, 2};
		return @popCount(@as(u3, @bitCast(hasTwoOnes))) == 2 and @popCount(@as(u3, @bitCast(hasTwoZeroes))) == 2;
	}

	pub fn init(quadInfos: []const QuadInfo) ModelIndex {
		const adjustedQuads = main.stackAllocator.alloc(QuadInfo, quadInfos.len);
		defer main.stackAllocator.free(adjustedQuads);
		for(adjustedQuads, quadInfos) |*dest, *src| {
			dest.* = src.*;
			// Snap all values to a fixed point grid to make comparisons more accurate.
			for(&dest.corners) |*corner| {
				corner.* = snapToGrid(corner.*);
			}
			for(&dest.cornerUV) |*uv| {
				uv.* = snapToGrid(uv.*);
			}
			// Snap the normals as well:
			dest.normal = snapToGrid(dest.normal);
		}
		const modelIndex: ModelIndex = @enumFromInt(models.len);
		const self = models.addOne();
		var amounts: [6]usize = .{0, 0, 0, 0, 0, 0};
		var internalAmount: usize = 0;
		self.min = .{1, 1, 1};
		self.max = .{0, 0, 0};
		self.isNeighborOccluded = @splat(false);
		for(adjustedQuads) |*quad| {
			for(quad.corners) |corner| {
				self.min = @min(self.min, @as(Vec3f, corner));
				self.max = @max(self.max, @as(Vec3f, corner));
			}
			if(getFaceNeighbor(quad)) |neighbor| {
				amounts[neighbor.toInt()] += 1;
			} else {
				internalAmount += 1;
			}
		}

		for(0..6) |i| {
			self.neighborFacingQuads[i] = main.globalAllocator.alloc(QuadIndex, amounts[i]);
		}
		self.internalQuads = main.globalAllocator.alloc(QuadIndex, internalAmount);

		var indices: [6]usize = .{0, 0, 0, 0, 0, 0};
		var internalIndex: usize = 0;
		for(adjustedQuads) |_quad| {
			var quad = _quad;
			if(getFaceNeighbor(&quad)) |neighbor| {
				for(&quad.corners) |*corner| {
					corner.* = @as(Vec3f, corner.*) - @as(Vec3f, quad.normal);
				}
				const quadIndex = addQuad(quad) catch continue;
				self.neighborFacingQuads[neighbor.toInt()][indices[neighbor.toInt()]] = quadIndex;
				indices[neighbor.toInt()] += 1;
			} else {
				const quadIndex = addQuad(quad) catch continue;
				self.internalQuads[internalIndex] = quadIndex;
				internalIndex += 1;
			}
		}
		for(0..6) |i| {
			self.neighborFacingQuads[i] = main.globalAllocator.realloc(self.neighborFacingQuads[i], indices[i]);
		}
		self.internalQuads = main.globalAllocator.realloc(self.internalQuads, internalIndex);
		self.hasNeighborFacingQuads = false;
		self.allNeighborsOccluded = true;
		self.noNeighborsOccluded = true;
		for(0..6) |neighbor| {
			for(self.neighborFacingQuads[neighbor]) |quad| {
				if(fullyOccludesNeighbor(quad.quadInfo())) {
					self.isNeighborOccluded[neighbor] = true;
				}
			}
			self.hasNeighborFacingQuads = self.hasNeighborFacingQuads or self.neighborFacingQuads[neighbor].len != 0;
			self.allNeighborsOccluded = self.allNeighborsOccluded and self.isNeighborOccluded[neighbor];
			self.noNeighborsOccluded = self.noNeighborsOccluded and !self.isNeighborOccluded[neighbor];
		}
		generateCollision(self, adjustedQuads);
		return modelIndex;
	}

	fn edgeInterp(y: f32, x0: f32, y0: f32, x1: f32, y1: f32) f32 {
		if(y1 == y0) return x0;
		return x0 + (x1 - x0)*(y - y0)/(y1 - y0);
	}

	fn solveDepth(normal: Vec3f, v0: Vec3f, xIndex: usize, yIndex: usize, zIndex: usize, u: f32, v: f32) f32 {
		const nX = @as([3]f32, normal)[xIndex];
		const nY = @as([3]f32, normal)[yIndex];
		const nZ = @as([3]f32, normal)[zIndex];

		const planeOffset = -vec.dot(v0, normal);

		return (-(nX*u + nY*v + planeOffset))/nZ;
	}

	fn rasterize(triangle: [3]Vec3f, grid: *[collisionGridSize][collisionGridSize]CollisionGridInteger, normal: Vec3f) void {
		var xIndex: usize = undefined;
		var yIndex: usize = undefined;
		var zIndex: usize = undefined;

		const v0 = triangle[0]*@as(Vec3f, @splat(@floatFromInt(collisionGridSize)));
		const v1 = triangle[1]*@as(Vec3f, @splat(@floatFromInt(collisionGridSize)));
		const v2 = triangle[2]*@as(Vec3f, @splat(@floatFromInt(collisionGridSize)));

		const absNormal = @abs(normal);
		if(absNormal[0] >= absNormal[1] and absNormal[0] >= absNormal[2]) {
			xIndex = 1;
			yIndex = 2;
			zIndex = 0;
		} else if(absNormal[1] >= absNormal[0] and absNormal[1] >= absNormal[2]) {
			xIndex = 0;
			yIndex = 2;
			zIndex = 1;
		} else {
			xIndex = 0;
			yIndex = 1;
			zIndex = 2;
		}

		const min: Vec3f = @min(v0, v1, v2);
		const max: Vec3f = @max(v0, v1, v2);

		const voxelMin: Vec3i = @max(@as(Vec3i, @intFromFloat(@floor(min))), @as(Vec3i, @splat(0)));
		const voxelMax: Vec3i = @max(@as(Vec3i, @intFromFloat(@ceil(max))), @as(Vec3i, @splat(0)));

		var p0 = Vec2f{@as([3]f32, v0)[xIndex], @as([3]f32, v0)[yIndex]};
		var p1 = Vec2f{@as([3]f32, v1)[xIndex], @as([3]f32, v1)[yIndex]};
		var p2 = Vec2f{@as([3]f32, v2)[xIndex], @as([3]f32, v2)[yIndex]};

		if(p0[1] > p1[1]) {
			std.mem.swap(Vec2f, &p0, &p1);
		}
		if(p0[1] > p2[1]) {
			std.mem.swap(Vec2f, &p0, &p2);
		}
		if(p1[1] > p2[1]) {
			std.mem.swap(Vec2f, &p1, &p2);
		}

		for(@intCast(@as([3]i32, voxelMin)[yIndex])..@intCast(@as([3]i32, voxelMax)[yIndex])) |y| {
			if(y >= collisionGridSize) continue;
			const yf = std.math.clamp(@as(f32, @floatFromInt(y)) + 0.5, @as([3]f32, min)[yIndex], @as([3]f32, max)[yIndex]);
			var xa: f32 = undefined;
			var xb: f32 = undefined;
			if(yf < p1[1]) {
				xa = edgeInterp(yf, p0[0], p0[1], p1[0], p1[1]);
				xb = edgeInterp(yf, p0[0], p0[1], p2[0], p2[1]);
			} else {
				xa = edgeInterp(yf, p1[0], p1[1], p2[0], p2[1]);
				xb = edgeInterp(yf, p0[0], p0[1], p2[0], p2[1]);
			}

			const xStart: f32 = @min(xa, xb);
			const xEnd: f32 = @max(xa, xb);

			const voxelXStart: usize = @intFromFloat(@max(@floor(xStart), 0.0));
			const voxelXEnd: usize = @intFromFloat(@max(@ceil(xEnd), 0.0));

			for(voxelXStart..voxelXEnd) |x| {
				if(x < 0 or x >= collisionGridSize) continue;
				const xf = std.math.clamp(@as(f32, @floatFromInt(x)) + 0.5, xStart, xEnd);

				const zf = solveDepth(normal, v0, xIndex, yIndex, zIndex, xf, yf);
				if(zf < 0.0) continue;
				const z: usize = @intFromFloat(zf);

				if(z >= collisionGridSize) continue;

				const pos: [3]usize = .{x, y, z};
				var realPos: [3]usize = undefined;
				realPos[xIndex] = pos[0];
				realPos[yIndex] = pos[1];
				realPos[zIndex] = pos[2];
				grid[realPos[0]][realPos[1]] |= @as(CollisionGridInteger, 1) << @intCast(realPos[2]);
			}
		}
	}

	fn generateCollision(self: *Model, modelQuads: []QuadInfo) void {
		var hollowGrid: [collisionGridSize][collisionGridSize]CollisionGridInteger = @splat(@splat(0));
		const voxelSize: Vec3f = @splat(1.0/@as(f32, collisionGridSize));

		for(modelQuads) |quad| {
			var shift = Vec3f{0, 0, 0};
			inline for(0..3) |i| {
				if(@abs(quad.normalVec()[i]) == 1.0 and @floor(quad.corners[0][i]*collisionGridSize) == quad.corners[0][i]*collisionGridSize) {
					shift = quad.normalVec()*voxelSize*@as(Vec3f, @splat(0.5));
				}
			}
			const triangle1: [3]Vec3f = .{
				quad.cornerVec(0) - shift,
				quad.cornerVec(1) - shift,
				quad.cornerVec(2) - shift,
			};
			const triangle2: [3]Vec3f = .{
				quad.cornerVec(1) - shift,
				quad.cornerVec(2) - shift,
				quad.cornerVec(3) - shift,
			};

			rasterize(triangle1, &hollowGrid, quad.normalVec());
			rasterize(triangle2, &hollowGrid, quad.normalVec());
		}

		const allOnes = ~@as(CollisionGridInteger, 0);
		var grid: [collisionGridSize][collisionGridSize]CollisionGridInteger = @splat(@splat(allOnes));

		var floodfillQueue = main.utils.CircularBufferQueue(struct {x: usize, y: usize, val: CollisionGridInteger}).init(main.stackAllocator, 1024);
		defer floodfillQueue.deinit();

		for(0..collisionGridSize) |x| {
			for(0..collisionGridSize) |y| {
				var val = 1 | @as(CollisionGridInteger, 1) << (@bitSizeOf(CollisionGridInteger) - 1);
				if(x == 0 or x == collisionGridSize - 1 or y == 0 or y == collisionGridSize - 1) val = allOnes;

				floodfillQueue.pushBack(.{.x = x, .y = y, .val = val});
			}
		}

		while(floodfillQueue.popFront()) |elem| {
			const oldValue = grid[elem.x][elem.y];
			const newValue = oldValue & ~(~hollowGrid[elem.x][elem.y] & elem.val);
			if(oldValue == newValue) continue;
			grid[elem.x][elem.y] = newValue;

			if(elem.x != 0) floodfillQueue.pushBack(.{.x = elem.x - 1, .y = elem.y, .val = ~newValue});
			if(elem.x != collisionGridSize - 1) floodfillQueue.pushBack(.{.x = elem.x + 1, .y = elem.y, .val = ~newValue});
			if(elem.y != 0) floodfillQueue.pushBack(.{.x = elem.x, .y = elem.y - 1, .val = ~newValue});
			if(elem.y != collisionGridSize - 1) floodfillQueue.pushBack(.{.x = elem.x, .y = elem.y + 1, .val = ~newValue});
			floodfillQueue.pushBack(.{.x = elem.x, .y = elem.y, .val = ~newValue << 1 | ~newValue >> 1});
		}

		var collision: main.List(Box) = .init(main.globalAllocator);

		for(0..collisionGridSize) |x| {
			for(0..collisionGridSize) |y| {
				while(grid[x][y] != 0) {
					const startZ = @ctz(grid[x][y]);
					const height = @min(@bitSizeOf(CollisionGridInteger) - startZ, @ctz(~grid[x][y] >> @intCast(startZ)));
					const mask = allOnes << @intCast(startZ) & ~((allOnes << 1) << @intCast(height + startZ - 1));

					const boxMin = Vec3i{@intCast(x), @intCast(y), startZ};
					var boxMax = Vec3i{@intCast(x + 1), @intCast(y + 1), startZ + height};

					while(canExpand(&grid, boxMin, boxMax, .x, mask)) boxMax[0] += 1;
					while(canExpand(&grid, boxMin, boxMax, .y, mask)) boxMax[1] += 1;
					disableAll(&grid, boxMin, boxMax, mask);

					const min = @as(Vec3f, @floatFromInt(boxMin))/@as(Vec3f, @splat(collisionGridSize));
					const max = @as(Vec3f, @floatFromInt(boxMax))/@as(Vec3f, @splat(collisionGridSize));

					collision.append(Box{.min = min, .max = max});
				}
			}
		}

		self.collision = collision.toOwnedSlice();
	}

	fn allTrue(grid: *const [collisionGridSize][collisionGridSize]CollisionGridInteger, min: Vec3i, max: Vec3i, mask: CollisionGridInteger) bool {
		if(max[0] > collisionGridSize or max[1] > collisionGridSize) {
			return false;
		}
		for(@intCast(min[0])..@intCast(max[0])) |x| {
			for(@intCast(min[1])..@intCast(max[1])) |y| {
				if((grid[x][y] & mask) != mask) {
					return false;
				}
			}
		}
		return true;
	}

	fn disableAll(grid: *[collisionGridSize][collisionGridSize]CollisionGridInteger, min: Vec3i, max: Vec3i, mask: CollisionGridInteger) void {
		for(@intCast(min[0])..@intCast(max[0])) |x| {
			for(@intCast(min[1])..@intCast(max[1])) |y| {
				grid[x][y] &= ~mask;
			}
		}
	}

	fn canExpand(grid: *const [collisionGridSize][collisionGridSize]CollisionGridInteger, min: Vec3i, max: Vec3i, dir: enum {x, y}, mask: CollisionGridInteger) bool {
		return switch(dir) {
			.x => allTrue(grid, Vec3i{max[0], min[1], min[2]}, Vec3i{max[0] + 1, max[1], max[2]}, mask),
			.y => allTrue(grid, Vec3i{min[0], max[1], min[2]}, Vec3i{max[0], max[1] + 1, max[2]}, mask),
		};
	}

	fn addVert(vert: Vec3f, vertList: *main.List(Vec3f)) usize {
		const ind = for(vertList.*.items, 0..) |vertex, index| {
			if(vertex == vert) break index;
		} else vertList.*.items.len;

		if(ind == vertList.*.items.len) {
			vertList.*.append(vert);
		}

		return ind;
	}

	pub fn loadModel(data: []const u8) ModelIndex {
		const quadInfos = loadRawModelDataFromObj(main.stackAllocator, data);
		defer main.stackAllocator.free(quadInfos);
		for(quadInfos) |*quad| {
			var minUv: Vec2f = @splat(std.math.inf(f32));
			for(0..4) |i| {
				quad.cornerUV[i] = @as(Vec2f, quad.cornerUV[i])*@as(Vec2f, @splat(4));
				minUv = @min(minUv, @as(Vec2f, quad.cornerUV[i]));
			}
			minUv = @floor(minUv);
			quad.textureSlot = @as(u32, @intFromFloat(minUv[1]))*4 + @as(u32, @intFromFloat(minUv[0]));

			if(minUv[0] < 0 or minUv[0] > 4 or minUv[1] < 0 or minUv[1] > 4) {
				std.log.err("Uv value for model is outside of 0-1 range", .{});
			}

			for(0..4) |i| {
				quad.cornerUV[i] = @as(Vec2f, quad.cornerUV[i]) - minUv;
			}
		}
		return Model.init(quadInfos);
	}

	pub fn loadRawModelDataFromObj(allocator: main.heap.NeverFailingAllocator, data: []const u8) []QuadInfo {
		var vertices = main.List(Vec3f).init(main.stackAllocator);
		defer vertices.deinit();

		var normals = main.List(Vec3f).init(main.stackAllocator);
		defer normals.deinit();

		var uvs = main.List(Vec2f).init(main.stackAllocator);
		defer uvs.deinit();

		var tris = main.List(Triangle).init(main.stackAllocator);
		defer tris.deinit();

		var quadFaces = main.List(Quad).init(main.stackAllocator);
		defer quadFaces.deinit();

		var splitIterator = std.mem.splitScalar(u8, data, '\n');
		while(splitIterator.next()) |lineUntrimmed| {
			if(lineUntrimmed.len < 3)
				continue;

			var line = lineUntrimmed;
			if(line[line.len - 1] == '\r') {
				line = line[0 .. line.len - 1];
			}

			if(line[0] == '#')
				continue;

			if(std.mem.eql(u8, line[0..2], "v ")) {
				var coordsIter = std.mem.splitScalar(u8, line[2..], ' ');
				var coords: [3]f32 = undefined;
				var i: usize = 0;
				while(coordsIter.next()) |coord| : (i += 1) {
					coords[i] = std.fmt.parseFloat(f32, coord) catch |e| blk: {
						std.log.err("Failed parsing {s} into float: {any}", .{coord, e});
						break :blk 0;
					};
				}
				vertices.append(coords);
			} else if(std.mem.eql(u8, line[0..3], "vn ")) {
				var coordsIter = std.mem.splitScalar(u8, line[3..], ' ');
				var norm: [3]f32 = undefined;
				var i: usize = 0;
				while(coordsIter.next()) |coord| : (i += 1) {
					norm[i] = std.fmt.parseFloat(f32, coord) catch |e| blk: {
						std.log.err("Failed parsing {s} into float: {any}", .{coord, e});
						break :blk 0;
					};
				}
				normals.append(norm);
			} else if(std.mem.eql(u8, line[0..3], "vt ")) {
				var coordsIter = std.mem.splitScalar(u8, line[3..], ' ');
				var uv: [2]f32 = undefined;
				var i: usize = 0;
				while(coordsIter.next()) |coord| : (i += 1) {
					uv[i] = std.fmt.parseFloat(f32, coord) catch |e| blk: {
						std.log.err("Failed parsing {s} into float: {any}", .{coord, e});
						break :blk 0;
					};
				}
				uvs.append(uv);
			} else if(std.mem.eql(u8, line[0..2], "f ")) {
				var coordsIter = std.mem.splitScalar(u8, line[2..], ' ');
				var faceData: [3][4]usize = undefined;
				var i: usize = 0;
				var failed = false;
				while(coordsIter.next()) |vertex| : (i += 1) {
					if(i >= 4) {
						failed = true;
						std.log.err("More than 4 verticies in a face", .{});
						break;
					}
					var d = std.mem.splitScalar(u8, vertex, '/');
					var j: usize = 0;
					if(std.mem.count(u8, vertex, "/") != 2 or std.mem.count(u8, vertex, "//") != 0) {
						failed = true;
						std.log.err("Failed loading face {s}. Each vertex must use vertex/uv/normal", .{line});
						break;
					}
					while(d.next()) |value| : (j += 1) {
						faceData[j][i] = std.fmt.parseUnsigned(usize, value, 10) catch |e| blk: {
							std.log.err("Failed parsing {s} into uint: {any}", .{value, e});
							break :blk 1;
						};
						faceData[j][i] -= 1;
					}
				}
				if(!failed) {
					switch(i) {
						3 => {
							tris.append(.{.vertex = faceData[0][0..3].*, .uvs = faceData[1][0..3].*, .normal = faceData[2][0]});
						},
						4 => {
							quadFaces.append(.{.vertex = faceData[0], .uvs = faceData[1], .normal = faceData[2][0]});
						},
						else => std.log.err("Failed loading face {s} with {d} vertices", .{line, i}),
					}
				}
			}
		}

		var quadInfos = main.List(QuadInfo).initCapacity(allocator, tris.items.len + quads.items.len);
		defer quadInfos.deinit();

		for(tris.items) |face| {
			const normal: Vec3f = normals.items[face.normal];

			const uvA: Vec2f = uvs.items[face.uvs[0]];
			const uvB: Vec2f = uvs.items[face.uvs[2]];
			const uvC: Vec2f = uvs.items[face.uvs[1]];

			const cornerA: Vec3f = vertices.items[face.vertex[0]];
			const cornerB: Vec3f = vertices.items[face.vertex[2]];
			const cornerC: Vec3f = vertices.items[face.vertex[1]];

			quadInfos.append(.{
				.normal = normal,
				.corners = .{cornerA, cornerB, cornerC, cornerB},
				.cornerUV = .{uvA, uvB, uvC, uvB},
				.textureSlot = 0,
			});
		}

		for(quadFaces.items) |face| {
			const normal: Vec3f = normals.items[face.normal];

			const uvA: Vec2f = uvs.items[face.uvs[1]];
			const uvB: Vec2f = uvs.items[face.uvs[0]];
			const uvC: Vec2f = uvs.items[face.uvs[2]];
			const uvD: Vec2f = uvs.items[face.uvs[3]];

			const cornerA: Vec3f = vertices.items[face.vertex[1]];
			const cornerB: Vec3f = vertices.items[face.vertex[0]];
			const cornerC: Vec3f = vertices.items[face.vertex[2]];
			const cornerD: Vec3f = vertices.items[face.vertex[3]];

			quadInfos.append(.{
				.normal = normal,
				.corners = .{cornerA, cornerB, cornerC, cornerD},
				.cornerUV = .{uvA, uvB, uvC, uvD},
				.textureSlot = 0,
			});
		}

		return quadInfos.toOwnedSlice();
	}

	fn deinit(self: *const Model) void {
		for(0..6) |i| {
			main.globalAllocator.free(self.neighborFacingQuads[i]);
		}
		main.globalAllocator.free(self.internalQuads);
		main.globalAllocator.free(self.collision);
	}

	pub fn getRawFaces(model: Model, quadList: *main.List(QuadInfo)) void {
		for(model.internalQuads) |quadIndex| {
			quadList.append(quadIndex.quadInfo().*);
		}
		for(0..6) |neighbor| {
			for(model.neighborFacingQuads[neighbor]) |quadIndex| {
				var quad = quadIndex.quadInfo().*;
				for(&quad.corners) |*corner| {
					corner.* = @as(Vec3f, corner.*) + @as(Vec3f, quad.normal);
				}
				quadList.append(quad);
			}
		}
	}

	pub fn mergeModels(modelList: []ModelIndex) ModelIndex {
		var quadList = main.List(QuadInfo).init(main.stackAllocator);
		defer quadList.deinit();
		for(modelList) |model| {
			model.model().getRawFaces(&quadList);
		}
		return Model.init(quadList.items);
	}

	pub fn transformModel(model: Model, transformFunction: anytype, transformFunctionParameters: anytype) ModelIndex {
		var quadList = main.List(QuadInfo).init(main.stackAllocator);
		defer quadList.deinit();
		model.getRawFaces(&quadList);
		for(quadList.items) |*quad| {
			@call(.auto, transformFunction, .{quad} ++ transformFunctionParameters);
		}
		return Model.init(quadList.items);
	}

	fn appendQuadsToList(quadList: []const QuadIndex, list: *main.ListUnmanaged(FaceData), allocator: NeverFailingAllocator, block: main.blocks.Block, x: i32, y: i32, z: i32, comptime backFace: bool) void {
		for(quadList) |quadIndex| {
			const texture = main.blocks.meshes.textureIndex(block, quadIndex.quadInfo().textureSlot);
			list.append(allocator, FaceData.init(texture, quadIndex, x, y, z, backFace));
		}
	}

	pub fn appendInternalQuadsToList(self: *const Model, list: *main.ListUnmanaged(FaceData), allocator: NeverFailingAllocator, block: main.blocks.Block, x: i32, y: i32, z: i32, comptime backFace: bool) void {
		appendQuadsToList(self.internalQuads, list, allocator, block, x, y, z, backFace);
	}

	pub fn appendNeighborFacingQuadsToList(self: *const Model, list: *main.ListUnmanaged(FaceData), allocator: NeverFailingAllocator, block: main.blocks.Block, neighbor: Neighbor, x: i32, y: i32, z: i32, comptime backFace: bool) void {
		appendQuadsToList(self.neighborFacingQuads[neighbor.toInt()], list, allocator, block, x, y, z, backFace);
	}
};

var nameToIndex: std.StringHashMap(ModelIndex) = undefined;

pub fn getModelIndex(string: []const u8) ModelIndex {
	return nameToIndex.get(string) orelse {
		std.log.err("Couldn't find voxelModel with name: {s}.", .{string});
		return @enumFromInt(0);
	};
}

var quads: main.List(QuadInfo) = undefined;
var extraQuadInfos: main.List(ExtraQuadInfo) = undefined;
var models: main.utils.VirtualList(Model, 1 << 20) = undefined;

var quadDeduplication: std.AutoHashMap([@sizeOf(QuadInfo)]u8, QuadIndex) = undefined;

fn addQuad(info_: QuadInfo) error{Degenerate}!QuadIndex {
	var info = info_;
	if(quadDeduplication.get(std.mem.toBytes(info))) |id| {
		return id;
	}
	// Check if it's degenerate:
	var cornerEqualities: u32 = 0;
	for(0..4) |i| {
		for(i + 1..4) |j| {
			if(@reduce(.And, @as(Vec3f, info.corners[i]) == @as(Vec3f, info.corners[j]))) cornerEqualities += 1;
		}
	}
	if(cornerEqualities >= 2) return error.Degenerate; // One corner equality is fine, since then the quad degenerates to a triangle, which has a non-zero area.
	const index: QuadIndex = @enumFromInt(quads.items.len);
	if(info.opaqueInLod == 2) {
		info.opaqueInLod = 0;
	} else {
		info.opaqueInLod = @intFromBool(Model.getFaceNeighbor(&info) != null);
	}
	quads.append(info);
	quadDeduplication.put(std.mem.toBytes(info), index) catch unreachable;

	var extraQuadInfo: ExtraQuadInfo = undefined;
	extraQuadInfo.faceNeighbor = Model.getFaceNeighbor(&info);
	extraQuadInfo.isFullQuad = Model.fullyOccludesNeighbor(&info);
	{
		var zeroes: @Vector(3, u32) = .{0, 0, 0};
		var ones: @Vector(3, u32) = .{0, 0, 0};
		for(info.corners) |corner| {
			zeroes += @select(u32, corner == @as(Vec3f, @splat(0)), .{1, 1, 1}, .{0, 0, 0});
			ones += @select(u32, corner == @as(Vec3f, @splat(1)), .{1, 1, 1}, .{0, 0, 0});
		}
		const cornerValues = @reduce(.Add, zeroes) + @reduce(.Add, ones);
		extraQuadInfo.hasOnlyCornerVertices = cornerValues == 4*3;
	}
	{
		extraQuadInfo.alignedNormalDirection = null;
		if(@reduce(.And, info.normal == Vec3f{-1, 0, 0})) extraQuadInfo.alignedNormalDirection = .dirNegX;
		if(@reduce(.And, info.normal == Vec3f{1, 0, 0})) extraQuadInfo.alignedNormalDirection = .dirPosX;
		if(@reduce(.And, info.normal == Vec3f{0, -1, 0})) extraQuadInfo.alignedNormalDirection = .dirNegY;
		if(@reduce(.And, info.normal == Vec3f{0, 1, 0})) extraQuadInfo.alignedNormalDirection = .dirPosY;
		if(@reduce(.And, info.normal == Vec3f{0, 0, -1})) extraQuadInfo.alignedNormalDirection = .dirDown;
		if(@reduce(.And, info.normal == Vec3f{0, 0, 1})) extraQuadInfo.alignedNormalDirection = .dirUp;
	}
	extraQuadInfos.append(extraQuadInfo);

	return index;
}

fn box(min: Vec3f, max: Vec3f, uvOffset: Vec2f) [6]QuadInfo {
	const corner000: Vec3f = .{min[0], min[1], min[2]};
	const corner001: Vec3f = .{min[0], min[1], max[2]};
	const corner010: Vec3f = .{min[0], max[1], min[2]};
	const corner011: Vec3f = .{min[0], max[1], max[2]};
	const corner100: Vec3f = .{max[0], min[1], min[2]};
	const corner101: Vec3f = .{max[0], min[1], max[2]};
	const corner110: Vec3f = .{max[0], max[1], min[2]};
	const corner111: Vec3f = .{max[0], max[1], max[2]};
	return .{
		.{
			.normal = .{-1, 0, 0},
			.corners = .{corner010, corner011, corner000, corner001},
			.cornerUV = .{uvOffset + Vec2f{1 - max[1], min[2]}, uvOffset + Vec2f{1 - max[1], max[2]}, uvOffset + Vec2f{1 - min[1], min[2]}, uvOffset + Vec2f{1 - min[1], max[2]}},
			.textureSlot = Neighbor.dirNegX.toInt(),
		},
		.{
			.normal = .{1, 0, 0},
			.corners = .{corner100, corner101, corner110, corner111},
			.cornerUV = .{uvOffset + Vec2f{min[1], min[2]}, uvOffset + Vec2f{min[1], max[2]}, uvOffset + Vec2f{max[1], min[2]}, uvOffset + Vec2f{max[1], max[2]}},
			.textureSlot = Neighbor.dirPosX.toInt(),
		},
		.{
			.normal = .{0, -1, 0},
			.corners = .{corner000, corner001, corner100, corner101},
			.cornerUV = .{uvOffset + Vec2f{min[0], min[2]}, uvOffset + Vec2f{min[0], max[2]}, uvOffset + Vec2f{max[0], min[2]}, uvOffset + Vec2f{max[0], max[2]}},
			.textureSlot = Neighbor.dirNegY.toInt(),
		},
		.{
			.normal = .{0, 1, 0},
			.corners = .{corner110, corner111, corner010, corner011},
			.cornerUV = .{uvOffset + Vec2f{1 - max[0], min[2]}, uvOffset + Vec2f{1 - max[0], max[2]}, uvOffset + Vec2f{1 - min[0], min[2]}, uvOffset + Vec2f{1 - min[0], max[2]}},
			.textureSlot = Neighbor.dirPosY.toInt(),
		},
		.{
			.normal = .{0, 0, -1},
			.corners = .{corner010, corner000, corner110, corner100},
			.cornerUV = .{uvOffset + Vec2f{min[0], 1 - max[1]}, uvOffset + Vec2f{min[0], 1 - min[1]}, uvOffset + Vec2f{max[0], 1 - max[1]}, uvOffset + Vec2f{max[0], 1 - min[1]}},
			.textureSlot = Neighbor.dirDown.toInt(),
		},
		.{
			.normal = .{0, 0, 1},
			.corners = .{corner111, corner101, corner011, corner001},
			.cornerUV = .{uvOffset + Vec2f{1 - max[0], 1 - max[1]}, uvOffset + Vec2f{1 - max[0], 1 - min[1]}, uvOffset + Vec2f{1 - min[0], 1 - max[1]}, uvOffset + Vec2f{1 - min[0], 1 - min[1]}},
			.textureSlot = Neighbor.dirUp.toInt(),
		},
	};
}

fn openBox(min: Vec3f, max: Vec3f, uvOffset: Vec2f, openSide: enum {x, y, z}) [4]QuadInfo {
	const fullBox = box(min, max, uvOffset);
	switch(openSide) {
		.x => return fullBox[2..6].*,
		.y => return fullBox[0..2].* ++ fullBox[4..6].*,
		.z => return fullBox[0..4].*,
	}
}

pub fn registerModel(id: []const u8, data: []const u8) ModelIndex {
	const model = Model.loadModel(data);
	nameToIndex.put(id, model) catch unreachable;
	return model;
}

// TODO: Entity models.
pub fn init() void {
	models = .init();
	quads = .init(main.globalAllocator);
	extraQuadInfos = .init(main.globalAllocator);
	quadDeduplication = .init(main.globalAllocator.allocator);

	nameToIndex = .init(main.globalAllocator.allocator);

	nameToIndex.put("none", Model.init(&.{})) catch unreachable;
}

pub fn reset() void {
	for(models.items()) |model| {
		model.deinit();
	}
	models.clearRetainingCapacity();
	quads.clearRetainingCapacity();
	extraQuadInfos.clearRetainingCapacity();
	quadDeduplication.clearRetainingCapacity();
	nameToIndex.clearRetainingCapacity();
	nameToIndex.put("none", Model.init(&.{})) catch unreachable;
}

pub fn deinit() void {
	quadSSBO.deinit();
	nameToIndex.deinit();
	for(models.items()) |model| {
		model.deinit();
	}
	models.deinit();
	quads.deinit();
	extraQuadInfos.deinit();
	quadDeduplication.deinit();
}

pub fn uploadModels() void {
	quadSSBO = graphics.SSBO.initStatic(QuadInfo, quads.items);
	quadSSBO.bind(4);
}
