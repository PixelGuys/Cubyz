const std = @import("std");
const assert = std.debug.assert;

pub const Module = @import("Package/Module.zig");
pub const Fetch = @import("Package/Fetch.zig");
pub const build_zig_basename = "build.zig";
pub const Manifest = @import("Package/Manifest.zig");

pub const Fingerprint = packed struct(u64) {
    id: u32,
    checksum: u32,

    pub fn generate(rng: std.Random, name: []const u8) Fingerprint {
        return .{
            .id = rng.intRangeLessThan(u32, 1, 0xffffffff),
            .checksum = std.hash.Crc32.hash(name),
        };
    }

    pub fn validate(n: Fingerprint, name: []const u8) bool {
        switch (n.id) {
            0x00000000, 0xffffffff => return false,
            else => return std.hash.Crc32.hash(name) == n.checksum,
        }
    }

    pub fn int(n: Fingerprint) u64 {
        return @bitCast(n);
    }
};

/// A user-readable, file system safe hash that identifies an exact package
/// snapshot, including file contents.
///
/// The hash is not only to prevent collisions but must resist attacks where
/// the adversary fully controls the contents being hashed. Thus, it contains
/// a full SHA-256 digest.
///
/// This data structure can be used to store the legacy hash format too. Legacy
/// hash format is scheduled to be removed after 0.14.0 is tagged.
///
/// There's also a third way this structure is used. When using path rather than
/// hash, a unique hash is still needed, so one is computed based on the path.
pub const Hash = struct {
    /// Maximum size of a package hash. Unused bytes at the end are
    /// filled with zeroes.
    ///
    /// Assumed to be already validated.
    bytes: [max_len]u8,

    pub const Algo = std.crypto.hash.sha2.Sha256;
    pub const Digest = [Algo.digest_length]u8;

    /// Example: "nnnn-vvvv-hhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhh"
    pub const max_len = 32 + 1 + 32 + 1 + (32 + 32 + 200) / 6;

    /// Asserts `s` is valid.
    pub fn fromSlice(s: []const u8) Hash {
        assert(validate(s) == .ok);
        var result: Hash = undefined;
        @memcpy(result.bytes[0..s.len], s);
        @memset(result.bytes[s.len..], 0);
        return result;
    }

    pub const Validation = enum { ok, short, long, incomplete };

    pub fn validate(s: []const u8) Validation {
        if (s.len > max_len) return .long;
        if (s.len < 44) return .short;
        const n_dashes = std.mem.countScalar(u8, s[0 .. s.len - 44], '-');
        if (n_dashes < 2) return .incomplete;
        return .ok;
    }

    test validate {
        try std.testing.expectEqual(.short, validate(""));
    }

    pub fn toSlice(ph: *const Hash) []const u8 {
        var end: usize = ph.bytes.len;
        while (true) {
            end -= 1;
            if (ph.bytes[end] != 0) return ph.bytes[0 .. end + 1];
        }
    }

    pub fn eql(a: *const Hash, b: *const Hash) bool {
        return std.mem.eql(u8, &a.bytes, &b.bytes);
    }

    /// Produces "$name-$semver-$hashplus".
    /// * name is the name field from build.zig.zon, asserted to be at most 32
    ///   bytes and assumed be a valid zig identifier
    /// * semver is the version field from build.zig.zon, asserted to be at
    ///   most 32 bytes
    /// * hashplus is the following 33-byte array, base64 encoded using -_ to make
    ///   it filesystem safe:
    ///   - (4 bytes) LE u32 Package ID
    ///   - (4 bytes) LE u32 total decompressed size in bytes, overflow saturated
    ///   - (25 bytes) truncated SHA-256 digest of hashed files of the package
    pub fn init(digest: Digest, name: []const u8, ver: []const u8, id: u32, size: u32) Hash {
        assert(name.len <= 32);
        assert(ver.len <= 32);
        var result: Hash = undefined;
        var buf: std.ArrayList(u8) = .initBuffer(&result.bytes);
        buf.appendSliceAssumeCapacity(name);
        buf.appendAssumeCapacity('-');
        buf.appendSliceAssumeCapacity(ver);
        buf.appendAssumeCapacity('-');
        var hashplus: [33]u8 = undefined;
        std.mem.writeInt(u32, hashplus[0..4], id, .little);
        std.mem.writeInt(u32, hashplus[4..8], size, .little);
        hashplus[8..].* = digest[0..25].*;
        _ = std.base64.url_safe_no_pad.Encoder.encode(buf.addManyAsArrayAssumeCapacity(44), &hashplus);
        @memset(buf.unusedCapacitySlice(), 0);
        return result;
    }

    /// Produces a unique hash based on the path provided. The result should
    /// not be user-visible.
    pub fn initPath(sub_path: []const u8, is_global: bool) Hash {
        var result: Hash = .{ .bytes = @splat(0) };
        var i: usize = 0;
        if (is_global) {
            result.bytes[0] = '/';
            i += 1;
        }
        if (i + sub_path.len <= result.bytes.len) {
            @memcpy(result.bytes[i..][0..sub_path.len], sub_path);
            return result;
        }
        var bin_digest: [Algo.digest_length]u8 = undefined;
        Algo.hash(sub_path, &bin_digest, .{});
        _ = std.fmt.bufPrint(result.bytes[i..], "{x}", .{&bin_digest}) catch unreachable;
        return result;
    }

    pub fn projectId(hash: *const Hash) ProjectId {
        const bytes = hash.toSlice();
        const name = std.mem.sliceTo(bytes, '-');
        const encoded_hashplus = bytes[bytes.len - 44 ..];
        var hashplus: [33]u8 = undefined;
        std.base64.url_safe_no_pad.Decoder.decode(&hashplus, encoded_hashplus) catch unreachable;
        const fingerprint_id = std.mem.readInt(u32, hashplus[0..4], .little);
        return .init(name, fingerprint_id);
    }

    test projectId {
        const hash: Hash = .fromSlice("pulseaudio-16.1.1-9-mk_62MZkNwBaFwiZ7ZVrYRIf_3dTqqJR5PbMRCJzSuLw");
        const project_id = hash.projectId();

        var expected_name: [32]u8 = @splat(0);
        expected_name[0.."pulseaudio".len].* = "pulseaudio".*;
        try std.testing.expectEqualSlices(u8, &expected_name, &project_id.padded_name);

        try std.testing.expectEqual(0xd8fa4f9a, project_id.fingerprint_id);
    }

    test "projectId with dashes in the base64" {
        const hash: Hash = .fromSlice("dvui-0.4.0-dev-AQFJmayi2gAKE7FeJoF61v5U1IV9-SupoEcFutIZYpkC");
        const project_id = hash.projectId();

        var expected_name: [32]u8 = @splat(0);
        expected_name[0.."dvui".len].* = "dvui".*;
        try std.testing.expectEqualSlices(u8, &expected_name, &project_id.padded_name);

        try std.testing.expectEqual(0x99490101, project_id.fingerprint_id);
    }
};

