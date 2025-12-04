const std = @import("std");

const blocks = @import("blocks.zig");
const Block = blocks.Block;
const chunk = @import("chunk.zig");
const Neighbor = chunk.Neighbor;
const main = @import("main");
const ModelIndex = main.models.ModelIndex;
const Tag = main.Tag;
const vec = main.vec;
const Vec3i = vec.Vec3i;
const Vec3f = vec.Vec3f;
const Mat4f = vec.Mat4f;
const ZonElement = main.ZonElement;

const list = @import("rotation");

pub const RayIntersectionResult = struct {
	distance: f32,
	min: Vec3f,
	max: Vec3f,
	normal: Vec3f,
};

pub const Degrees = enum(u2) {
	@"0" = 0,
	@"90" = 1,
	@"180" = 2,
	@"270" = 3,
};

// TODO: Why not just use a tagged union?
/// Each block gets 16 bit of additional storage(apart from the reference to the block type).
/// These 16 bits are accessed and interpreted by the `RotationMode`.
/// With the `RotationMode` interface there is almost no limit to what can be done with those 16 bit.
pub const RotationMode = struct { // MARK: RotationMode
	pub const DefaultFunctions = struct {
		pub fn model(block: Block) ModelIndex {
			return blocks.meshes.modelIndexStart(block);
		}
		pub fn rotateZ(data: u16, _: Degrees) u16 {
			return data;
		}
		pub fn generateData(_: *main.game.World, _: Vec3i, _: Vec3f, _: Vec3f, _: Vec3i, _: ?Neighbor, _: *Block, _: Block, blockPlacing: bool) bool {
			return blockPlacing;
		}
		pub fn createBlockModel(_: Block, _: *u16, zon: ZonElement) ModelIndex {
			return main.models.getModelIndex(zon.as([]const u8, "cubyz:cube"));
		}
		pub fn updateData(_: *Block, _: Neighbor, _: Block) bool {
			return false;
		}
		pub fn modifyBlock(_: *Block, _: u16) bool {
			return false;
		}
		pub fn rayIntersection(block: Block, _: main.items.Item, relativePlayerPos: Vec3f, playerDir: Vec3f) ?RayIntersectionResult {
			return rayModelIntersection(blocks.meshes.model(block), relativePlayerPos, playerDir);
		}
		pub fn rayModelIntersection(modelIndex: ModelIndex, relativePlayerPos: Vec3f, playerDir: Vec3f) ?RayIntersectionResult {
			const modelData = modelIndex.model();
			var minimum: ?f32 = null;
			var normal: ?Vec3f = null;
			var quadList: main.List(main.models.QuadInfo) = .init(main.stackAllocator);
			defer quadList.deinit();
			modelData.getRawFaces(&quadList);
			for(quadList.items) |quad| {
				const triangle1: [3]Vec3f = .{quad.cornerVec(0), quad.cornerVec(1), quad.cornerVec(2)};
				const triangle2: [3]Vec3f = .{quad.cornerVec(1), quad.cornerVec(2), quad.cornerVec(3)};
				if(rayTriangleIntersection(relativePlayerPos, playerDir, triangle1)) |distance| {
					if(minimum == null or distance < minimum.?) {
						minimum = distance;
						normal = quad.normalVec();
					}
				}
				if(rayTriangleIntersection(relativePlayerPos, playerDir, triangle2)) |distance| {
					if(minimum == null or distance < minimum.?) {
						minimum = distance;
						normal = quad.normalVec();
					}
				}
			}
			if(minimum != null) {
				// Invert the normal if the player is behind the face (eg. cross model)
				if(vec.dot(normal.?, relativePlayerPos) < 0.0) {
					normal = -normal.?;
				}
				return .{
					.distance = minimum.?,
					.min = modelData.min,
					.max = modelData.max,
					.normal = normal.?,
				};
			}
			return null;
		}
		pub fn onBlockBreaking(_: main.items.Item, _: Vec3f, _: Vec3f, currentData: *Block) void {
			currentData.* = .{.typ = 0, .data = 0};
		}
		pub fn canBeChangedInto(oldBlock: Block, newBlock: Block, item: main.items.ItemStack, shouldDropSourceBlockOnSuccess: *bool) CanBeChangedInto {
			shouldDropSourceBlockOnSuccess.* = true;
			if(oldBlock == newBlock) return .no;
			if(oldBlock.typ == newBlock.typ) return .yes;
			if(!oldBlock.replacable()) {
				var damage: f32 = main.game.Player.defaultBlockDamage;
				const isTool = item.item == .tool;
				if(isTool) {
					damage = item.item.tool.getBlockDamage(oldBlock);
				}
				damage -= oldBlock.blockResistance();
				if(damage > 0) {
					if(isTool and item.item.tool.isEffectiveOn(oldBlock)) {
						return .{.yes_costsDurability = 1};
					} else return .yes;
				}
			} else {
				if(item.item == .baseItem) {
					if(item.item.baseItem.block() != null and item.item.baseItem.block().? == newBlock.typ) {
						return .{.yes_costsItems = 1};
					}
				}
				if(newBlock.typ == 0) {
					return .yes;
				}
			}
			return .no;
		}
		pub fn getBlockTags() []const Tag {
			return &.{};
		}
	};

	pub const CanBeChangedInto = union(enum) {
		no: void,
		yes: void,
		yes_costsDurability: u16,
		yes_costsItems: u16,
		yes_dropsItems: u16,
	};

	/// if the block should be destroyed or changed when a certain neighbor is removed.
	dependsOnNeighbors: bool = false,

	/// The default rotation data intended for generation algorithms
	naturalStandard: u16 = 0,

	model: *const fn(block: Block) ModelIndex = &DefaultFunctions.model,

	// Rotates block data counterclockwise around the Z axis.
	rotateZ: *const fn(data: u16, angle: Degrees) u16 = DefaultFunctions.rotateZ,

	createBlockModel: *const fn(block: Block, modeData: *u16, zon: ZonElement) ModelIndex = &DefaultFunctions.createBlockModel,

	/// Updates the block data of a block in the world or places a block in the world.
	/// return true if the placing was successful, false otherwise.
	generateData: *const fn(world: *main.game.World, pos: Vec3i, relativePlayerPos: Vec3f, playerDir: Vec3f, relativeDir: Vec3i, neighbor: ?Neighbor, currentData: *Block, neighborBlock: Block, blockPlacing: bool) bool = DefaultFunctions.generateData,

	/// Updates data of a placed block if the RotationMode dependsOnNeighbors.
	updateData: *const fn(block: *Block, neighbor: Neighbor, neighborBlock: Block) bool = &DefaultFunctions.updateData,

	modifyBlock: *const fn(block: *Block, newType: u16) bool = DefaultFunctions.modifyBlock,

	rayIntersection: *const fn(block: Block, item: main.items.Item, relativePlayerPos: Vec3f, playerDir: Vec3f) ?RayIntersectionResult = &DefaultFunctions.rayIntersection,

	onBlockBreaking: *const fn(item: main.items.Item, relativePlayerPos: Vec3f, playerDir: Vec3f, currentData: *Block) void = &DefaultFunctions.onBlockBreaking,

	canBeChangedInto: *const fn(oldBlock: Block, newBlock: Block, item: main.items.ItemStack, shouldDropSourceBlockOnSuccess: *bool) CanBeChangedInto = DefaultFunctions.canBeChangedInto,

	getBlockTags: *const fn() []const Tag = DefaultFunctions.getBlockTags,
};

