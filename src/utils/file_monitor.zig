const std = @import("std");
const builtin = @import("builtin");

const main = @import("main");

const CallbackFunction = *const fn(usize) void;

const Impl = if(builtin.os.tag == .windows)
	WindowsImpl
else if(builtin.os.tag == .linux)
	LinuxImpl
else
	NoImpl;

pub fn init() void {
	Impl.init();
}

pub fn deinit() void {
	Impl.deinit();
}

pub fn handleEvents() void {
	Impl.handleEvents();
}

pub fn listenToPath(path: [:0]const u8, callback: CallbackFunction, userData: usize) void {
	Impl.listenToPath(path, callback, userData);
}

pub fn removePath(path: [:0]const u8) void {
	Impl.removePath(path);
}

const NoImpl = struct {
	fn init() void {}
	fn deinit() void {}
	fn handleEvents() void {}
	fn listenToPath(_: [:0]const u8, _: CallbackFunction, _: usize) void {}
	fn removePath(_: [:0]const u8) void {}
};

const LinuxImpl = struct { // MARK: LinuxImpl
	const c = @cImport({
		@cInclude("sys/inotify.h");
		@cInclude("sys/ioctl.h");
		@cInclude("unistd.h");
		@cInclude("errno.h");
	});

	const DirectoryInfo = struct {
		callback: CallbackFunction,
		userData: usize,
		watchDescriptors: main.ListUnmanaged(c_int),
		needsUpdate: bool,
		path: []const u8,
	};

	var fd: c_int = undefined;
	var watchDescriptors: std.StringHashMap(*DirectoryInfo) = undefined;
	var callbacks: std.AutoHashMap(c_int, *DirectoryInfo) = undefined;
	var mutex: std.Thread.Mutex = .{};

	fn init() void {
		fd = c.inotify_init();
		if(fd == -1) {
			std.log.err("Error while initializing inotifiy: {}", .{std.posix.errno(fd)});
		}
		watchDescriptors = .init(main.globalAllocator.allocator);
		callbacks = .init(main.globalAllocator.allocator);
	}

	fn deinit() void {
		const result = c.close(fd);
		if(result == -1) {
			std.log.err("Error while closing file descriptor: {}", .{std.posix.errno(result)});
		}
		var iterator = watchDescriptors.iterator();
		while(iterator.next()) |entry| {
			main.globalAllocator.free(entry.key_ptr.*);
			entry.value_ptr.*.watchDescriptors.deinit(main.globalAllocator);
			main.globalAllocator.destroy(entry.value_ptr.*);
		}
		watchDescriptors.deinit();
		callbacks.deinit();
	}

	fn addWatchDescriptorsRecursive(info: *DirectoryInfo, path: []const u8) void {
		main.utils.assertLocked(&mutex);
		var iterableDir = std.fs.cwd().openDir(path, .{.iterate = true}) catch |err| {
			std.log.err("Error while opening dirs {s}: {s}", .{path, @errorName(err)});
			return;
		};
		defer iterableDir.close();
		var iterator = iterableDir.iterate();
		while(iterator.next() catch |err| {
			std.log.err("Error while iterating dir {s}: {s}", .{path, @errorName(err)});
			return;
		}) |entry| {
			if(entry.kind == .directory) {
				const subPath = std.fmt.allocPrintZ(main.stackAllocator.allocator, "{s}/{s}", .{path, entry.name}) catch unreachable;
				defer main.stackAllocator.free(subPath);
				addWatchDescriptor(info, subPath);
				addWatchDescriptorsRecursive(info, subPath);
			}
		}
	}

	fn updateRecursiveCallback(info: *DirectoryInfo) void {
		main.utils.assertLocked(&mutex);
		for(info.watchDescriptors.items[1..]) |watchDescriptor| {
			removeWatchDescriptor(watchDescriptor, info.path);
		}
		info.watchDescriptors.items.len = 1;
		addWatchDescriptorsRecursive(info, info.path);
	}

	fn handleEvents() void {
		mutex.lock();
		defer mutex.unlock();
		var available: c_uint = 0;
		const result = c.ioctl(fd, c.FIONREAD, &available);
		if(result == -1) {
			std.log.err("Error while checking the number of available bytes for the inotify file descriptor: {}", .{std.posix.errno(result)});
		}
		if(available == 0) return;
		const events: []u8 = main.stackAllocator.alloc(u8, available);
		defer main.stackAllocator.free(events);
		const readBytes = c.read(fd, events.ptr, available);
		if(readBytes == -1) {
			std.log.err("Error while reading inotify event: {}", .{std.posix.errno(readBytes)});
			return;
		}
		var triggeredCallbacks = std.AutoHashMap(*DirectoryInfo, void).init(main.stackAllocator.allocator); // Avoid duplicate calls
		defer triggeredCallbacks.deinit();
		var offset: usize = 0;
		while(offset < available) {
			const eventPtr: *const c.inotify_event = @alignCast(@ptrCast(events.ptr[offset..]));
			defer offset += @sizeOf(c.inotify_event) + eventPtr.len;

			const callback = callbacks.get(eventPtr.wd) orelse continue;
			if(eventPtr.mask & c.IN_ISDIR != 0) callback.needsUpdate = true;
			_ = triggeredCallbacks.getOrPut(callback) catch unreachable;
		}
		var iterator = triggeredCallbacks.keyIterator();
		while(iterator.next()) |callback| {
			if(callback.*.needsUpdate) {
				callback.*.needsUpdate = false;
				updateRecursiveCallback(callback.*);
			}
			mutex.unlock();
			callback.*.callback(callback.*.userData);
			mutex.lock();
		}
	}

	fn addWatchDescriptor(info: *DirectoryInfo, path: [:0]const u8) void {
		main.utils.assertLocked(&mutex);
		const watchDescriptor = c.inotify_add_watch(fd, path.ptr, c.IN_CLOSE_WRITE | c.IN_DELETE | c.IN_CREATE | c.IN_MOVE | c.IN_ONLYDIR);
		if(watchDescriptor == -1) {
			std.log.err("Error while adding watch descriptor for path {s}: {}", .{path, std.posix.errno(watchDescriptor)});
		}
		callbacks.put(watchDescriptor, info) catch unreachable;
		info.watchDescriptors.append(main.globalAllocator, watchDescriptor);
	}

	fn removeWatchDescriptor(watchDescriptor: c_int, path: []const u8) void {
		main.utils.assertLocked(&mutex);
		_ = callbacks.remove(watchDescriptor);
		const result = c.inotify_rm_watch(fd, watchDescriptor);
		if(result == -1) {
			const err = std.posix.errno(result);
			if(err != .INVAL) std.log.err("Error while removing watch descriptors for path {s}: {}", .{path, err});
		}
	}

	fn listenToPath(path: [:0]const u8, callback: CallbackFunction, userData: usize) void {
		mutex.lock();
		defer mutex.unlock();
		if(watchDescriptors.contains(path)) {
			std.log.err("Tried to add duplicate watch descriptor for path {s}", .{path});
			return;
		}
		const callbackInfo = main.globalAllocator.create(DirectoryInfo);
		callbackInfo.* = .{
			.callback = callback,
			.userData = userData,
			.watchDescriptors = .{},
			.path = main.globalAllocator.dupe(u8, path),
			.needsUpdate = false,
		};
		watchDescriptors.putNoClobber(callbackInfo.path, callbackInfo) catch unreachable;
		addWatchDescriptor(callbackInfo, path);
		updateRecursiveCallback(callbackInfo);
	}

	fn removePath(path: [:0]const u8) void {
		mutex.lock();
		defer mutex.unlock();
		if(watchDescriptors.fetchRemove(path)) |kv| {
			for(kv.value.watchDescriptors.items) |watchDescriptor| {
				removeWatchDescriptor(watchDescriptor, path);
			}
			main.globalAllocator.free(kv.key);
			kv.value.watchDescriptors.deinit(main.globalAllocator);
			main.globalAllocator.destroy(kv.value);
		} else {
			std.log.err("Tried to remove non-existent watch descriptor for path {s}", .{path});
		}
	}
};

