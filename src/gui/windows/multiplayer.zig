const std = @import("std");

const main = @import("main");
const ConnectionManager = main.network.ConnectionManager;
const settings = main.settings;
const Vec2f = main.vec.Vec2f;
const ZonElement = @import("../../zon.zig").ZonElement;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const HorizontalList = @import("../components/HorizontalList.zig");
const Selectable = @import("../components/Selectable.zig");
const Label = @import("../components/Label.zig");
const TextInput = @import("../components/TextInput.zig");
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

const Tabs = enum(u8) {
	WORLD,
	LOCAL
};

const serverListPath = "server_list.zig.zon";
const width: f32 = 490;
const padding: f32 = 8;

var servers: main.List(ServerInfo) = .init(main.globalAllocator);
var serverList: *VerticalList = undefined;
var selectedServerIdx: ?u32 = null;

var connection: ?*ConnectionManager = null;
var ipAddress: []const u8 = "";
var ipAddressLabel: *Label = undefined;
var ipAddressEntry: *TextInput = undefined;
var gotIpAddress: std.atomic.Value(bool) = .init(false);
var thread: ?std.Thread = null;

var joinButton: *Button = undefined;
var removeButton: *Button = undefined;
var selectedTab: Tabs = .WORLD;
var refresh: bool = false;

fn initConnection() void {
	connection = ConnectionManager.init(main.settings.defaultPort, true) catch |err| {
		std.log.err("Could not open Connection: {s}", .{@errorName(err)});
		ipAddress = main.globalAllocator.dupe(u8, @errorName(err));
		return;
	};
}

fn discoverIpAddress() void {
	initConnection();
	ipAddress = std.fmt.allocPrint(main.globalAllocator.allocator, "{f}", .{connection.?.externalAddress}) catch unreachable;
	gotIpAddress.store(true, .release);
}

fn discoverIpAddressFromNewThread() void {
	std.log.debug("thread started", .{});

	main.initThreadLocals();
	defer main.deinitThreadLocals();

	discoverIpAddress();
}

fn joinWorld(_: usize) void {
	const server = &servers.items[selectedServerIdx.?];
	joinServer(server.address);
}

fn joinLocal(_: usize) void {
	const address = ipAddressEntry.currentString.items;
	joinServer(address);

	main.globalAllocator.free(settings.lastUsedIPAddress);
	settings.lastUsedIPAddress = main.globalAllocator.dupe(u8, address);
	settings.save();
}

fn copyIp(_: usize) void {
	main.Window.setClipboardString(ipAddress);
}

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
		servers.append(.{
			.name = main.globalAllocator.dupe(u8, name.?.stringOwned),
			.address = main.globalAllocator.dupe(u8, address.?.stringOwned)
		});
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

fn initWorldTab(root: *VerticalList) void {
	if(!refresh) {
		loadServerList();
	}

	if(servers.items.len == 0) {
		root.add(Label.init(.{0, 0}, width/3*2, "#d0d0d0The list is empty :(\n\nAdd a new #ffffff__server__ #d0d0d0by clicking the *button* below!", .center));
	}
	serverList = VerticalList.init(.{0, 0}, root.maxHeight/2, 0);
	for(servers.items, 0..) |*server, i| {
		serverList.add(initServerElement(server, i));
	}
	serverList.finish(.left);
	selectedServerIdx = null;

	const bottomPanel = HorizontalList.init();
	const buttonWidth = (width - padding*3)/4;
	bottomPanel.add(Button.initText(.{0, 0}, buttonWidth, "Add server", gui.openWindowCallback("add_server")));
	bottomPanel.add(Button.initText(.{padding, 0}, buttonWidth, "Join Directly", gui.openWindowCallback("join_directly")));
	joinButton = Button.initText(.{padding, 0}, buttonWidth, "Join", .{.callback = &joinWorld});
	joinButton.disabled = true;
	bottomPanel.add(joinButton);
	removeButton = Button.initText(.{padding, 0}, buttonWidth, "Remove", .{.callback = &removeServer});
	removeButton.disabled = true;
	bottomPanel.add(removeButton);
	bottomPanel.finish(.{0, 0}, .center);

	root.add(serverList);
	root.add(bottomPanel);
}

