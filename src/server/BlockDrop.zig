const main = @import("main");
const Tag = main.Tag;
const items = main.items;
const Item = items.Item;
const vec = main.vec;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;
const blocks = main.blocks;
const Block = blocks.Block;

itemStacks: []const items.ItemStack,
chance: f32,
forbiddenToolTags: []Tag,
allowedToolTags: ?[]Tag = null,

pub fn isDroppedWhenBrokenWithItem(self: @This(), item: Item) bool {
	if (item != .proceduralItem) return self.allowedToolTags == null;

	const proceduralItem = item.proceduralItem;
	for (self.forbiddenToolTags) |tag| if (proceduralItem.hasTag(tag)) return false;
	if (self.allowedToolTags) |tags| {
		for (tags) |tag| if (proceduralItem.hasTag(tag)) return true;
		return false;
	}

	return true;
}

pub fn drop(self: @This(), pos: Vec3d, dir: Vec3f, velocity: f32) void {
	if (self.chance == 1 or main.random.nextFloat(&main.seed) < self.chance) {
		for (self.itemStacks) |itemStack| {
			main.server.world.?.drop(itemStack.clone(), pos, dir, velocity);
		}
	}
}

pub const Location = struct {
	normalDir: Vec3f,
	min: Vec3f,
	max: Vec3f,

	const half = @as(Vec3f, @splat(0.5));
	const itemHitBoxMargin: f32 = @floatCast(main.itemdrop.ItemDropManager.radius);
	const itemHitBoxMarginVec: Vec3f = @splat(itemHitBoxMargin);

	fn insidePos(self: Location, _pos: Vec3i) Vec3d {
		const pos: Vec3d = @floatFromInt(_pos);
		return pos + self.randomOffset();
	}
	fn randomOffset(self: Location) Vec3f {
		const max = @min(@as(Vec3f, @splat(1.0)) - itemHitBoxMarginVec, @max(itemHitBoxMarginVec, self.max - itemHitBoxMarginVec));
		const min = @min(max, @max(itemHitBoxMarginVec, self.min + itemHitBoxMarginVec));
		const center = (max + min)*half;
		const width = (max - min)*half;
		return center + width*main.random.nextFloatVectorSigned(3, &main.seed)*half;
	}
	fn outsidePos(self: Location, _pos: Vec3i) Vec3d {
		const pos: Vec3d = @floatFromInt(_pos);
		const random = self.randomOffset();
		const minorVectors = minors(self);
		const minor1Offset = @as(Vec3f, @splat(vec.dot(random, minorVectors[0])))*minorVectors[0];
		const minor2Offset = @as(Vec3f, @splat(vec.dot(random, minorVectors[1])))*minorVectors[1];
		return pos + minor1Offset + minor2Offset + self.directionOffset()*self.major() + self.direction()*itemHitBoxMarginVec;
	}
	fn directionOffset(self: Location) Vec3d {
		return half + self.direction()*half;
	}
	inline fn direction(self: Location) Vec3f {
		return self.normalDir;
	}
	inline fn major(self: Location) Vec3f {
		return @abs(self.normalDir);
	}
	inline fn minors(self: Location) struct { Vec3f, Vec3f } {
		const minor1 = vec.normalize(vec.cross(self.normalDir, if (@reduce(.And, @abs(self.normalDir) == Vec3f{1.0, 0.0, 0.0})) Vec3f{0.0, 1.0, 0.0} else Vec3f{1.0, 0.0, 0.0}));
		const minor2 = vec.normalize(vec.cross(self.normalDir, minor1));
		return .{minor1, minor2};
	}
	fn dropDir(self: Location) Vec3f {
		const randomnessVec: Vec3f = main.random.nextFloatVectorSigned(3, &main.seed)*@as(Vec3f, @splat(0.25));
		const directionVec: Vec3f = @as(Vec3f, @floatCast(self.direction())) + randomnessVec;
		const z: f32 = directionVec[2];
		return vec.normalize(Vec3f{
			directionVec[0],
			directionVec[1],
			if (z < -0.5) 0 else if (z < 0.0) (z + 0.5)*4.0 else z + 2.0,
		});
	}
	fn dropVelocity(self: Location) f32 {
		const velocity = 3.5 + main.random.nextFloatSigned(&main.seed)*0.5;
		if (self.direction()[2] < -0.5) return velocity*0.333;
		return velocity;
	}
};

pub const Context = struct {
	oldBlock: Block,
	newBlock: Block,
	item: Item = .null,

	pub fn drop(self: Context, location: Location, pos: Vec3i) void {
		const dropAmount = self.oldBlock.mode().itemDropsOnChange(self.oldBlock, self.newBlock);
		if (dropAmount == 0) return;

		const dropPos = if (self.newBlock.collide()) location.outsidePos(pos) else location.insidePos(pos);
		const dropDir = location.dropDir();
		const dropVelocity = location.dropVelocity();

		for (0..dropAmount) |_| {
			for (self.oldBlock.blockDrops()) |blockDrop| {
				if (blockDrop.isDroppedWhenBrokenWithItem(self.item)) {
					blockDrop.drop(dropPos, dropDir, dropVelocity);
				}
			}
		}
	}
};
