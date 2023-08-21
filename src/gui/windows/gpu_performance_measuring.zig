const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const c = main.c;
const graphics = main.graphics;
const draw = graphics.draw;
const Texture = graphics.Texture;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiWindow = gui.GuiWindow;
const GuiComponent = gui.GuiComponent;

pub const Samples = enum(u8) {
	screenbuffer_clear,
	clear,
	chunk_rendering,
	entity_rendering,
	transparent_rendering,
	bloom,
	final_copy,
};

const names = [_][]const u8 {
	"Screenbuffer clear",
	"Clear",
	"Chunk Rendering",
	"Entity Rendering",
	"Transparent Rendering",
	"Bloom",
	"Copy to screen",
};

var queryObjects: [@typeInfo(Samples).Enum.fields.len]c_uint = undefined;

var activeSample: ?Samples = null;

pub fn init() !void {
	c.glGenQueries(queryObjects.len, &queryObjects);
	for(0..queryObjects.len) |i| { // Start them to get an initial value.
		c.glBeginQuery(c.GL_TIME_ELAPSED, queryObjects[i]);
		c.glEndQuery(c.GL_TIME_ELAPSED);
	}
}

pub fn deinit() void {
	c.glDeleteQueries(queryObjects.len, &queryObjects);
}

pub fn startQuery(sample: Samples) void {
	std.debug.assert(activeSample == null); // There can be at most one active measurement at a time.
	activeSample = sample;
	c.glBeginQuery(c.GL_TIME_ELAPSED, queryObjects[@intFromEnum(sample)]);
}

pub fn stopQuery() void {
	std.debug.assert(activeSample != null); // There must be an active measurement to stop.
	activeSample = null;
	c.glEndQuery(c.GL_TIME_ELAPSED);
}

pub var window = GuiWindow {
	.contentSize = Vec2f{128, 16},
	.id = "gpu_performance_measuring",
	.isHud = false,
	.showTitleBar = false,
	.hasBackground = false,
	.hideIfMouseIsGrabbed = false,
};

fn flawedRender() !void {
	draw.setColor(0xffffffff);
	var sum: isize = 0;
	var y: f32 = 8;
	inline for(0..queryObjects.len) |i| {
		var result: i64 = undefined;
		c.glGetQueryObjecti64v(queryObjects[i], c.GL_QUERY_RESULT, &result);
		try draw.print("{s}: {} ns", .{names[i], result}, 0, y, 8, .left);
		sum += result;
		y += 8;
	}
	try draw.print("Total: {} ns", .{sum}, 0, 0, 8, .left);
}

pub fn render() Allocator.Error!void {
	flawedRender() catch |err| {
		std.log.err("Encountered error while drawing debug window: {s}", .{@errorName(err)});
	};
}