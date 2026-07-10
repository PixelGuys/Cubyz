const std = @import("std");

const main = @import("main");
const settings = main.settings;
const graphics = main.graphics;
const draw = graphics.draw;
const vec = main.vec;
const Vec2f = vec.Vec2f;

const gui = @import("../gui.zig");
const GuiWindow = gui.GuiWindow;
const GuiComponent = gui.GuiComponent;

const width: f32 = 300;
const height: f32 = 36;
const pixelsPerDegree: f32 = 4.0;
const halfWidth: f32 = width / 2.0;

pub var window = GuiWindow{
    .relativePosition = .{
        .{ .ratio = 0.5 },
        .{ .attachedToFrame = .{ .selfAttachmentPoint = .lower, .otherAttachmentPoint = .lower } },
    },
    .contentSize = Vec2f{ width, height },
    .isHud = true,
    .showTitleBar = false,
    .hasBackground = false,
    .hideIfMouseIsGrabbed = false,
    .closeable = false,
};

const cardinalNames = [8][]const u8{ "N", "NE", "E", "SE", "S", "SW", "W", "NW" };

fn centeredText(str: []const u8, centerX: f32, y: f32, fontSize: f32) void {
    const w: f32 = @as(f32, @floatFromInt(str.len)) * fontSize * 0.6;
    draw.text(str, centerX - w / 2.0, y, fontSize);
}

fn wrapDiff(a: f32, b: f32) f32 {
    return @mod(a - b + 540.0, 360.0) - 180.0;
}

const MarkerStyle = enum { line, bracket };

const Theme = struct {
    background: ?u32,
    tickTop: f32,
    tickBottomCardinal: f32,
    tickBottomLabeled: f32,
    tickBottomMinor: f32,
    cardinalColor: u32,
    tickColorMinor: u32,
    numberLabelColor: u32,
    cardinalFontSize: f32,
    numberFontSize: f32,
    cardinalLabelY: f32,
    numberLabelY: f32,
    markerColor: u32,
    markerStyle: MarkerStyle,
    readout: bool,
};

const classicTheme = Theme{
    .background = 0x80101018,
    .tickTop = 8,
    .tickBottomCardinal = 28,
    .tickBottomLabeled = 22,
    .tickBottomMinor = 14,
    .cardinalColor = 0xffffcc33,
    .tickColorMinor = 0xffe0e0e0,
    .numberLabelColor = 0xffaaaaaa,
    .cardinalFontSize = 9,
    .numberFontSize = 7,
    .cardinalLabelY = 28,
    .numberLabelY = 22,
    .markerColor = 0xffff5555,
    .markerStyle = .line,
    .readout = false,
};

const parchmentTheme = Theme{
    .background = 0xd0d8c090,
    .tickTop = 8,
    .tickBottomCardinal = 28,
    .tickBottomLabeled = 22,
    .tickBottomMinor = 14,
    .cardinalColor = 0xff3a2410,
    .tickColorMinor = 0xff5a3a20,
    .numberLabelColor = 0xff6a4a2a,
    .cardinalFontSize = 9,
    .numberFontSize = 7,
    .cardinalLabelY = 28,
    .numberLabelY = 22,
    .markerColor = 0xff8b1a1a,
    .markerStyle = .line,
    .readout = false,
};

const forestTheme = Theme{
    .background = 0xb0182818,
    .tickTop = 8,
    .tickBottomCardinal = 28,
    .tickBottomLabeled = 22,
    .tickBottomMinor = 14,
    .cardinalColor = 0xffd4a017,
    .tickColorMinor = 0xff8fbf6b,
    .numberLabelColor = 0xff6f8f5a,
    .cardinalFontSize = 9,
    .numberFontSize = 7,
    .cardinalLabelY = 28,
    .numberLabelY = 22,
    .markerColor = 0xffd4a017,
    .markerStyle = .line,
    .readout = false,
};

const stoneTheme = Theme{
    .background = 0xc0525048,
    .tickTop = 8,
    .tickBottomCardinal = 28,
    .tickBottomLabeled = 22,
    .tickBottomMinor = 14,
    .cardinalColor = 0xff7fe0a0,
    .tickColorMinor = 0xffd0d0c8,
    .numberLabelColor = 0xffaaaaa0,
    .cardinalFontSize = 9,
    .numberFontSize = 7,
    .cardinalLabelY = 28,
    .numberLabelY = 22,
    .markerColor = 0xff7fe0a0,
    .markerStyle = .bracket,
    .readout = false,
};

