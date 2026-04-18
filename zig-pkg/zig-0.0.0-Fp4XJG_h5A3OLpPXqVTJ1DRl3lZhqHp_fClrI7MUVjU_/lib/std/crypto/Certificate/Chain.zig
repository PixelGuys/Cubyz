//! A sequence of certificates, where each certificate is authenticated by the next certificate.
const Chain = @This();

store: ?crypt32.HCERTSTORE,
primary: ?*const crypt32.CERT_CONTEXT,

pub const empty: Chain = .{ .store = null, .primary = null };

pub fn deinit(chain: *Chain) void {
    if (chain.primary) |primary| assert(crypt32.CertFreeCertificateContext(primary).toBool());
    if (chain.store) |store| if (!crypt32.CertCloseStore(store, .{
        .CHECK = std.debug.runtime_safety,
    }).toBool()) std.os.windows.unexpectedError(std.os.windows.GetLastError()) catch unreachable;
    chain.* = .empty;
}

pub fn addCert(chain: *Chain, cert: []const u8) std.Io.UnexpectedError!void {
    const store = chain.store orelse store: {
        const store = crypt32.CertOpenStore(
            .MEMORY,
            .{},
            .NULL,
            .{},
            null,
        ) orelse return std.os.windows.unexpectedError(std.os.windows.GetLastError());
        chain.store = store;
        break :store store;
    };
    if (!crypt32.CertAddEncodedCertificateToStore(
        store,
        .{ .CERT = .ASN },
        cert.ptr,
        @intCast(cert.len),
        .ALWAYS,
        if (chain.primary) |_| null else &chain.primary,
    ).toBool()) return std.os.windows.unexpectedError(std.os.windows.GetLastError());
}

pub const VerifyError = error{
    TlsCertificateNotVerified,
} || std.Io.UnexpectedError;

pub fn verify(chain: *const Chain, now: std.Io.Timestamp) VerifyError!void {
    const now_win = @divFloor(now.nanoseconds - std.time.epoch.windows * std.time.ns_per_s, 100);
    var cert_chain: *const crypt32.CERT_CHAIN.CONTEXT = undefined;
    if (!crypt32.CertGetCertificateChain(
        .CURRENT_USER,
        chain.primary orelse return error.TlsCertificateNotVerified,
        &.{
            .dwLowDateTime = @bitCast(@as(i32, @truncate(now_win >> 0))),
            .dwHighDateTime = @bitCast(@as(i32, @intCast(now_win >> 32))),
        },
        null,
        &.{ .RequestedUsage = .{ .dwType = .AND, .Usage = .{
            .cUsageIdentifier = ALLOWED_EKUS.len,
            .rgpszUsageIdentifier = &ALLOWED_EKUS,
        } } },
        .{ .REVOCATION_CHECK_END_CERT = true, .REVOCATION_ACCUMULATIVE_TIMEOUT = true },
        null,
        &cert_chain,
    ).toBool()) return std.os.windows.unexpectedError(std.os.windows.GetLastError());
    defer crypt32.CertFreeCertificateChain(cert_chain);
    var status: crypt32.CERT_CHAIN.POLICY.STATUS = .{
        .dwError = undefined,
        .lChainIndex = undefined,
        .lElementIndex = undefined,
        .pvExtraPolicyStatus = undefined,
    };
    if (!crypt32.CertVerifyCertificateChainPolicy(
        .SSL,
        cert_chain,
        &.{
            .dwFlags = .{
                .IGNORE_END_REV_UNKNOWN = true,
                .IGNORE_CTL_SIGNER_REV_UNKNOWN = true,
                .IGNORE_CA_REV_UNKNOWN = true,
                .IGNORE_ROOT_REV_UNKNOWN = true,
            },
            .pvExtraPolicyPara = @constCast(&crypt32.HTTPSPolicyCallbackData{ .dwAuthType = .SERVER }),
        },
        &status,
    ).toBool()) return std.os.windows.unexpectedError(std.os.windows.GetLastError());
    switch (status.dwError) {
        .SUCCESS => return,
        .CERT_E_UNTRUSTEDROOT => return error.TlsCertificateNotVerified,
        else => |err| return std.os.windows.unexpectedError(err),
    }
}

const ALLOWED_EKUS = [_][*:0]const u8{"1.3.6.1.5.5.7.3.1"};

const assert = std.debug.assert;
const builtin = @import("builtin");
const std = @import("std");
const crypt32 = std.os.windows.crypt32;
