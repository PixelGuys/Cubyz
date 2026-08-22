const main = @import("main");
const Tag = main.Tag;
const items = main.items;
const Item = items.Item;

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
