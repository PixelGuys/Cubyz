const std = @import("std");

const build_options = @import("build_options");

const main = @import("../../main.zig");
const ConnnectionManager = main.network.ConnectionManager;
const Vec2f = main.vec.Vec2f;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ZonElement = main.ZonElement;
const Gamemode = main.game.Gamemode;

const gui = @import("../gui.zig");
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const HorizontalList = @import("../components/HorizontalList.zig");
const Label = @import("../components/Label.zig");
const TextInput = @import("../components/TextInput.zig");
const CheckBox = @import("../components/CheckBox.zig");
const VerticalList = @import("../components/VerticalList.zig");
const DiscreteSlider = @import("../components/DiscreteSlider.zig");

const WorldConfig = struct {
    worldName: []const u8,
    seed: i128,
    tickSpeed: std.atomic.Value(u32),
    defaultGamemode: Gamemode,
    allowCheats: bool,
    doGameTimeCycle: bool,
    testingMode: bool,

    isUpdated: bool = false,

    pub fn init(worldName: []const u8, seed: i128, defaultGamemode: Gamemode, allowCheats: bool, doGameTimeCycle: bool, testingMode: bool) @This() {
        return .{
            .worldName = worldName,
            .seed = seed,
            .tickSpeed = .init(12),
            .defaultGamemode = defaultGamemode,
            .allowCheats = allowCheats,
            .doGameTimeCycle = doGameTimeCycle,
            .testingMode = testingMode,
        };
    }

    pub fn getGameMode(gameMode: ?[]const u8) Gamemode {
        const mode = gameMode orelse @tagName(defaultSettings.defaultGamemode);
        return std.meta.stringToEnum(Gamemode, mode).?;
    }

    pub fn update(self: *@This(), state: bool) void {
        self.isUpdated = state;
        saveConfig.disabled = !state;
    }

    pub fn save(self: @This()) void {
        const worldInfoPath = main.stackAllocator.print("saves/{s}/world.zig.zon", .{editWorldName});
        const worldInfo = main.files.cubyzDir().readToZon(main.stackAllocator, worldInfoPath) catch {
            return;
        };
        const worldSettings = worldInfo.getChild("settings");
        //worldSettings.put("tickSpeed", self.tickSpeed);
        worldSettings.put("defaultGamemode", @tagName(self.defaultGamemode));
        worldSettings.put("allowCheats", self.allowCheats);
        if (!build_options.isTaggedRelease) worldSettings.put("testingMode", self.testingMode);

        worldInfo.put("settings", worldSettings);
        worldInfo.put("doGameTimeCycle", self.doGameTimeCycle);

        main.files.cubyzDir().writeZon(worldInfoPath, worldInfo) catch return;
    }
};

pub var window = GuiWindow{
    .contentSize = Vec2f{ 128, 256 },
};

const padding: f32 = 8;

var editWorldName: []const u8 = undefined;

var defaultSettings = main.server.world_zig.Settings.defaults;

var gamemodeInput: *Button = undefined;
var worldNameLabel: *Label = undefined;
var saveConfig: *Button = undefined;

var worldConfig: WorldConfig = undefined;

const tickSpeeds = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20 };

fn pass() void {}
fn pass3(index: u16) void {
    _ = index;
}

fn gamemodeCallback() void {
    worldConfig.defaultGamemode = std.enums.fromInt(Gamemode, @intFromEnum(worldConfig.defaultGamemode) + 1) orelse @enumFromInt(0);
    gamemodeInput.child.label.updateText(@tagName(worldConfig.defaultGamemode));
    worldConfig.update(true);
}

fn allowCheatsCallback(allow: bool) void {
    worldConfig.allowCheats = allow;
    worldConfig.update(true);
}

fn testingModeCallback(enabled: bool) void {
    worldConfig.testingMode = enabled;
    worldConfig.update(true);
}

fn doGameTimeCycleCallback(enabled: bool) void {
    worldConfig.doGameTimeCycle = enabled;
    worldConfig.update(true);
}

fn submit() void {
    worldConfig.save();
    worldConfig.update(false);
}

pub fn setEditWorldName(name: []const u8) void {
    main.globalAllocator.free(editWorldName);
    editWorldName = main.globalAllocator.dupe(u8, name);
}

pub fn onOpen() void {
    const list = VerticalList.init(.{ padding, 16 + padding }, 300, 8);

    const worldInfoPath = main.stackAllocator.print("saves/{s}/world.zig.zon", .{editWorldName});

    const worldInfo = main.files.cubyzDir().readToZon(main.stackAllocator, worldInfoPath) catch |err| {
        std.log.err("Couldn't open save {s}: {s}", .{ worldInfoPath, @errorName(err) });
        return;
    };

    const worldSettings = worldInfo.getChild("settings");

    worldConfig = WorldConfig.init(
        worldInfo.get([]const u8, "name") orelse "",
        worldSettings.get(i128, "seed") orelse 0,
        WorldConfig.getGameMode(worldSettings.get([]const u8, "defaultGameMode")),
        worldSettings.get(bool, "allowCheats") orelse defaultSettings.allowCheats,
        worldInfo.get(bool, "doGameTimeCycle") orelse true,
        worldSettings.get(bool, "testingMode") orelse defaultSettings.testingMode,
    );

    worldNameLabel = Label.init(.{ 0, 0 }, 128, worldConfig.worldName, .center);
    list.add(worldNameLabel);

    gamemodeInput = Button.initText(.{ 0, 0 }, 128, @tagName(worldConfig.defaultGamemode), .{ .onAction = .init(gamemodeCallback) });
    list.add(gamemodeInput);

    list.add(CheckBox.init(.{ 0, 0 }, 128, "Allow Cheats", worldConfig.allowCheats, &allowCheatsCallback));

    if (!build_options.isTaggedRelease) {
        list.add(CheckBox.init(.{ 0, 0 }, 128, "Developer Options", worldConfig.testingMode, &testingModeCallback));
    }

    const seedRow = HorizontalList.init();
    const seedLabel = Label.init(.{ 0, 0 }, 48, "Seed: ", .left);

    const worldSeedText = main.stackAllocator.print("{d}", .{worldConfig.seed});
    defer main.stackAllocator.free(worldSeedText);
    const seedValLabel = Label.init(.{ 0, 0 }, 128 - 48, worldSeedText, .left);
    seedRow.add(seedLabel);
    seedRow.add(seedValLabel);
    seedRow.finish(.{ 0, 0 }, .center);

    list.add(seedRow);

    list.add(CheckBox.init(.{ 0, 0 }, 128, "Time Cycle", worldConfig.doGameTimeCycle, &doGameTimeCycleCallback));

    //    list.add(DiscreteSlider.init(.{ 0, 0 }, 128, "Tick Speed", ": {}", &tickSpeeds, @as(worldConfig.tickSpeed), &pass3));

    saveConfig = Button.initText(.{ 0, 0 }, 128, "Save Changes", .{ .onAction = .init(submit), .disabled = !worldConfig.isUpdated });
    list.add(saveConfig);

    list.finish(.center);
    window.rootComponent = list.toComponent();
    window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
    gui.updateWindowPositions();
}

pub fn onClose() void {
    if (window.rootComponent) |*comp| {
        comp.deinit();
    }
}