const WindowsImpl = struct { // MARK: WindowsImpl
	const c = @cImport({
		@cInclude("fileapi.h");
	});
	const HANDLE = std.os.windows.HANDLE;
	var notificationHandlers: std.StringHashMap(*DirectoryInfo) = undefined;
	var callbacks: main.List(*DirectoryInfo) = undefined;
	var justTheHandles: main.List(HANDLE) = undefined;
	var mutex: std.Thread.Mutex = .{};

	const DirectoryInfo = struct {
		callback: CallbackFunction,
		userData: usize,
		notificationHandler: HANDLE,
		needsUpdate: bool,
		path: []const u8,
	};

	fn init() void {
		notificationHandlers = .init(main.globalAllocator.allocator);
		callbacks = .init(main.globalAllocator);
		justTheHandles = .init(main.globalAllocator);
	}

	fn deinit() void {
		var iterator = notificationHandlers.iterator();
		while(iterator.next()) |entry| {
			main.globalAllocator.free(entry.key_ptr.*);
			main.globalAllocator.destroy(entry.value_ptr.*);
		}
		notificationHandlers.deinit();
		callbacks.deinit();
		justTheHandles.deinit();
	}

	fn handleEvents() void {
		mutex.lock();
		defer mutex.unlock();
		while(true) {
			if(justTheHandles.items.len == 0) break;
			const waitResult = std.os.windows.kernel32.WaitForMultipleObjects(@intCast(justTheHandles.items.len), justTheHandles.items.ptr, @intFromBool(false), 0);
			if(waitResult == std.os.windows.WAIT_TIMEOUT) break;
			if(waitResult == std.os.windows.WAIT_FAILED) {
				std.log.err("Error while waiting: {}", .{std.os.windows.kernel32.GetLastError()});
				break;
			}
			if(waitResult < std.os.windows.WAIT_OBJECT_0 or waitResult - std.os.windows.WAIT_OBJECT_0 >= justTheHandles.items.len) {
				std.log.err("Windows gave an unexpected wait result: {}", .{waitResult});
				break;
			}
			const callbackInfo = callbacks.items[@intCast(waitResult - std.os.windows.WAIT_OBJECT_0)];
			const result = c.FindNextChangeNotification(callbackInfo.notificationHandler);
			if(result == 0) {
				std.log.err("Error on FindNextChangeNotification for path {s}: {}", .{callbackInfo.path, result});
			}
			mutex.unlock();
			callbackInfo.callback(callbackInfo.userData);
			mutex.lock();
		}
	}

	fn listenToPath(path: [:0]const u8, callback: CallbackFunction, userData: usize) void {
		mutex.lock();
		defer mutex.unlock();
		if(notificationHandlers.contains(path)) {
			std.log.err("Tried to add duplicate notification handler for path {s}", .{path});
			return;
		}
		const handle = c.FindFirstChangeNotificationA(path.ptr, @intFromBool(true), c.FILE_NOTIFY_CHANGE_LAST_WRITE);
		if(handle == std.os.windows.INVALID_HANDLE_VALUE) {
			std.log.err("Got error while creating notification handler for path {s}: {}", .{path, std.os.windows.kernel32.GetLastError()});
		}

		const callbackInfo = main.globalAllocator.create(DirectoryInfo);
		callbackInfo.* = .{
			.callback = callback,
			.userData = userData,
			.notificationHandler = handle.?,
			.path = main.globalAllocator.dupe(u8, path),
			.needsUpdate = false,
		};
		notificationHandlers.putNoClobber(callbackInfo.path, callbackInfo) catch unreachable;
		callbacks.append(callbackInfo);
		justTheHandles.append(callbackInfo.notificationHandler);
	}

	fn removePath(path: [:0]const u8) void {
		mutex.lock();
		defer mutex.unlock();
		if(notificationHandlers.fetchRemove(path)) |kv| {
			const index = std.mem.indexOfScalar(*DirectoryInfo, callbacks.items, kv.value).?;
			_ = callbacks.swapRemove(index);
			_ = justTheHandles.swapRemove(index);
			if(c.FindCloseChangeNotification(kv.value.notificationHandler) == 0) {
				std.log.err("Error while closing notification handler for path {s}: {}", .{path, std.os.windows.kernel32.GetLastError()});
			}
			main.globalAllocator.free(kv.key);
			main.globalAllocator.destroy(kv.value);
		} else {
			std.log.err("Tried to remove non-existent notification handler for path {s}", .{path});
		}
	}
};
