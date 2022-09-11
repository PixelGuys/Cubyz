const std = @import("std");

const main = @import("main.zig");

pub const Compression = struct {
	pub fn pack(sourceDir: std.fs.IterableDir, writer: anytype) !void {
		var comp = try std.compress.deflate.compressor(main.threadAllocator, writer, .{.level = .no_compression});
		defer comp.deinit();
		var walker = try sourceDir.walk(main.threadAllocator);
		defer walker.deinit();

		while(try walker.next()) |entry| {
			if(entry.kind == .File) {
				var relPath = entry.path;
				var len: [4]u8 = undefined;
				std.mem.writeIntBig(u32, &len, @intCast(u32, relPath.len));
				_ = try comp.write(&len);
				_ = try comp.write(relPath);

				var file = try sourceDir.dir.openFile(relPath, .{});
				defer file.close();
				var fileData = try file.readToEndAlloc(main.threadAllocator, std.math.maxInt(u32));
				defer main.threadAllocator.free(fileData);

				std.mem.writeIntBig(u32, &len, @intCast(u32, fileData.len));
				_ = try comp.write(&len);
				_ = try comp.write(fileData);
			}
		}
		try comp.close();
	}

	pub fn unpack(outDir: std.fs.Dir, input: []const u8) !void {
		var stream = std.io.fixedBufferStream(input);
		var decomp = try std.compress.deflate.decompressor(main.threadAllocator, stream.reader(), null);
		defer decomp.deinit();
		var reader = decomp.reader();
		const _data = try reader.readAllAlloc(main.threadAllocator, std.math.maxInt(usize));
		defer main.threadAllocator.free(_data);
		var data = _data;
		while(data.len != 0) {
			var len = std.mem.readIntBig(u32, data[0..4]);
			data = data[4..];
			var path = data[0..len];
			data = data[len..];
			len = std.mem.readIntBig(u32, data[0..4]);
			data = data[4..];
			var fileData = data[0..len];
			data = data[len..];

			var splitter = std.mem.splitBackwards(u8, path, "/");
			_ = splitter.first();
			try outDir.makePath(splitter.rest());
			var file = try outDir.createFile(path, .{});
			defer file.close();
			try file.writeAll(fileData);
		}
	}
//	public static void pack(String sourceDirPath, OutputStream outputstream){
//		try {
//			DeflaterOutputStream compressedOut = new DeflaterOutputStream(outputstream);
//			Path path = Paths.get(sourceDirPath);
//			Files.walk(path)
//					.filter(p -> !Files.isDirectory(p)) // potential bug
//					.forEach(p -> {
//						String relPath = path.relativize(p).toString();
//						try {
//							byte[] strData = relPath.getBytes(StandardCharsets.UTF_8);
//							byte[] len = new byte[4];
//							Bits.putInt(len, 0, strData.length);
//							compressedOut.write(len);
//							compressedOut.write(strData);
//							byte[] file = Files.readAllBytes(p);
//							Bits.putInt(len, 0, file.length);
//							compressedOut.write(len);
//							compressedOut.write(file);
//						} catch (IOException e) {
//							Logger.error(e);
//						}
//					});
//			compressedOut.close();
//		}catch(IOException exception){
//			Logger.error(exception);
//		}
//	}
//	public static void unpack(String outputFolderPath, InputStream inputStream){
//		try {
//			File outputFolder = new File(outputFolderPath);
//			if (!outputFolder.exists()) {
//				outputFolder.mkdir();
//			}
//			InflaterInputStream compressedIn = new InflaterInputStream(inputStream);
//			while(compressedIn.available() != 0) {
//				byte[] len = compressedIn.readNBytes(4);
//				byte[] pathBytes = compressedIn.readNBytes(Bits.getInt(len ,0));
//				String path = new String(pathBytes, StandardCharsets.UTF_8);
//				String filePath = outputFolder.getAbsolutePath() + File.separator + path;
//				len = compressedIn.readNBytes(4);
//				byte[] fileBytes = compressedIn.readNBytes(Bits.getInt(len ,0));
//				new File(filePath).getParentFile().mkdirs();
//				BufferedOutputStream bos = new BufferedOutputStream(new FileOutputStream(filePath));
//				bos.write(fileBytes, 0, fileBytes.length);
//				bos.close();
//			}
//			compressedIn.close();
//		}catch (Exception e){
//			Logger.error(e);
//		}
//	}
};