const ironTheme = Theme{
    .background = 0xd0362413,
    .tickTop = 8,
    .tickBottomCardinal = 28,
    .tickBottomLabeled = 22,
    .tickBottomMinor = 14,
    .cardinalColor = 0xffb87333,
    .tickColorMinor = 0xff9a9a9a,
    .numberLabelColor = 0xff8a7a6a,
    .cardinalFontSize = 9,
    .numberFontSize = 7,
    .cardinalLabelY = 28,
    .numberLabelY = 22,
    .markerColor = 0xffb87333,
    .markerStyle = .bracket,
    .readout = false,
};

const minimalTheme = Theme{
    .background = null,
    .tickTop = 4,
    .tickBottomCardinal = 24,
    .tickBottomLabeled = 18,
    .tickBottomMinor = 12,
    .cardinalColor = 0xffffd700,
    .tickColorMinor = 0xff888888,
    .numberLabelColor = 0xffcccccc,
    .cardinalFontSize = 9,
    .numberFontSize = 6,
    .cardinalLabelY = 24,
    .numberLabelY = 18,
    .markerColor = 0xffffd700,
    .markerStyle = .line,
    .readout = true,
};

const themes = [_]Theme{ classicTheme, parchmentTheme, forestTheme, stoneTheme, ironTheme, minimalTheme };

const heldItemId = "cubyz:compass";

fn isHoldingCompass() bool {
    const held = main.game.Player.inventory.getItem(main.game.Player.selectedSlot);
    const id = held.id() orelse return false;
    return std.mem.eql(u8, id, heldItemId);
}

pub fn render() void {
    if (!settings.compassEnabled) return;
    if (!isHoldingCompass()) return;

    const headingDeg = @mod(std.math.radiansToDegrees(main.game.camera.rotation[2]), 360.0);
    const theme = themes[@min(settings.compassStyle, themes.len - 1)];
    renderThemed(theme, headingDeg);
}

fn renderThemed(theme: Theme, headingDeg: f32) void {
    if (theme.background) |bg| {
        const oldColor = draw.setColor(bg);
        defer draw.restoreColor(oldColor);
        draw.rect(Vec2f{ 0, theme.tickTop }, Vec2f{ width, height - theme.tickTop });
    }

    var degInt: i32 = 0;
    while (degInt < 360) : (degInt += 5) {
        const diff = wrapDiff(@floatFromInt(degInt), headingDeg);
        if (@abs(diff) > halfWidth / pixelsPerDegree) continue;
        const x = halfWidth + diff * pixelsPerDegree;

        const normDeg: u16 = @intCast(@mod(degInt, 360));
        const isCardinal = normDeg % 45 == 0;
        const isLabeled = normDeg % 15 == 0;
        const tickBottom: f32 = if (isCardinal) theme.tickBottomCardinal else if (isLabeled) theme.tickBottomLabeled else theme.tickBottomMinor;

        {
            const oldColor = draw.setColor(if (isCardinal) theme.cardinalColor else theme.tickColorMinor);
            defer draw.restoreColor(oldColor);
            draw.line(Vec2f{ x, theme.tickTop }, Vec2f{ x, tickBottom });
        }

        if (isLabeled) {
            if (isCardinal) {
                const oldColor = draw.setColor(theme.cardinalColor);
                defer draw.restoreColor(oldColor);
                centeredText(cardinalNames[normDeg / 45], x, theme.cardinalLabelY, theme.cardinalFontSize);
            } else {
                const oldColor = draw.setColor(theme.numberLabelColor);
                defer draw.restoreColor(oldColor);
                const str = std.fmt.allocPrint(main.stackAllocator.allocator, "{d}", .{normDeg}) catch unreachable;
                defer main.stackAllocator.free(str);
                centeredText(str, x, theme.numberLabelY, theme.numberFontSize);
            }
        }
    }

    {
        const oldColor = draw.setColor(theme.markerColor);
        defer draw.restoreColor(oldColor);
        switch (theme.markerStyle) {
            .line => draw.line(Vec2f{ halfWidth, 0 }, Vec2f{ halfWidth, theme.tickTop }),
            .bracket => {
                draw.line(Vec2f{ halfWidth - 6, 0 }, Vec2f{ halfWidth - 6, theme.tickTop + 2 });
                draw.line(Vec2f{ halfWidth + 6, 0 }, Vec2f{ halfWidth + 6, theme.tickTop + 2 });
                draw.line(Vec2f{ halfWidth - 6, 0 }, Vec2f{ halfWidth + 6, 0 });
            },
        }
    }

    if (theme.readout) {
        const roundedDeg: u16 = @intFromFloat(@mod(@round(headingDeg), 360.0));
        const oldColor = draw.setColor(0xffffffff);
        defer draw.restoreColor(oldColor);
        const str = std.fmt.allocPrint(main.stackAllocator.allocator, "{d}°", .{roundedDeg}) catch unreachable;
        defer main.stackAllocator.free(str);
        centeredText(str, halfWidth, height - 8, 8);
    }
}