fn initLocalTab(root: *VerticalList) void {
	root.add(Label.init(.{0, 0}, width, "Please send your IP to the host of the game and enter the host's IP below.", .center));
	//                                               255.255.255.255:?65536 (longest possible ip address)

	const ipBar = HorizontalList.init();
	const ipText = if(refresh and ipAddress.len != 0) ipAddress else "                      ";
	ipAddressLabel = Label.init(.{padding/3, 0}, width/2.5 - padding/3, ipText, .left);
	ipBar.add(ipAddressLabel);
	ipBar.add(Button.initText(.{padding, 0}, 100, "Copy IP", .{.callback = &copyIp}));
	ipBar.finish(.{0, 0}, .center);

	const inputBar = HorizontalList.init();
	ipAddressEntry = TextInput.init(.{0, 0}, width/2.5, 24, settings.lastUsedIPAddress, .{.callback = &joinLocal}, .{});
	inputBar.add(ipAddressEntry);
	inputBar.add(Button.initText(.{padding, 0}, 100, "Join", .{.callback = &joinLocal}));
	inputBar.finish(.{0, 0}, .center);

	root.add(ipBar);
	root.add(inputBar);

	if(thread == null) {
		thread = std.Thread.spawn(.{}, discoverIpAddressFromNewThread, .{}) catch |err| blk: {
			std.log.err("Error spawning thread: {s}. Doing it in the current thread instead.", .{@errorName(err)});
			discoverIpAddress();
			break :blk null;
		};
	}
}

fn refreshWindow() void {
	refresh = true;
	gui.closeWindowFromRef(&window);
	gui.openWindowFromRef(&window);
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

fn switchTab(tab: usize) void {
	selectedTab = @enumFromInt(tab);
	refreshWindow();
}

pub fn addServer(name: []const u8, address: []const u8) void {
	const server = servers.addOne();
	server.* = .{
		.name = main.globalAllocator.dupe(u8, name),
		.address = main.globalAllocator.dupe(u8, address)
	};
	saveServerList();
	refreshWindow();
}

pub fn joinServer(address: []const u8) void {
	if(thread) |_thread| {
		_thread.join();
		thread = null;
	} else if(connection == null) {
		initConnection();
	}

	if(ipAddress.len != 0) {
		main.globalAllocator.free(ipAddress);
		ipAddress = "";
	}
	if(connection) |_connection| {
		_connection.world = &main.game.testWorld;
		main.game.world = &main.game.testWorld;
		std.log.info("Connecting to server: {s}", .{address});
		main.game.testWorld.init(address, _connection) catch |err| {
			const formattedError = std.fmt.allocPrint(main.stackAllocator.allocator, "Encountered error while opening world: {s}", .{@errorName(err)}) catch unreachable;
			defer main.stackAllocator.free(formattedError);
			std.log.err("{s}", .{formattedError});
			main.gui.windowlist.notification.raiseNotification(formattedError);
			main.game.world = null;
			_connection.world = null;
			return;
		};
		connection = null;
	} else {
		std.log.err("No connection found. Cannot connect.", .{});
		main.gui.windowlist.notification.raiseNotification("No connection found. Cannot connect.");
	}

	for(gui.openWindows.items) |openWindow| {
		gui.closeWindowFromRef(openWindow);
	}
	gui.openHud();
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	//list.add(Label.init(.{0, 0}, 100, "**Multiplayer**", .center));

	const tabs = HorizontalList.init();
	const worldButton = Button.initText(.{0, 0}, width/2 + 4, "World", .{.callback = &switchTab, .arg = @intFromEnum(Tabs.WORLD)});
	const localButton = Button.initText(.{-4, 0}, width/2 + 4, "Local", .{.callback = &switchTab, .arg = @intFromEnum(Tabs.LOCAL)});
	worldButton.disabled = selectedTab == .WORLD;
	localButton.disabled = selectedTab == .LOCAL;
	tabs.add(worldButton);
	tabs.add(localButton);
	tabs.finish(.{0, 0}, .center);
	list.add(tabs);

	switch(selectedTab) {
		.WORLD => initWorldTab(list),
		.LOCAL => initLocalTab(list)
	}

	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();

	refresh = false;
}

pub fn onClose() void {
	if(!refresh) {
		if(thread) |_thread| {
			_thread.join();
			thread = null;
		}
		if(ipAddress.len != 0) {
			main.globalAllocator.free(ipAddress);
			ipAddress = "";
		}
		if(connection) |_connection| {
			_connection.deinit();
			connection = null;
		}
		if(servers.items.len != 0) {
			for(0..servers.items.len) |i| servers.items[i].deinit();
			servers.clearAndFree();
		}
	}

	if(window.rootComponent) |*comp| {
		comp.deinit();
	}
}

pub fn update() void {
	switch (selectedTab) {
		.LOCAL => {
			if(gotIpAddress.load(.acquire)) {
				gotIpAddress.store(false, .monotonic);
				ipAddressLabel.updateText(ipAddress);
			}
		},
		.WORLD => {
			joinButton.disabled = selectedServerIdx == null;
			removeButton.disabled = joinButton.disabled;
		}
	}
}
