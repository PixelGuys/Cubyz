const main = @import("main");
const Tag = main.Tag;
const items = main.items;
const Item = items.Item;
const vec = main.vec;
const Vec3d = vec.Vec3d;
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

pub fn dropFromPosition(self: @This(), item: Item, pos: Vec3d, dir: Vec3f, velocity: f32) void {
	if (!self.isDroppedWhenBrokenWithItem(item)) return;

	if (self.chance == 1 or main.random.nextFloat(&main.seed) < self.chance) {
		for (self.items) |itemStack| {
			main.server.world.?.drop(itemStack.clone(), pos, dir, velocity);
		}
	}
}
