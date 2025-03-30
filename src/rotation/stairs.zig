const std = @import("std");

const main = @import("main");
const blocks = main.blocks;
const Block = blocks.Block;
const Neighbor = main.chunk.Neighbor;
const ModelIndex = main.models.ModelIndex;
const rotation = main.rotation;
const Degrees = rotation.Degrees;
const RayIntersectionResult = rotation.RayIntersectionResult;
const RotationMode = rotation.RotationMode;
const vec = main.vec;
const Mat4f = vec.Mat4f;
const Vec2f = vec.Vec2f;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;
const ZonElement = main.ZonElement;

var modelIndex: ?ModelIndex = null;

fn subBlockMask(x: u1, y: u1, z: u1) u8 {
	return @as(u8, 1) << ((@as(u3, x)*2 + @as(u3, y))*2 + z);
}
fn hasSubBlock(stairData: u8, x: u1, y: u1, z: u1) bool {
	return stairData & subBlockMask(x, y, z) == 0;
}

pub fn rotateZ(data: u16, angle: Degrees) u16 {
	@setEvalBranchQuota(65_536);

	comptime var rotationTable: [4][256]u8 = undefined;
	comptime for(0..4) |a| {
		for(0..256) |old| {
			var new: u8 = 0b11_11_11_11;

			for(0..2) |i| for(0..2) |j| for(0..2) |k| {
				const sin: f32 = @sin((std.math.pi/2.0)*@as(f32, @floatFromInt(a)));
				const cos: f32 = @cos((std.math.pi/2.0)*@as(f32, @floatFromInt(a)));

				const x: f32 = (@as(f32, @floatFromInt(i)) - 0.5)*2.0;
				const y: f32 = (@as(f32, @floatFromInt(j)) - 0.5)*2.0;

				const rX = @intFromBool(x*cos - y*sin > 0);
				const rY = @intFromBool(x*sin + y*cos > 0);

				if(hasSubBlock(@intCast(old), @intCast(i), @intCast(j), @intCast(k))) {
					new &= ~subBlockMask(rX, rY, @intCast(k));
				}
			};
			rotationTable[a][old] = new;
		}
	};
	if(data >= 256) return 0;
	return rotationTable[@intFromEnum(angle)][data];
}

pub fn init() void {}
pub fn deinit() void {}
pub fn reset() void {
	modelIndex = null;
}

const GreedyFaceInfo = struct {min: Vec2f, max: Vec2f};
fn mergeFaces(faceVisible: [2][2]bool, mem: []GreedyFaceInfo) []GreedyFaceInfo {
	var faces: usize = 0;
	if(faceVisible[0][0]) {
		if(faceVisible[0][1]) {
			if(faceVisible[1][0] and faceVisible[1][1]) {
				// One big face:
				mem[faces] = .{.min = .{0, 0}, .max = .{1, 1}};
				faces += 1;
			} else {
				mem[faces] = .{.min = .{0, 0}, .max = .{0.5, 1}};
				faces += 1;
				if(faceVisible[1][0]) {
					mem[faces] = .{.min = .{0.5, 0}, .max = .{1, 0.5}};
					faces += 1;
				}
				if(faceVisible[1][1]) {
					mem[faces] = .{.min = .{0.5, 0.5}, .max = .{1, 1}};
					faces += 1;
				}
			}
		} else {
			if(faceVisible[1][0]) {
				mem[faces] = .{.min = .{0, 0}, .max = .{1.0, 0.5}};
				faces += 1;
			} else {
				mem[faces] = .{.min = .{0, 0}, .max = .{0.5, 0.5}};
				faces += 1;
			}
			if(faceVisible[1][1]) {
				mem[faces] = .{.min = .{0.5, 0.5}, .max = .{1, 1}};
				faces += 1;
			}
		}
	} else {
		if(faceVisible[0][1]) {
			if(faceVisible[1][1]) {
				mem[faces] = .{.min = .{0, 0.5}, .max = .{1, 1}};
				faces += 1;
			} else {
				mem[faces] = .{.min = .{0, 0.5}, .max = .{0.5, 1}};
				faces += 1;
			}
			if(faceVisible[1][0]) {
				mem[faces] = .{.min = .{0.5, 0}, .max = .{1, 0.5}};
				faces += 1;
			}
		} else {
			if(faceVisible[1][0]) {
				if(faceVisible[1][1]) {
					mem[faces] = .{.min = .{0.5, 0}, .max = .{1, 1.0}};
					faces += 1;
				} else {
					mem[faces] = .{.min = .{0.5, 0}, .max = .{1, 0.5}};
					faces += 1;
				}
			} else if(faceVisible[1][1]) {
				mem[faces] = .{.min = .{0.5, 0.5}, .max = .{1, 1}};
				faces += 1;
			}
		}
	}
	return mem[0..faces];
}

