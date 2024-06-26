const std = @import("std");

const main = @import("root");
const c = main.Window.c;
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
	animation,
	chunk_rendering_preparation,
	chunk_rendering_previous_visible,
	chunk_rendering_occlusion_test,
	chunk_rendering_new_visible,
	entity_rendering,
	transparent_rendering_preparation,
	transparent_rendering_occlusion_test,
	transparent_rendering,
	bloom_extract_downsample,
	bloom_first_pass,
	bloom_second_pass,
	final_copy,
	gui,
};

const names = [_][]const u8 {
	"Screenbuffer clear",
	"Clear",
	"Pre-processing Block Animations",
	"Chunk Rendering Preparation",
	"Chunk Rendering Previous Visible",
	"Chunk Rendering Occlusion Test",
	"Chunk Rendering New Visible",
	"Entity Rendering",
	"Transparent Rendering Preparation",
	"Transparent Rendering Occlusion Test",
	"Transparent Rendering",
	"Bloom - Extract color and downsample",
	"Bloom - First Pass",
	"Bloom - Second Pass",
	"Copy to screen",
	"GUI Rendering",
};

const buffers = 4;
var curBuffer: u2 = 0;
var queryObjects: [buffers][@typeInfo(Samples).Enum.fields.len]c_uint = undefined;

var activeSample: ?Samples = null;

pub fn init() void {
	for(&queryObjects) |*buf| {
		c.glGenQueries(buf.len, buf);
		for(buf) |queryObject| { // Start them to get an initial value.
			c.glBeginQuery(c.GL_TIME_ELAPSED, queryObject);
			c.glEndQuery(c.GL_TIME_ELAPSED);
		}
	}
}

pub fn deinit() void {
	c.glDeleteQueries(queryObjects.len*buffers, @ptrCast(&queryObjects));
}

pub fn startQuery(sample: Samples) void {
	std.debug.assert(activeSample == null); // There can be at most one active measurement at a time.
	activeSample = sample;
	c.glBeginQuery(c.GL_TIME_ELAPSED, queryObjects[curBuffer][@intFromEnum(sample)]);
}

pub fn stopQuery() void {
	std.debug.assert(activeSample != null); // There must be an active measurement to stop.
	activeSample = null;
	c.glEndQuery(c.GL_TIME_ELAPSED);
}

pub var window = GuiWindow {
	.relativePosition = .{
		.{ .attachedToFrame = .{.selfAttachmentPoint = .upper, .otherAttachmentPoint = .upper} },
		.{ .attachedToFrame = .{.selfAttachmentPoint = .lower, .otherAttachmentPoint = .lower} },
	},
	.contentSize = Vec2f{256, 16},
	.isHud = false,
	.showTitleBar = false,
	.hasBackground = false,
	.hideIfMouseIsGrabbed = false,
};

pub fn render() void {
	curBuffer +%= 1;
	draw.setColor(0xffffffff);
	var sum: isize = 0;
	var y: f32 = 8;
	inline for(0..queryObjects[curBuffer].len) |i| {
		var result: u32 = undefined;
		c.glGetQueryObjectuiv(queryObjects[curBuffer][i], c.GL_QUERY_RESULT, &result);
		draw.print("{s}: {} µs", .{names[i], @divTrunc(result, 1000)}, 0, y, 8, .left);
		sum += result;
		y += 8;
	}
	draw.print("Total: {} µs", .{@divTrunc(sum, 1000)}, 0, 0, 8, .left);
}