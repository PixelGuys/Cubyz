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
	animation,
	chunk_rendering,
	voxel_model_rendering,
	entity_rendering,
	transparent_rendering,
	bloom_extract_downsample,
	bloom_first_pass,
	bloom_second_pass,
	bloom_upscale,
	final_copy,
	gui,
};

const names = [_][]const u8 {
	"Screenbuffer clear",
	"Clear",
	"Pre-processing Block Animations",
	"Chunk Rendering",
	"Voxel Model Rendering",
	"Entity Rendering",
	"Transparent Rendering",
	"Bloom - Extract color and downsample",
	"Bloom - First Pass",
	"Bloom - Second Pass",
	"Bloom - Upscale",
	"Copy to screen",
	"GUI Rendering",
};

const buffers = 4;
var curBuffer: u2 = 0;
var queryObjects: [buffers][@typeInfo(Samples).Enum.fields.len]c_uint = undefined;

var activeSample: ?Samples = null;

pub fn init() !void {
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
	.id = "gpu_performance_measuring",
	.isHud = false,
	.showTitleBar = false,
	.hasBackground = false,
	.hideIfMouseIsGrabbed = false,
};

fn flawedRender() !void {
	curBuffer +%= 1;
	draw.setColor(0xffffffff);
	var sum: isize = 0;
	var y: f32 = 8;
	inline for(0..queryObjects[curBuffer].len) |i| {
		var result: i64 = undefined;
		c.glGetQueryObjecti64v(queryObjects[curBuffer][i], c.GL_QUERY_RESULT, &result);
		try draw.print("{s}: {} µs", .{names[i], @divTrunc(result, 1000)}, 0, y, 8, .left);
		sum += result;
		y += 8;
	}
	try draw.print("Total: {} µs", .{@divTrunc(sum, 1000)}, 0, 0, 8, .left);
}

pub fn render() Allocator.Error!void {
	flawedRender() catch |err| {
		std.log.err("Encountered error while drawing debug window: {s}", .{@errorName(err)});
	};
}