/// Minimum information required to identify whether a package is an artifact
/// of a given project.
pub const ProjectId = struct {
    /// Bytes after name.len are set to zero.
    padded_name: [32]u8,
    fingerprint_id: u32,

    pub fn init(name: []const u8, fingerprint_id: u32) ProjectId {
        var padded_name: [32]u8 = @splat(0);
        @memcpy(padded_name[0..name.len], name);
        return .{
            .padded_name = padded_name,
            .fingerprint_id = fingerprint_id,
        };
    }

    pub fn eql(a: *const ProjectId, b: *const ProjectId) bool {
        return a.fingerprint_id == b.fingerprint_id and std.mem.eql(u8, &a.padded_name, &b.padded_name);
    }

    pub fn hash(a: *const ProjectId) u64 {
        const x: u64 = @bitCast(a.padded_name[0..8].*);
        return std.hash.int(x | a.fingerprint_id);
    }
};

test Hash {
    const example_digest: Hash.Digest = .{
        0xc7, 0xf5, 0x71, 0xb7, 0xb4, 0xe7, 0x6f, 0x3c, 0xdb, 0x87, 0x7a, 0x7f, 0xdd, 0xf9, 0x77, 0x87,
        0x9d, 0xd3, 0x86, 0xfa, 0x73, 0x57, 0x9a, 0xf7, 0x9d, 0x1e, 0xdb, 0x8f, 0x3a, 0xd9, 0xbd, 0x9f,
    };
    const result: Hash = .init(example_digest, "nasm", "2.16.1-3", 0xcafebabe, 10 * 1024 * 1024);
    try std.testing.expectEqualStrings("nasm-2.16.1-3-vrr-ygAAoADH9XG3tOdvPNuHen_d-XeHndOG-nNXmved", result.toSlice());
}

test {
    _ = Fetch;
}
