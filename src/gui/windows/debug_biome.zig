const std = @import("std");

const main = @import("main");
const graphics = main.graphics;
const draw = graphics.draw;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiWindow = gui.GuiWindow;

pub var window = GuiWindow{
	.relativePosition = .{
		.{.attachedToFrame = .{.selfAttachmentPoint = .lower, .otherAttachmentPoint = .lower}},
		.{.attachedToFrame = .{.selfAttachmentPoint = .upper, .otherAttachmentPoint = .upper}},
	},
	.contentSize = Vec2f{160, 64},
	.isHud = false,
	.showTitleBar = false,
	.hasBackground = false,
	.hideIfMouseIsGrabbed = false,
};

fn moodBar(currentFrame: *graphics.vulkan.Frame, label: []const u8, value: f32, baseValue: f32, fillColor: u32, y: *f32) void {
	draw.print(currentFrame, "{s}: {d:.2}", .{label, value}, 0, y.*, 8);
	y.* += 8;

	const barWidth: f32 = 100;
	const barHeight: f32 = 6;
	{
		const oldColor = draw.setColor(0x80000000);
		defer draw.restoreColor(oldColor);
		draw.rect(currentFrame, .{0, y.*}, .{barWidth, barHeight});
	}
	{
		const oldColor = draw.setColor(fillColor);
		defer draw.restoreColor(oldColor);
		draw.rect(currentFrame, .{0, y.*}, .{barWidth*std.math.clamp(value, 0, 1), barHeight});
	}
	{
		const oldColor = draw.setColor(0xff000000);
		defer draw.restoreColor(oldColor);
		draw.rect(currentFrame, .{barWidth*std.math.clamp(baseValue, 0, 1) - 1, y.* - 1}, .{2, barHeight + 2});
	}
	y.* += barHeight + 2;
}

pub fn render(currentFrame: *graphics.vulkan.Frame) void {
	var y: f32 = 0;
	if (main.game.world != null) {
		{
			const biome = main.game.world.?.playerBiome.load(.monotonic);
			var tags = main.ListManaged(u8).init(main.stackAllocator);
			defer tags.deinit();
			inline for (@typeInfo(main.server.terrain.biomes.Biome.ClimateProperties).@"struct".field_names) |name| {
				if (@field(biome.climate, name)) {
					if (tags.items.len != 0) tags.appendSlice(", ");
					tags.appendSlice(name);
				}
			}
			draw.print(currentFrame, "Biome: {s}", .{biome.id}, 0, y, 8);
			y += 8;
			draw.print(currentFrame, "Biome Climate: {s}", .{tags.items}, 0, y, 8);
			y += 8;
		}
		moodBar(currentFrame, "Anxiety", main.audio.mood.current.anxiety, main.audio.mood.target.anxiety, 0xffaa4444, &y);
		moodBar(currentFrame, "Energy", main.audio.mood.current.energy, main.audio.mood.target.energy, 0xffaaaa33, &y);
		moodBar(currentFrame, "Sanity", main.audio.mood.current.sanity, main.audio.mood.target.sanity, 0xff44aa66, &y);
	}
}