var rotationModes: std.StringHashMap(RotationMode) = undefined;

pub fn rotationMatrixTransform(quad: *main.models.QuadInfo, transformMatrix: Mat4f) void {
	quad.normal = vec.xyz(Mat4f.mulVec(transformMatrix, vec.combine(quad.normal, 0)));
	for(&quad.corners) |*corner| {
		corner.* = vec.xyz(Mat4f.mulVec(transformMatrix, vec.combine(corner.* - Vec3f{0.5, 0.5, 0.5}, 1))) + Vec3f{0.5, 0.5, 0.5};
	}
}

/// Modified from https://en.wikipedia.org/wiki/Möller–Trumbore_intersection_algorithm#Implementations
fn rayTriangleIntersection(origin: Vec3f, direction: Vec3f, triangle: [3]Vec3f) ?f32 {
	const e1 = triangle[1] - triangle[0];
	const e2 = triangle[2] - triangle[0];

	const rayCrossE2 = vec.cross(direction, e2);
	const det = vec.dot(e1, rayCrossE2);

	if(det > -std.math.floatEps(f32) and det < std.math.floatEps(f32)) {
		return null;
	}

	const invDet = 1.0/det;
	const s = origin - triangle[0];
	const u = invDet*vec.dot(s, rayCrossE2);
	if(u < 0.0 or u > 1.0) {
		return null;
	}

	const sCrossE1 = vec.cross(s, e1);
	const v = invDet*vec.dot(direction, sCrossE1);
	if(v < 0.0 or u + v > 1.0) {
		return null;
	}

	const t = invDet*vec.dot(e2, sCrossE1);

	if(t > std.math.floatEps(f32)) {
		return t;
	} else {
		return null;
	}
}

// MARK: init/register

pub fn init() void {
	rotationModes = .init(main.globalAllocator.allocator);
	inline for(@typeInfo(list).@"struct".decls) |declaration| {
		register(declaration.name, @field(list, declaration.name));
	}
}

pub fn reset() void {
	inline for(@typeInfo(list).@"struct".decls) |declaration| {
		@field(list, declaration.name).reset();
	}
}

pub fn deinit() void {
	rotationModes.deinit();
	inline for(@typeInfo(list).@"struct".decls) |declaration| {
		@field(list, declaration.name).deinit();
	}
}

pub fn getByID(id: []const u8) *const RotationMode {
	if(rotationModes.getPtr(id)) |mode| return mode;
	std.log.err("Could not find rotation mode {s}. Using cubyz:no_rotation instead.", .{id});
	return rotationModes.getPtr("cubyz:no_rotation").?;
}

pub fn register(comptime id: []const u8, comptime Mode: type) void {
	Mode.init();
	var result: RotationMode = RotationMode{};
	inline for(@typeInfo(RotationMode).@"struct".fields) |field| {
		if(@hasDecl(Mode, field.name)) {
			if(field.type == @TypeOf(@field(Mode, field.name))) {
				@field(result, field.name) = @field(Mode, field.name);
			} else {
				@field(result, field.name) = &@field(Mode, field.name);
			}
		}
	}
	rotationModes.putNoClobber(id, result) catch unreachable;
}
