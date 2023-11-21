const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const graphics = main.graphics;
const draw = graphics.draw;
const Texture = graphics.Texture;
const network = main.network;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiWindow = gui.GuiWindow;
const GuiComponent = gui.GuiComponent;

pub var window = GuiWindow {
	.relativePosition = .{
		.{ .attachedToFrame = .{.selfAttachmentPoint = .upper, .otherAttachmentPoint = .upper} },
		.{ .attachedToFrame = .{.selfAttachmentPoint = .upper, .otherAttachmentPoint = .upper} },
	},
	.contentSize = Vec2f{192, 128},
	.id = "debug_network",
	.isHud = false,
	.showTitleBar = false,
	.hasBackground = false,
	.hideIfMouseIsGrabbed = false,
};

fn flawedRender() !void {
	draw.setColor(0xffffffff);
	var y: f32 = 0;
	if (main.game.world != null) {
		if(main.server.world != null) {
			try draw.print("Players Connected: {}", .{main.server.users.items.len}, 0, y, 8, .left);
			y += 8;
		}
		const sent = network.Connection.packetsSent.load(.Monotonic);
		const resent = network.Connection.packetsResent.load(.Monotonic);
		const loss = @as(f64, @floatFromInt(resent))/@as(f64, @floatFromInt(sent))*100;
		try draw.print("Packet loss: {d:.1}% ({}/{})", .{loss, resent, sent}, 0, y, 8, .left);
		y += 8;
		inline for(@typeInfo(network.Protocols).Struct.decls) |decl| {
			if(@TypeOf(@field(network.Protocols, decl.name)) == type) {
				const id = @field(network.Protocols, decl.name).id;
				try draw.print("{s}: {}kiB in {} packets", .{decl.name, network.bytesReceived[id].load(.Monotonic) >> 10, network.packetsReceived[id].load(.Monotonic)}, 0, y, 8, .left);
				y += 8;
			}
		}
	}
	if(window.size[1] != y) {
		window.size[1] = y;
		window.updateWindowPosition();
	}
}

pub fn render() Allocator.Error!void {
	flawedRender() catch |err| {
		std.log.err("Encountered error while drawing debug window: {s}", .{@errorName(err)});
	};
}