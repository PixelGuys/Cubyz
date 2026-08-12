const std = @import("std");
const builtin = @import("builtin");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const EncodingType = main.network.authentication.EncodingType;
const c = @import("c");

pub inline fn canProtect() bool {
	switch (builtin.os.tag) {
		.windows => return true,
		else => return false,
	}
}

pub fn protect(allocator: NeverFailingAllocator, data: []u8) error{ syserr, Unsupported }![]u8 {
	if (builtin.os.tag == .windows) {
		var plainblob: c.DATA_BLOB = undefined;
		var cipherblob: c.DATA_BLOB = undefined;
		plainblob.cbData = @intCast(data.len);
		plainblob.pbData = @as([*c]u8, data.ptr); // Does this need to be secureZeroed?
		if (c.CryptProtectData(&plainblob, @as([*c]const c_ushort, null), @as([*c]c.DATA_BLOB, null), null, @as([*c]c.CRYPTPROTECT_PROMPTSTRUCT, null), @as(c_ulong, 0), &cipherblob) == 0) {
			std.log.err("CryptProtectData syscall failed. Errorcode: {}. This should never happen. Please report it to the maintainers.", .{c.GetLastError()});
			return error.syserr;
		}
		defer if (c.LocalFree(cipherblob.pbData) != null) std.log.err("LocalFree syscall failed to free previously allocated memory. Errorcode: {}. This should never happen. Please report it to the maintainers.", .{c.GetLastError()});
		const out: []u8 = allocator.alloc(u8, @intCast(cipherblob.cbData));
		@memcpy(out, cipherblob.pbData);
		return out;
	} else {
		return error.Unsupported;
	}
}

pub fn unprotect(allocator: NeverFailingAllocator, data: []u8) error{ syserr, Invalid }![]u8 {
	if (builtin.os.tag == .windows) {
		var plainblob: c.DATA_BLOB = undefined;
		var cipherblob: c.DATA_BLOB = undefined;
		cipherblob.cbData = @intCast(data.len);
		cipherblob.pbData = @as([*c]u8, data.ptr);
		if (c.CryptUnprotectData(&cipherblob, @as([*c][*c]c_ushort, null), @as([*c]c.DATA_BLOB, null), null, @as([*c]c.CRYPTPROTECT_PROMPTSTRUCT, null), @as(c_ulong, 0), &plainblob) == 0) {
			const err = c.GetLastError();
			if (err == 13 or err == 87) {
				return error.Invalid;
			}
			std.log.err("CryptUnprotectData syscall failed. Errorcode: {}", .{err});
			return error.syserr;
		}
		var pbDataSlice: []u8 = undefined;
		pbDataSlice.len = plainblob.cbData;
		pbDataSlice.ptr = plainblob.pbData;
		defer {
			std.crypto.secureZero(u8, pbDataSlice);
			if (c.LocalFree(plainblob.pbData) != null) std.log.err("LocalFree syscall failed to free previously allocated memory. Errorcode: {}. This should never happen. Please report it to the maintainers.", .{c.GetLastError()});
		}
		const out: []u8 = allocator.alloc(u8, @intCast(plainblob.cbData));
		@memcpy(out, plainblob.pbData);
		return out;
	} else {
		return error.Invalid;
	}
}

test "slice==unprotect(protect(slice))" {
	const slice: []u8 = @as([]u8, @constCast("Test"));
	if (canProtect()) {
		const protected = try protect(main.stackAllocator, slice);
		defer main.stackAllocator.free(protected);
		const unprotected = try unprotect(main.stackAllocator, protected);
		defer main.stackAllocator.free(unprotected);
		try std.testing.expectEqualSlices(u8, slice, unprotected);
	}
}

test "Protect fails on unsupported platforms" {
	const slice: []u8 = @as([]u8, @constCast("Test"));
	if (!canProtect()) {
		try std.testing.expectError(error.Unsupported, protect(main.stackAllocator, slice));
		try std.testing.expectError(error.Invalid, unprotect(main.stackAllocator, slice));
	}
}

test "Unprotect fails when supplied with garbage" {
	const slices: [5][]u8 = .{@as([]u8, @constCast("TestdwadadÖOUWHdöouHIOSUdhöoUHNWLJDKNOÖPAHUIwdoöJKNSdlkjöwuHOÖIhso8zpo9IKj")), @as([]u8, @constCast("Test")), @as([]u8, @constCast("Testd")), @as([]u8, @constCast("")), @as([]u8, @constCast("WIJDp8iU)(du098UÜ=JHd0ü8hz=Ü(HJ0isidjowi8h=(Z\"ß08IJUISdhd0w98hdoi8uoIWUJDoikjsoIKHJOwiuhdOISHNdo9i8H(UIHNASUJhdnbiuJBWGiudjhbIAKUJHnbsiudjkhiWUAHNIUDshjliuAHELIUHFILUHNIUJBDIUHwiuHushoujhdiiuwhIUHsouhdUHwiuhdUAHLsuidhlHU)"))};
	for (slices) |slice| {
		if (canProtect()) {
			try std.testing.expectError(error.Invalid, unprotect(main.stackAllocator, slice));
		}
	}
}