pub fn createBlockModel(_: Block, _: *u16, _: ZonElement) ModelIndex {
	if(modelIndex) |idx| return idx;
	for(0..256) |i| {
		var quads = main.List(main.models.QuadInfo).init(main.stackAllocator);
		defer quads.deinit();
		for(Neighbor.iterable) |neighbor| {
			const xComponent = @abs(neighbor.textureX());
			const yComponent = @abs(neighbor.textureY());
			const normal = Vec3i{neighbor.relX(), neighbor.relY(), neighbor.relZ()};
			const zComponent = @abs(normal);
			const zMap: [2]@Vector(3, u32) = if(@reduce(.Add, normal) > 0) .{@splat(0), @splat(1)} else .{@splat(1), @splat(0)};
			var visibleFront: [2][2]bool = undefined;
			var visibleMiddle: [2][2]bool = undefined;
			for(0..2) |x| {
				for(0..2) |y| {
					const xSplat: @TypeOf(xComponent) = @splat(@intCast(x));
					const ySplat: @TypeOf(xComponent) = @splat(@intCast(y));
					const posFront = xComponent*xSplat + yComponent*ySplat + zComponent*zMap[1];
					const posBack = xComponent*xSplat + yComponent*ySplat + zComponent*zMap[0];
					visibleFront[x][y] = hasSubBlock(@intCast(i), @intCast(posFront[0]), @intCast(posFront[1]), @intCast(posFront[2]));
					visibleMiddle[x][y] = !visibleFront[x][y] and hasSubBlock(@intCast(i), @intCast(posBack[0]), @intCast(posBack[1]), @intCast(posBack[2]));
				}
			}
			const xAxis = @as(Vec3f, @floatFromInt(neighbor.textureX()));
			const yAxis = @as(Vec3f, @floatFromInt(neighbor.textureY()));
			const zAxis = @as(Vec3f, @floatFromInt(normal));
			// Greedy mesh it:
			var faces: [2]GreedyFaceInfo = undefined;
			const frontFaces = mergeFaces(visibleFront, &faces);
			for(frontFaces) |*face| {
				var xLower = @abs(xAxis)*@as(Vec3f, @splat(face.min[0]));
				var xUpper = @abs(xAxis)*@as(Vec3f, @splat(face.max[0]));
				if(@reduce(.Add, xAxis) < 0) std.mem.swap(Vec3f, &xLower, &xUpper);
				var yLower = @abs(yAxis)*@as(Vec3f, @splat(face.min[1]));
				var yUpper = @abs(yAxis)*@as(Vec3f, @splat(face.max[1]));
				if(@reduce(.Add, yAxis) < 0) std.mem.swap(Vec3f, &yLower, &yUpper);
				const zValue: Vec3f = @floatFromInt(zComponent*zMap[1]);
				if(neighbor == .dirNegX or neighbor == .dirPosY) {
					face.min[0] = 1 - face.min[0];
					face.max[0] = 1 - face.max[0];
					const swap = face.min[0];
					face.min[0] = face.max[0];
					face.max[0] = swap;
				}
				if(neighbor == .dirUp) {
					face.min = Vec2f{1, 1} - face.min;
					face.max = Vec2f{1, 1} - face.max;
					std.mem.swap(Vec2f, &face.min, &face.max);
				}
				if(neighbor == .dirDown) {
					face.min[1] = 1 - face.min[1];
					face.max[1] = 1 - face.max[1];
					const swap = face.min[1];
					face.min[1] = face.max[1];
					face.max[1] = swap;
				}
				quads.append(.{
					.normal = zAxis,
					.corners = .{
						xLower + yLower + zValue,
						xLower + yUpper + zValue,
						xUpper + yLower + zValue,
						xUpper + yUpper + zValue,
					},
					.cornerUV = .{.{face.min[0], face.min[1]}, .{face.min[0], face.max[1]}, .{face.max[0], face.min[1]}, .{face.max[0], face.max[1]}},
					.textureSlot = neighbor.toInt(),
				});
			}
			const middleFaces = mergeFaces(visibleMiddle, &faces);
			for(middleFaces) |*face| {
				var xLower = @abs(xAxis)*@as(Vec3f, @splat(face.min[0]));
				var xUpper = @abs(xAxis)*@as(Vec3f, @splat(face.max[0]));
				if(@reduce(.Add, xAxis) < 0) std.mem.swap(Vec3f, &xLower, &xUpper);
				var yLower = @abs(yAxis)*@as(Vec3f, @splat(face.min[1]));
				var yUpper = @abs(yAxis)*@as(Vec3f, @splat(face.max[1]));
				if(@reduce(.Add, yAxis) < 0) std.mem.swap(Vec3f, &yLower, &yUpper);
				const zValue = @as(Vec3f, @floatFromInt(zComponent))*@as(Vec3f, @splat(0.5));
				if(neighbor == .dirNegX or neighbor == .dirPosY) {
					face.min[0] = 1 - face.min[0];
					face.max[0] = 1 - face.max[0];
					const swap = face.min[0];
					face.min[0] = face.max[0];
					face.max[0] = swap;
				}
				if(neighbor == .dirUp) {
					face.min = Vec2f{1, 1} - face.min;
					face.max = Vec2f{1, 1} - face.max;
					std.mem.swap(Vec2f, &face.min, &face.max);
				}
				if(neighbor == .dirDown) {
					face.min[1] = 1 - face.min[1];
					face.max[1] = 1 - face.max[1];
					const swap = face.min[1];
					face.min[1] = face.max[1];
					face.max[1] = swap;
				}
				quads.append(.{
					.normal = zAxis,
					.corners = .{
						xLower + yLower + zValue,
						xLower + yUpper + zValue,
						xUpper + yLower + zValue,
						xUpper + yUpper + zValue,
					},
					.cornerUV = .{.{face.min[0], face.min[1]}, .{face.min[0], face.max[1]}, .{face.max[0], face.min[1]}, .{face.max[0], face.max[1]}},
					.textureSlot = neighbor.toInt(),
				});
			}
		}
		const index = main.models.Model.init(quads.items);
		if(i == 0) {
			modelIndex = index;
		}
	}
	return modelIndex.?;
}

