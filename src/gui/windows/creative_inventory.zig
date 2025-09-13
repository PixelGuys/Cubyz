const std = @import("std");

const main = @import("main");
const Item = main.items.Item;
const Inventory = main.items.Inventory;
const Player = main.game.Player;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const TextInput = GuiComponent.TextInput;
const Label = GuiComponent.Label;
const HorizontalList = GuiComponent.HorizontalList;
const VerticalList = GuiComponent.VerticalList;
const ItemSlot = GuiComponent.ItemSlot;

pub var window = GuiWindow{
	.relativePosition = .{
		.{.attachedToFrame = .{.selfAttachmentPoint = .lower, .otherAttachmentPoint = .lower}},
		.{.attachedToFrame = .{.selfAttachmentPoint = .middle, .otherAttachmentPoint = .middle}},
	},
	.contentSize = Vec2f{64*8, 64*6},
	.scale = 0.75,
};

const padding: f32 = 8;
const slotsPerRow: u32 = 10;
var items: main.List(Item) = undefined;
var inventory: Inventory = undefined;
var searchInput: *TextInput = undefined;
var searchString: []const u8 = undefined;

fn lessThan(_: void, lhs: Item, rhs: Item) bool {
	if(lhs == .baseItem and rhs == .baseItem) {
		const lhsFolders = std.mem.count(u8, lhs.baseItem.id(), "/");
		const rhsFolders = std.mem.count(u8, rhs.baseItem.id(), "/");
		if(lhsFolders < rhsFolders) return true;
		if(lhsFolders > rhsFolders) return false;
		return std.ascii.lessThanIgnoreCase(lhs.baseItem.id(), rhs.baseItem.id());
	} else {
		if(lhs == .baseItem) return true;
		return false;
	}
}

pub fn onOpen() void {
	searchString = "";
	initContent();
}

pub fn onClose() void {
	deinitContent();
	main.globalAllocator.free(searchString);
}

fn hasMatchingTag(tags: []const main.Tag, target: []const u8) bool {
	for(tags) |tag| {
		if(std.mem.containsAtLeast(u8, tag.getName(), 1, target)) {
			return true;
		}
	}
	return false;
}

fn initContent() void {
	const root = VerticalList.init(.{padding, padding}, 300, 0);
	{
		const list = VerticalList.init(.{0, padding + padding}, 48, 0);
		const row = HorizontalList.init();
		const label = Label.init(.{0, 3}, 56, "Search:", .right);

		searchInput = TextInput.init(.{0, 0}, 288, 22, searchString, .{.callback = &filter}, .{});

		row.add(label);
		row.add(searchInput);
		list.add(row);
		list.finish(.center);
		root.add(list);
	}
	{
		const list = VerticalList.init(.{0, padding}, 144, 0);
		items = .init(main.globalAllocator);
		var itemIterator = main.items.iterator();
		if(searchString.len > 1 and searchString[0] == '.') {
			const tag = searchString[1..];
			while(itemIterator.next()) |item| {
				if(hasMatchingTag(item.tags(), tag) or (item.block() != null and hasMatchingTag((main.blocks.Block{.typ = item.block().?, .data = undefined}).blockTags(), tag))) {
					items.append(Item{.baseItem = item.*});
				}
			}
		} else {
			while(itemIterator.next()) |item| {
				if(searchString.len != 0 and !std.mem.containsAtLeast(u8, item.id(), 1, searchString)) continue;
				items.append(Item{.baseItem = item.*});
			}
		}

		std.mem.sort(Item, items.items, {}, lessThan);
		const slotCount = items.items.len + (slotsPerRow - items.items.len%slotsPerRow);
		inventory = Inventory.init(main.globalAllocator, slotCount, .creative, .other, .{});
		for(0..items.items.len) |i| {
			inventory.fillAmountFromCreative(@intCast(i), items.items[i], 1);
		}
		var i: u32 = 0;
		while(i < items.items.len) {
			const row = HorizontalList.init();
			for(0..slotsPerRow) |_| {
				if(i >= items.items.len) {
					row.add(ItemSlot.init(.{0, 0}, inventory, i, .immutable, .immutable));
				} else {
					row.add(ItemSlot.init(.{0, 0}, inventory, i, .default, .takeOnly));
				}
				i += 1;
			}
			list.add(row);
		}
		list.finish(.center);
		root.add(list);
	}
	root.finish(.center);
	window.rootComponent = root.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

fn deinitContent() void {
	if(window.rootComponent) |*comp| {
		comp.deinit();
	}
	items.deinit();
	inventory.deinit(main.globalAllocator);
}

pub fn update() void {
	if(std.mem.eql(u8, searchInput.currentString.items, searchString)) return;
	filter(undefined);
}

fn filter(_: usize) void {
	const selectionStart = searchInput.selectionStart;
	const cursor = searchInput.cursor;

	main.globalAllocator.free(searchString);
	searchString = main.globalAllocator.dupe(u8, searchInput.currentString.items);
	deinitContent();
	initContent();

	searchInput.selectionStart = selectionStart;
	searchInput.cursor = cursor;

	searchInput.select();
}
