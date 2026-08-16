const main = @import("main");
const Tag = main.Tag;
const items = main.items;
const Item = items.Item;
const blocks = main.blocks;
const Block = blocks.Block;
const vec = main.vec;
const Vec3f = vec.Vec3f;

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

pub fn dropRandomly(self: @This(), block: Block, wx: i32, wy: i32, wz: i32) void {
	if (!self.isDroppedWhenBrokenWithItem(.null)) return;
	if (self.chance == 1 or main.random.nextFloat(&main.seed) < self.chance) {
		for (self.items) |stack| {
			var dir = main.vec.normalize(main.random.nextFloatVectorSigned(3, &main.seed));
			// Bias upwards
			dir[2] += main.random.nextFloat(&main.seed)*4.0;
			const model = block.mode().model(block).model();
			const pos = Vec3f{
				@as(f32, @floatFromInt(wx)) + model.min[0] + main.random.nextFloat(&main.seed)*(model.max[0] - model.min[0]),
				@as(f32, @floatFromInt(wy)) + model.min[1] + main.random.nextFloat(&main.seed)*(model.max[1] - model.min[1]),
				@as(f32, @floatFromInt(wz)) + model.min[2] + main.random.nextFloat(&main.seed)*(model.max[2] - model.min[2]),
			};
			main.server.world.?.drop(stack.clone(), pos, dir, 1);
		}
	}
}