pub fn model(block: Block) ModelIndex {
	return .{.index = blocks.meshes.modelIndexStart(block).index + (block.data & 255)};
}

pub fn generateData(_: *main.game.World, _: Vec3i, _: Vec3f, _: Vec3f, _: Vec3i, _: ?Neighbor, currentData: *Block, _: Block, blockPlacing: bool) bool {
	if(blockPlacing) {
		currentData.data = 0;
		return true;
	}
	return false;
}

fn intersectHalfUnitBox(start: Vec3f, invDir: Vec3f) ?f32 {
	const t0 = start*invDir;
	const t1 = (start + Vec3f{0.5, 0.5, 0.5})*invDir;
	const entry = @reduce(.Max, @min(t0, t1));
	const exit = @reduce(.Min, @max(t0, t1));
	if(entry > exit or exit < 0) {
		return null;
	} else return entry;
}

fn intersectionPos(block: Block, relativePlayerPos: Vec3f, playerDir: Vec3f) ?struct {minT: f32, minPos: @Vector(3, u1)} {
	const invDir = @as(Vec3f, @splat(1))/playerDir;
	const relPos: Vec3f = @floatCast(-relativePlayerPos);
	const data: u8 = @truncate(block.data);
	var minT: f32 = std.math.floatMax(f32);
	var minPos: @Vector(3, u1) = undefined;
	for(0..8) |i| {
		const subPos: @Vector(3, u1) = .{
			@truncate(i >> 2),
			@truncate(i >> 1),
			@truncate(i),
		};
		if(hasSubBlock(data, subPos[0], subPos[1], subPos[2])) {
			const relSubPos = relPos + @as(Vec3f, @floatFromInt(subPos))*@as(Vec3f, @splat(0.5));
			if(intersectHalfUnitBox(relSubPos, invDir)) |t| {
				if(t < minT) {
					minT = t;
					minPos = subPos;
				}
			}
		}
	}
	if(minT != std.math.floatMax(f32)) {
		return .{.minT = minT, .minPos = minPos};
	}
	return null;
}

