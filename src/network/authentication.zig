const std = @import("std");

const main = @import("main");

var wordlist: ?[2048][]const u8 = null;

fn wordToIndex(word: []const u8) ?u11 {
	if (wordlist == null) return null;
	for (wordlist.?, 0..) |other, i| {
		if (std.mem.eql(u8, word, other)) {
			return @intCast(i);
		}
	}
	return null;
}

pub fn init() void {
	const wordlistString = main.files.cwd().read(main.globalArena, "assets/cubyz/wordlist") catch |err| {
		std.log.err("Got error while reading word list: {s}", .{@errorName(err)});
		return;
	};
	var splitIterator = std.mem.splitScalar(u8, wordlistString, '\n');
	wordlist = @splat(&.{});
	var i: usize = 0;
	while (splitIterator.next()) |word| {
		wordlist.?[i] = word;
		i += 1;
	}
}

pub const SeedPhrase = struct {
	text: []u8,

	pub fn initFromUserInput(text: []const u8, failureText: *main.List(u8)) SeedPhrase {
		var result: main.ListUnmanaged(u8) = .initCapacity(main.stackAllocator, text.len);
		defer result.deinit(main.stackAllocator);
		defer @memset(result.items, 0);

		for (text) |char| {
			if (std.ascii.isAlphabetic(char)) {
				result.appendAssumeCapacity(std.ascii.toLower(char));
			} else if (std.ascii.isWhitespace(char)) {
				if(result.items.len != 0 and result.items[result.items.len - 1] != ' ') {
					result.appendAssumeCapacity(char);
				}
			} else {
				failureText.print("Seed phrase contains invalid character '{c}', only ASCII letters and whitespaces are allowed\n", .{char});
			}
		}
		if(result.items[result.items.len - 1] == ' ') _ = result.pop();

		var split = std.mem.splitScalar(u8, result.items, ' ');
		var wordCount: usize = 0;
		var bits: [21]u8 = @splat(0);
		defer @memset(&bits, 0);
		var failedWordlist: bool = false;
		while (split.next()) |word| {
			wordCount += 1;
			if (wordToIndex(word)) |wordIndex| {
				if(wordCount <= 15) {
					const bitIndex = (wordCount - 1)*11;
					const byteIndex = bitIndex/8;
					const containingRegion: usize = @as(usize, wordIndex) << @intCast(8*3 - 11 - bitIndex%8);

					bits[byteIndex] |= @truncate(containingRegion >> 16);
					bits[byteIndex + 1] |= @truncate(containingRegion >> 8);
					if (byteIndex + 2 < bits.len) bits[byteIndex + 2] |= @truncate(containingRegion);
				}
			} else {
				failureText.print("The {}{s} word of the seed phrase is not a part of the wordlist.\n", .{wordCount, if (wordCount == 1) "st" else if (wordCount == 2) "nd" else if (wordCount == 3) "rd" else "th"});
				failedWordlist = true;
			}
		}

		if (wordCount != 15) {
			failureText.print("The seed phrase contains an invalid number of words. Should be 16.\n", .{});
			failedWordlist = true;
		}

		if(!failedWordlist) {
			var sha256Result: [32]u8 = undefined;
			defer @memset(&sha256Result, 0);
			std.crypto.hash.sha2.Sha256.hash(bits[0..20], &sha256Result, .{});
			if(sha256Result[0] >> 3 != bits[20] >> 3) {
				failureText.print("The seed phrase has an incorrect checksum.\n", .{});
			}
		}

		// TODO: Checksum check

		return .{
			.text = main.globalAllocator.dupe(u8, result.items),
		};
	}

	pub fn initRandomly() SeedPhrase {
		if(wordlist == null) @panic("Cannot generate new Account without a valid wordlist.");
		var bits: [21]u8 = undefined;
		defer @memset(&bits, 0);
		std.crypto.random.bytes(bits[0..20]);
		var sha256Result: [32]u8 = undefined;
		defer @memset(&sha256Result, 0);
		std.crypto.hash.sha2.Sha256.hash(bits[0..20], &sha256Result, .{});
		bits[20] = sha256Result[0];

		var result: main.ListUnmanaged(u8) = .{};
		defer result.deinit(main.stackAllocator);
		defer @memset(result.items, 0);

		for (0..15) |i| {
			const bitIndex = i*11;
			const byteIndex = bitIndex/8;

			const containingRegion = @as(usize, bits[byteIndex]) << 16 | @as(usize, bits[byteIndex + 1]) << 8 | if (byteIndex + 2 < bits.len) bits[byteIndex + 2] else 0;
			const wordIndex: u11 = @truncate(containingRegion >> @intCast(8*3 - 11 - bitIndex%8));

			if(i != 0) result.append(main.stackAllocator, ' ');
			result.appendSlice(main.stackAllocator, wordlist.?[wordIndex]);
		}

		return .{
			.text = main.globalAllocator.dupe(u8, result.items),
		};
	}

	pub fn deinit(self: SeedPhrase) void {
		@memset(self.text, 0);
		main.globalAllocator.free(self.text);
	}
};