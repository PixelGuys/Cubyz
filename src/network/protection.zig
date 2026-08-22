const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const builtin = @import("builtin");

const c = @import("c");

const impl = switch (builtin.os.tag) {
	.windows => windows_impl,
	else => no_impl,
};

pub const canProtect: bool = impl.canProtect;

pub fn protect(allocator: NeverFailingAllocator, data: []const u8) error{ SystemError, Unsupported }![]u8 {
	return impl.protect(allocator, data);
}

pub fn unprotect(allocator: NeverFailingAllocator, data: []const u8) error{ SystemError, Invalid }![]u8 {
	return impl.unprotect(allocator, data);
}

const no_impl = struct {
	const canProtect = false;

	fn protect(_: NeverFailingAllocator, _: []const u8) error{ SystemError, Unsupported }![]u8 {
		return error.Unsupported;
	}

	fn unprotect(_: NeverFailingAllocator, _: []const u8) error{ SystemError, Invalid }![]u8 {
		return error.Invalid;
	}
};

const windows_impl = struct {
	const canProtect = true;

	fn protect(allocator: NeverFailingAllocator, data: []const u8) error{ SystemError, Unsupported }![]u8 {
		var plainblob: c.DATA_BLOB = .{
			.cbData = @intCast(data.len),
			.pbData = @constCast(data.ptr),
		};
		var cipherblob: c.DATA_BLOB = undefined;
		if (c.CryptProtectData(&plainblob, null, null, null, null, 0, &cipherblob) == 0) {
			std.log.err("CryptProtectData syscall failed. Errorcode: {}. This should never happen. Please report it to the maintainers.", .{c.GetLastError()});
			return error.SystemError;
		}
		defer if (c.LocalFree(cipherblob.pbData) != null) std.log.err("LocalFree syscall failed to free previously allocated memory. Errorcode: {}. This should never happen. Please report it to the maintainers.", .{c.GetLastError()});
		return allocator.dupe(u8, cipherblob.pbData[0..cipherblob.cbData]);
	}

	fn unprotect(allocator: NeverFailingAllocator, data: []const u8) error{ SystemError, Invalid }![]u8 {
		var plainblob: c.DATA_BLOB = undefined;
		var cipherblob: c.DATA_BLOB = .{
			.cbData = @intCast(data.len),
			.pbData = @constCast(data.ptr),
		};
		if (c.CryptUnprotectData(&cipherblob, null, null, null, null, 0, &plainblob) == 0) {
			const err = c.GetLastError();
			switch (err) {
				c.ERROR_INVALID_DATA, c.ERROR_INVALID_PARAMETER => return error.Invalid,
				else => {
					std.log.err("CryptUnprotectData syscall failed. Errorcode: {}", .{err});
					return error.SystemError;
				},
			}
		}
		var pbDataSlice: []u8 = undefined;
		pbDataSlice.len = plainblob.cbData;
		pbDataSlice.ptr = plainblob.pbData;
		defer {
			std.crypto.secureZero(u8, pbDataSlice);
			if (c.LocalFree(plainblob.pbData) != null) std.log.err("LocalFree syscall failed to free previously allocated memory. Errorcode: {}. This should never happen. Please report it to the maintainers.", .{c.GetLastError()});
		}
		return allocator.dupe(u8, plainblob.pbData[0..plainblob.cbData]);
	}
};

test "slice==unprotect(protect(slice))" {
	if (canProtect) {
		const slices: [5][]const u8 = .{"TestdwadadÖOUWHdöouHIOSUdhöoUHNWLJDKNOÖPAHUIwdoöJKNSdlkjöwuHOÖIhso8zpo9IKj", "Test", "Testd", "", "WIJDp8iU)(du098UÜ=JHd0ü8hz=Ü(HJ0isidjowi8h=(Z\"ß08IJUISdhd0w98hdoi8uoIWUJDoikjsoIKHJOwiuhdOISHNdo9i8H(UIHNASUJhdnbiuJBWGiudjhbIAKUJHnbsiudjkhiWUAHNIUDshjliuAHELIUHFILUHNIUJBDIUHwiuHushoujhdiiuwhIUHsouhdUHwiuhdUAHLsuidhlHU)"};
		for (slices) |slice| {
			const protected = try protect(main.stackAllocator, slice);
			defer main.stackAllocator.free(protected);
			const unprotected = try unprotect(main.stackAllocator, protected);
			defer main.stackAllocator.free(unprotected);
			try std.testing.expectEqualSlices(u8, slice, unprotected);
		}
	} else {
		return error.SkipZigTest;
	}
}

test "Protect fails on unsupported platforms" {
	const slice = "Test";
	if (!canProtect) {
		try std.testing.expectError(error.Unsupported, protect(main.stackAllocator, slice));
		try std.testing.expectError(error.Invalid, unprotect(main.stackAllocator, slice));
	} else {
		return error.SkipZigTest;
	}
}

test "Unprotect fails when supplied with garbage" {
	if (canProtect) {
		const slices: [5][]const u8 = .{"TestdwadadÖOUWHdöouHIOSUdhöoUHNWLJDKNOÖPAHUIwdoöJKNSdlkjöwuHOÖIhso8zpo9IKj", "Test", "Testd", "", "WIJDp8iU)(du098UÜ=JHd0ü8hz=Ü(HJ0isidjowi8h=(Z\"ß08IJUISdhd0w98hdoi8uoIWUJDoikjsoIKHJOwiuhdOISHNdo9i8H(UIHNASUJhdnbiuJBWGiudjhbIAKUJHnbsiudjkhiWUAHNIUDshjliuAHELIUHFILUHNIUJBDIUHwiuHushoujhdiiuwhIUHsouhdUHwiuhdUAHLsuidhlHU)"};
		for (slices) |slice| {
			try std.testing.expectError(error.Invalid, unprotect(main.stackAllocator, slice));
		}
	} else {
		return error.SkipZigTest;
	}
}
