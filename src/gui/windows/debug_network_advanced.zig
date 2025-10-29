const std = @import("std");

const main = @import("main");
const graphics = main.graphics;
const draw = graphics.draw;
const Texture = graphics.Texture;
const network = main.network;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiWindow = gui.GuiWindow;
const GuiComponent = gui.GuiComponent;

pub var window = GuiWindow{
	.relativePosition = .{
		.{.attachedToFrame = .{.selfAttachmentPoint = .middle, .otherAttachmentPoint = .middle}},
		.{.attachedToFrame = .{.selfAttachmentPoint = .upper, .otherAttachmentPoint = .upper}},
	},
	.contentSize = Vec2f{192, 128},
	.isHud = false,
	.showTitleBar = false,
	.hasBackground = false,
	.hideIfMouseIsGrabbed = false,
};

fn renderConnectionData(conn: *main.network.Connection, name: []const u8, y: *f32) void {
	conn.mutex.lock();
	defer conn.mutex.unlock();
	var unconfirmed: [3]usize = @splat(0);
	var queued: [3]usize = @splat(0);
	conn.lossyChannel.getStatistics(&unconfirmed[0], &queued[0]);
	conn.fastChannel.getStatistics(&unconfirmed[1], &queued[1]);
	conn.slowChannel.getStatistics(&unconfirmed[2], &queued[2]);
	draw.print("{s} | RTT = {d:.1} ms | {d:.0} kiB/RTT", .{name, conn.rttEstimate/1000.0, conn.bandwidthEstimateInBytesPerRtt/1024.0}, 0, y.*, 8, .left);
	y.* += 8;
	draw.print("Waiting in queue:      {: >6} kiB |{: >6} kiB |{: >6} kiB", .{queued[0] >> 10, queued[1] >> 10, queued[2] >> 10}, 0, y.*, 8, .left);
	y.* += 8;
	draw.print("Sent but not confirmed:{: >6} kiB |{: >6} kiB |{: >6} kiB", .{unconfirmed[0] >> 10, unconfirmed[1] >> 10, unconfirmed[2] >> 10}, 0, y.*, 8, .left);
	y.* += 8;
}

pub fn render() void {
	draw.setColor(0xffffffff);
	var y: f32 = 0;
	if(main.game.world != null) {
		renderConnectionData(main.game.world.?.conn, "Client", &y);
	}
	y += 8;
	if(main.server.world != null) {
		const userList = main.server.getUserListAndIncreaseRefCount(main.stackAllocator);
		defer main.server.freeUserListAndDecreaseRefCount(main.stackAllocator, userList);
		for(userList) |user| {
			renderConnectionData(user.conn, user.name, &y);
		}
	}
	if(window.contentSize[1] != y) {
		window.contentSize[1] = y;
		window.updateWindowPosition();
	}
}
