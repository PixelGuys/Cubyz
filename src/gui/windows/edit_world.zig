const std = @import("std");

const main = @import("../../main.zig");
const ConnnectionManager = main.network.ConnectionManager;
const settings = main.settings;
const Vec2f = main.vec.Vec2f;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ZonElement = main.ZonElement;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const HorizontalList = @import("../components/HorizontalList.zig");
const Label = @import("../components/Label.zig");
const TextInput = @import("../components/TextInput.zig");
const CheckBox = @import("../components/CheckBox.zig");
const VerticalList = @import("../components/VerticalList.zig");

pub var window = GuiWindow{
    .contentSize = Vec2f{ 128, 256 },
};

const padding: f32 = 8;

var nameInput: *TextInput = undefined;
var seedInput: *TextInput = undefined;

var gameModeInput: *Button = undefined;

const ZonMapEntry = std.StringHashMapUnmanaged(ZonElement).Entry;
var worldPresets: []ZonMapEntry = &.{};
var selectedPreset: usize = undefined;
var defaultPreset: usize = 0;
var presetButton: *Button = undefined;

pub fn pass() void {}

pub fn onOpen() void {
    const list = VerticalList.init(.{ padding, 16 + padding }, 300, 8);
    nameInput = TextInput.init(.{ 0, 0 }, 128, 22, "WorldName", .{ .onNewline = .init(pass) });
    list.add(nameInput);
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