pub fn rayIntersection(block: Block, item: ?main.items.Item, relativePlayerPos: Vec3f, playerDir: Vec3f) ?RayIntersectionResult {
	if(item) |_item| {
		switch(_item) {
			.baseItem => |baseItem| {
				if(std.mem.eql(u8, baseItem.id, "cubyz:chisel")) { // Select only one eigth of a block
					if(intersectionPos(block, relativePlayerPos, playerDir)) |intersection| {
						const offset: Vec3f = @floatFromInt(intersection.minPos);
						const half: Vec3f = @splat(0.5);
						return .{
							.distance = intersection.minT,
							.min = half*offset,
							.max = half + half*offset,
						};
					}
					return null;
				}
			},
			else => {},
		}
	}
	return RotationMode.DefaultFunctions.rayIntersection(block, item, relativePlayerPos, playerDir);
}

pub fn onBlockBreaking(item: ?main.items.Item, relativePlayerPos: Vec3f, playerDir: Vec3f, currentData: *Block) void {
	if(item) |_item| {
		switch(_item) {
			.baseItem => |baseItem| {
				if(std.mem.eql(u8, baseItem.id, "cubyz:chisel")) { // Break only one eigth of a block
					if(intersectionPos(currentData.*, relativePlayerPos, playerDir)) |intersection| {
						currentData.data = currentData.data | subBlockMask(intersection.minPos[0], intersection.minPos[1], intersection.minPos[2]);
						if(currentData.data == 255) currentData.* = .{.typ = 0, .data = 0};
						return;
					}
				}
			},
			else => {},
		}
	}
	return RotationMode.DefaultFunctions.onBlockBreaking(item, relativePlayerPos, playerDir, currentData);
}

pub fn canBeChangedInto(oldBlock: Block, newBlock: Block, item: main.items.ItemStack, shouldDropSourceBlockOnSuccess: *bool) RotationMode.CanBeChangedInto {
	if(oldBlock.typ != newBlock.typ) return RotationMode.DefaultFunctions.canBeChangedInto(oldBlock, newBlock, item, shouldDropSourceBlockOnSuccess);
	if(oldBlock.data == newBlock.data) return .no;
	if(item.item != null and item.item.? == .baseItem and std.mem.eql(u8, item.item.?.baseItem.id, "cubyz:chisel")) {
		return .yes; // TODO: Durability change, after making the chisel a proper tool.
	}
	return .no;
}
