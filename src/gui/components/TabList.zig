const std = @import("std");

const main = @import("main");
const graphics = main.graphics;
const draw = graphics.draw;
const TextBuffer = graphics.TextBuffer;
const vec = main.vec;
const Vec2f = vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const ScrollBar = GuiComponent.ScrollBar;

const TabList = @This();

pos: Vec2f,
size: Vec2f,
tabs: main.List(GuiComponent),
tabNames: main.List([]const u8),
currentTab: usize,

pub fn init(pos: Vec2f) *TabList {
	const self = main.globalAllocator.create(TabList);
	self.* = TabList{
		.tabs = .init(main.globalAllocator),
		.tabNames = .init(main.globalAllocator),
		.pos = pos,
		.size = .{0, 0},
		.currentTab = 0,
	};
	return self;
}

pub fn deinit(self: *const TabList) void {
	for (self.tabs.items) |*tab| {
		tab.deinit();
	}
	self.tabs.deinit();
	self.tabNames.deinit();
	main.globalAllocator.destroy(self);
}

pub fn toComponent(self: *TabList) GuiComponent {
	return .{.tabList = self};
}

pub fn add(self: *TabList, title: []const u8, _other: anytype) void {
	var other: GuiComponent = undefined;
	if (@TypeOf(_other) == GuiComponent) {
		other = _other;
	} else {
		other = _other.toComponent();
	}
	self.tabs.append(other);
	self.tabNames.append(title);
	if (self.tabs.items.len == 1) self.setValues();
}

pub fn finish(self: *TabList) void {
	for (self.tabs.items) |*tab| {
		if (tab.size()[1] > self.size[1]) self.size[1] = tab.size()[1];
	}
}

pub fn getCurrentGuiComponent(self: *TabList) *GuiComponent {
	return &self.tabs.items[self.currentTab];
}

pub fn getTitle(self: *TabList) []const u8 {
	return self.tabNames.items[self.currentTab];
}

pub fn setValues(self: *TabList) void {
	self.size = self.getCurrentGuiComponent().size();
}

pub fn nextTab(self: *TabList) void {
	self.currentTab = (self.currentTab + 1)%self.tabs.items.len;
	self.setValues();
}

pub fn previousTab(self: *TabList) void {
	if (self.currentTab == 0) self.currentTab = self.tabs.items.len;
	self.currentTab = (self.currentTab - 1)%self.tabs.items.len;
	self.setValues();
}

pub fn updateSelected(self: *TabList) void {
	self.getCurrentGuiComponent().updateSelected();
}

pub fn updateHovered(self: *TabList, mousePosition: Vec2f) main.callbacks.Result {
	return self.getCurrentGuiComponent().updateHovered(mousePosition - self.pos);
}

pub fn render(self: *TabList, mousePosition: Vec2f) void {
	const oldTranslation = draw.setTranslation(self.pos);
	defer draw.restoreTranslation(oldTranslation);
	const oldClip = draw.setClip(self.size);
	defer draw.restoreClip(oldClip);
	self.getCurrentGuiComponent().render(mousePosition - self.pos);
}

pub fn mainButtonPressed(self: *TabList, mousePosition: Vec2f) main.callbacks.Result {
	return self.getCurrentGuiComponent().mainButtonPressed(mousePosition - self.pos);
}

pub fn mainButtonReleased(self: *TabList, mousePosition: Vec2f) void {
	self.getCurrentGuiComponent().mainButtonReleased(mousePosition - self.pos);
}
