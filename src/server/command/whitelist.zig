const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ListManaged = main.ListManaged;
const command = main.server.command;
const Source = command.Source;
const players = main.server.players;

pub const description = "Manages the connection whitelist";
pub const usage =
	\\/whitelist <add/block> <keyType>:<base64Key>
	\\/whitelist <add/block> @<playerIndex>
;

const Action = enum { add, block };

pub const Args = union(enum) {
	@"/whitelist <action> <key>": struct { action: Action, key: KeyString },
	@"/whitelist <action> <playerIndex>": struct { action: Action, playerIndex: command.PlayerIndex },
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
	}
}

fn applyAction(source: Source, action: Action, key: []const u8) void {
	switch (action) {
		.add => switch (players.add(key)) {
			.added => source.sendMessage("#00ff00Added {s}§#00ff00 to the whitelist", .{key}),
			.alreadyAllowed => source.sendMessage("#ff0000{s}§#ff0000 is already on the whitelist", .{key}),
		},
		.block => switch (players.block(key)) {
			.blocked => source.sendMessage("#00ff00Blocked {s}§#00ff00 from connecting", .{key}),
			.alreadyBlocked => source.sendMessage("#ff0000{s}§#ff0000 is already blocked", .{key}),
		},
	}
}

const KeyString = struct {
	key: []const u8,

	pub fn parse(_: NeverFailingAllocator, name: []const u8, arg: []const u8, errorMessage: *ListManaged(u8)) error{ParseError}!KeyString {
		const colonIndex = std.mem.indexOfScalar(u8, arg, ':') orelse {
			errorMessage.print("Expected a public key of the form \"<keyType>:<base64>\" for <{s}>, found \"{s}\"", .{name, arg});
			return error.ParseError;
		};
		_ = std.meta.stringToEnum(main.network.authentication.KeyTypeEnum, arg[0..colonIndex]) orelse {
			errorMessage.print("Unknown key type \"{s}\" for <{s}>", .{arg[0..colonIndex], name});
			return error.ParseError;
		};
		return .{.key = arg};
	}
};
