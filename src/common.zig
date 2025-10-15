const main = @import("main");

pub const Gamemode = enum(u8) {survival = 0, creative = 1};

pub const DamageType = enum(u8) {
	heal = 0, // For when you are adding health
	kill = 1,
	fall = 2,

	pub fn sendMessage(self: DamageType, name: []const u8) void {
		switch(self) {
			.heal => main.server.sendMessage("{s}§#ffffff was healed", .{name}),
			.kill => main.server.sendMessage("{s}§#ffffff was killed", .{name}),
			.fall => main.server.sendMessage("{s}§#ffffff died of fall damage", .{name}),
		}
	}
};
