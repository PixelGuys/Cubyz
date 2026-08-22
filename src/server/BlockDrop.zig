const main = @import("main");
const Tag = main.Tag;
const items = main.items;
const Item = items.Item;
const blocks = main.blocks;
const Block = blocks.Block;
const vec = main.vec;
const Vec3i = vec.Vec3i;
const Vec3f = vec.Vec3f;
const ModelIndex = main.models.ModelIndex;

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

pub fn tryDropNaturally(self: @This(), modelIndex: ModelIndex, worldPos: Vec3i) void {
	if (!self.isDroppedWhenBrokenWithItem(.null)) return;

	if (self.chance == 1 or main.random.nextFloat(&main.seed) < self.chance) {
		const model = modelIndex.model();
		for (self.itemStacks) |stack| {
			var dir = main.vec.normalize(main.random.nextFloatVectorSigned(3, &main.seed));
			// Bias upwards
			dir[2] += main.random.nextFloat(&main.seed)*4.0;
			const pos = Vec3f{
				@as(f32, @floatFromInt(worldPos[0])) + model.min[0] + main.random.nextFloat(&main.seed)*(model.max[0] - model.min[0]),
				@as(f32, @floatFromInt(worldPos[1])) + model.min[1] + main.random.nextFloat(&main.seed)*(model.max[1] - model.min[1]),
				@as(f32, @floatFromInt(worldPos[2])) + model.min[2] + main.random.nextFloat(&main.seed)*(model.max[2] - model.min[2]),
			};
			main.server.world.?.drop(stack.clone(), pos, dir, 1);
		}
	}
}
