const std = @import("std");

const main = @import("main");
const Vec2f = main.vec.Vec2f;
const ZonElement = @import("../../zon.zig").ZonElement;

const gui = @import("../gui.zig");
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const HorizontalList = @import("../components/HorizontalList.zig");
const Selectable = @import("../components/Selectable.zig");
const Label = @import("../components/Label.zig");
const VerticalList = @import("../components/VerticalList.zig");

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 256},
};

const ServerInfo = struct {
	name: []const u8 = &.{},
	address: []const u8 = &.{},

	pub fn deinit(self: *ServerInfo) void {
		main.globalAllocator.free(self.name);
		main.globalAllocator.free(self.address);
	}
};

const serverListPath = "server_list.zig.zon";
const width: f32 = 490;
const padding: f32 = 8;

var servers: main.List(ServerInfo) = .init(main.globalAllocator);
var serverList: *VerticalList = undefined;
var selectedServerIdx: ?u32 = null;
var joinButton: *Button = undefined;
var removeButton: *Button = undefined;
var refresh: bool = false;

fn loadServerList() void {
	servers.clearRetainingCapacity();
	const zon: ZonElement = main.files.cubyzDir().readToZon(main.stackAllocator, serverListPath) catch |err| blk: {
		if(err != error.FileNotFound) {
			std.log.err("Could not read server list file: {s}", .{@errorName(err)});
		}
		break :blk .null;
	};
	defer zon.deinit(main.stackAllocator);

	if(zon == .null) return;
	if(zon != .array) {
		std.log.err("Invalid format of server list file: {s}", .{@tagName(zon)});
	}

	const items = zon.array.items;
	for(items, 0..) |*item, i| {
		if(item.* != .object) {
			std.log.err("Invalid entry type in server list file: {s}:{}", .{@tagName(item.*), i});
		}

		const name = item.object.get("name");
		const address = item.object.get("address");
		if(name == null or address == null) {
			std.log.err("Invalid entry in server list file: {}", .{i});
			continue;
		}
		servers.append(.{.name = main.globalAllocator.dupe(u8, name.?.stringOwned), .address = main.globalAllocator.dupe(u8, address.?.stringOwned)});
	}
}

fn saveServerList() void {
	const zon = ZonElement.initArray(main.stackAllocator);
	defer zon.deinit(main.stackAllocator);

	for(servers.items) |*item| {
		const serverObject = ZonElement.initObject(main.stackAllocator);
		serverObject.put("name", item.name);
		serverObject.put("address", item.address);
		zon.append(serverObject);
	}

	main.files.cubyzDir().writeZon(serverListPath, zon) catch |err| {
		std.log.err("Couldn't write server list to file: {s}", .{@errorName(err)});
	};
}

fn initServerElement(server: *const ServerInfo, idx: usize) *Selectable {
	const nameWidth = width/5*2 - padding;
	const addressWidth = width/5*3 - padding;
	const element = HorizontalList.init();
	const panel = Selectable.init(.{0, 0}, .{0, 16 + padding*1.5}, .{.callback = &selectServer, .arg = idx});

	element.add(Label.init(.{padding, 0}, nameWidth, server.name, .left));
	element.add(Label.init(.{padding, 0}, addressWidth, server.address, .left));
	element.finish(.{0, 0}, .center);
	panel.setChild(element);
	panel.finish(.center);

	return panel;
}

fn refreshWindow() void {
	refresh = true;
	gui.closeWindowFromRef(&window);
	gui.openWindowFromRef(&window);
}

fn join(_: usize) void {
	const serverAddress = servers.items[selectedServerIdx.?].address;
	_ = main.game.join(serverAddress, null);
}

fn selectServer(serverIdx: usize) void {
	if(selectedServerIdx) |idx| {
		serverList.children.items[idx].selectable.deselect();
	}
	selectedServerIdx = @truncate(serverIdx);
}

fn removeServer(_: usize) void {
	var server = servers.orderedRemove(selectedServerIdx.?);
	server.deinit();
	saveServerList();
	refreshWindow();
}

pub fn addServer(name: []const u8, address: []const u8) void {
	const server = servers.addOne();
	server.* = .{.name = main.globalAllocator.dupe(u8, name), .address = main.globalAllocator.dupe(u8, address)};
	saveServerList();
	refreshWindow();
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	list.add(Label.init(.{0, 0}, width/3, "**Multiplayer**", .center));

	if(!refresh) {
		loadServerList();
	}
	if(servers.items.len == 0) {
		list.add(Label.init(.{0, 0}, width/3*2, "#d0d0d0The list is empty :(\n\nAdd a new #ffffff__server__ #d0d0d0by clicking the *button* below!", .center));
	}
	serverList = VerticalList.init(.{0, 0}, list.maxHeight/2, 0);
	for(servers.items, 0..) |*server, i| {
		serverList.add(initServerElement(server, i));
	}
	serverList.finish(.left);
	selectedServerIdx = null;

	const bottomPanel = HorizontalList.init();
	const buttonWidth = (width - padding*3)/4;
	bottomPanel.add(Button.initText(.{0, 0}, buttonWidth, "Add a Server", gui.openWindowCallback("add_server")));
	bottomPanel.add(Button.initText(.{padding, 0}, buttonWidth, "Join Directly", gui.openWindowCallback("join_directly")));
	joinButton = Button.initText(.{padding, 0}, buttonWidth, "Join", .{.callback = &join});
	joinButton.disabled = true;
	bottomPanel.add(joinButton);
	removeButton = Button.initText(.{padding, 0}, buttonWidth, "Remove", .{.callback = &removeServer});
	removeButton.disabled = true;
	bottomPanel.add(removeButton);
	bottomPanel.finish(.{0, 0}, .center);

	list.add(serverList);
	list.add(bottomPanel);

	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();

	refresh = false;
}

pub fn onClose() void {
	if(!refresh) {
		if(servers.items.len != 0) {
			for(0..servers.items.len) |i| servers.items[i].deinit();
			servers.clearAndFree();
		}

		gui.closeWindow("join_directly");
		gui.closeWindow("add_server");
	}

	if(window.rootComponent) |*comp| {
		comp.deinit();
	}
}

pub fn update() void {
	joinButton.disabled = selectedServerIdx == null;
	removeButton.disabled = joinButton.disabled;
}
