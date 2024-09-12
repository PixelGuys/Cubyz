const std = @import("std");

const main = @import("root");
const User = main.server.User;

pub const description = "Teleport to location.";
pub const usage = "/tp <x> <y>\n/tp <x> <y> <z>";

pub fn execute(args: []const u8, source: *User) void {
	var x: ?f64 = null;
	var y: ?f64 = null;
	var z: ?f64 = null;
	var split = std.mem.splitScalar(u8, args, ' ');
	while(split.next()) |arg| {
		const num: f64 = std.fmt.parseFloat(f64, arg) catch {
			const msg = std.fmt.allocPrint(main.stackAllocator.allocator, "#ff0000Expected number, found \"{s}\"", .{arg}) catch unreachable;
			defer main.stackAllocator.free(msg);
			source.sendMessage(msg);
			return;
		};
		if(x == null) {
			x = num;
		} else if(y == null) {
			y = num;
		} else if(z == null) {
			z = num;
		} else {
			source.sendMessage("#ff0000Too many arguments for command /tp");
			return;
		}
	}
	if(x == null or y == null) {
		source.sendMessage("#ff0000Too few arguments for command /tp");
		return;
	}
	if(z == null) {
		z = source.player.pos[2];
	}
	x = std.math.clamp(x.?, -1e9, 1e9); // TODO: Remove after #310 is implemented
	y = std.math.clamp(y.?, -1e9, 1e9);
	z = std.math.clamp(z.?, -1e9, 1e9);
	main.network.Protocols.genericUpdate.sendTPCoordinates(source.conn, .{x.?, y.?, z.?});
}