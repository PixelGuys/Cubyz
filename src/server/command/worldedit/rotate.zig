const std = @import("std");

const main = @import("main");
const User = main.server.User;
const Degrees = main.rotation.Degrees;

pub const description = "rotate clipboard content around Z axis counterclockwise.";
pub const usage =
	\\/rotate
	\\/rotate <0/90/180/270>
;

pub const Args = union(enum) {
	@"/rotate": struct {},
	@"/rotate <rotation>": struct { rotation: Degrees },
};

pub fn execute(result: Args, source: *User) void {
	if (source.worldEditData.clipboard == null) {
		source.sendMessage("#ff0000Error: No clipboard content to rotate.", .{});
		return;
	}
	const current = source.worldEditData.clipboard.?;
	defer current.deinit(main.globalAllocator);
	switch (result) {
		.@"/rotate" => source.worldEditData.clipboard = current.rotateZ(main.globalAllocator, .@"90"),
		.@"/rotate <rotation>" => |params| source.worldEditData.clipboard = current.rotateZ(main.globalAllocator, params.rotation),
	}
}
