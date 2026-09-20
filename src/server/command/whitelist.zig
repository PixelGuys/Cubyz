const std = @import("std");

const main = @import("main");
const command = main.server.command;
const Source = command.Source;
const players = main.server.players;

pub const description = "Manages the connection whitelist";
pub const usage =
	\\/whitelist <add/block> <keyType>:<base64Key>
	\\/whitelist <add/block> @<playerIndex>
	\\/whitelist <enable/disable>
;

const Action = enum { add, block };
const Toggle = enum { enable, disable };

pub const Args = union(enum) {
	@"/whitelist <action> <key>": struct { action: Action, key: command.KeyString },
	@"/whitelist <action> <playerIndex>": struct { action: Action, playerIndex: command.PlayerIndex },
	@"/whitelist <enable/disable>": struct { toggle: Toggle },
};

pub fn execute(args: Args, source: Source) void {
	switch (args) {
		.@"/whitelist <action> <key>" => |params| applyAction(source, params.action, params.key.key),
		.@"/whitelist <action> <playerIndex>" => |params| {
			const target = command.Target.fromPlayerIndex(params.playerIndex, source) catch return;
			const key = target.user.newKeyString orelse {
				source.sendMessage("#ff0000Player {s}§#ff0000 has no public key to whitelist", .{target.user.name});
				return;
			};
			applyAction(source, params.action, key);
		},
		.@"/whitelist <enable/disable>" => |params| {
			main.server.world.?.settings.whitelistEnabled.store(params.toggle == .enable, .monotonic);
			main.server.world.?.saveWorldConfig() catch |err| {
				std.log.err("Error while saving world config: {s}", .{@errorName(err)});
			};
			source.sendMessage("#00ff00Whitelist {s}", .{if (params.toggle == .enable) "enabled" else "disabled"});
		},
	}
}

fn applyAction(source: Source, action: Action, key: []const u8) void {
	switch (action) {
		.add => switch (players.add(key)) {
			.added => source.sendMessage("#00ff00Added {s}§#00ff00 to the whitelist", .{key}),
			.alreadyAllowed => source.sendMessage("#ff0000{s}§#ff0000 is already on the whitelist", .{key}),
		},
		.block => {
			switch (players.block(key)) {
				.blocked => source.sendMessage("#00ff00Blocked {s}§#00ff00 from connecting", .{key}),
				.alreadyBlocked => source.sendMessage("#ff0000{s}§#ff0000 is already blocked", .{key}),
			}
			const userList = main.server.getUserList(main.stackAllocator);
			defer main.stackAllocator.free(userList);
			for (userList) |user| {
				if (user.newKeyString) |userKey| {
					if (std.mem.eql(u8, userKey, key)) {
						user.conn.disconnect();
						break;
					}
				}
			}
		},
	}
}
