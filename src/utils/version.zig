const std = @import("std");
const build_options = @import("build_options");

pub const version = build_options.version;

fn isCompatibleClientVersionImpl(clientVersion: []const u8, serverVersion: []const u8) !bool {
	if(std.mem.endsWith(u8, serverVersion, "-dev")) return true;
	if(std.mem.endsWith(u8, clientVersion, "-dev")) return false;

	const client = try std.SemanticVersion.parse(clientVersion);
	const server = try std.SemanticVersion.parse(serverVersion);

	return client.major == server.major and client.minor == server.minor;
}

pub fn isCompatibleClientVersion(clientVersion: []const u8) !bool {
	return isCompatibleClientVersionImpl(clientVersion, version);
}

test "version correctness" {
	_ = try std.SemanticVersion.parse(version);
}

test "dev version" {
	const serverVersion = "1054.11.423-dev";
	try std.testing.expect(try isCompatibleClientVersionImpl("0.3.1", serverVersion));
	try std.testing.expect(try isCompatibleClientVersionImpl("100.0.0-dev", serverVersion));
	try std.testing.expect(try isCompatibleClientVersionImpl("0.0.0-dev", serverVersion));
	try std.testing.expect(try isCompatibleClientVersionImpl("1055.12.424", serverVersion));
	try std.testing.expect(try isCompatibleClientVersionImpl(serverVersion, serverVersion));
}

test "release version" {
	const serverVersion = "4.5.6";
	try std.testing.expect(!try isCompatibleClientVersionImpl("0.3.1", serverVersion));
	try std.testing.expect(!try isCompatibleClientVersionImpl("100.0.0-dev", serverVersion));
	try std.testing.expect(!try isCompatibleClientVersionImpl("0.0.0-dev", serverVersion));
	try std.testing.expect(!try isCompatibleClientVersionImpl("1055.12.424", serverVersion));
	try std.testing.expect(try isCompatibleClientVersionImpl(serverVersion, serverVersion));
	try std.testing.expect(try isCompatibleClientVersionImpl("4.5.0", serverVersion));
	try std.testing.expect(try isCompatibleClientVersionImpl("4.5.10", serverVersion));
	try std.testing.expect(!try isCompatibleClientVersionImpl("4.6.6", serverVersion));
	try std.testing.expect(!try isCompatibleClientVersionImpl("4.4.6", serverVersion));
	try std.testing.expect(!try isCompatibleClientVersionImpl("3.5.6", serverVersion));
	try std.testing.expect(!try isCompatibleClientVersionImpl("5.5.6", serverVersion));
}
