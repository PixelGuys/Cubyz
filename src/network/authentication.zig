const std = @import("std");

const main = @import("main");

var wordlist: ?[2048][]const u8 = null;

fn hasWord(word: []const u8) bool {
	if (wordlist == null) return false;
	for (wordlist.?) |other| {
		if (std.mem.eql(u8, word, other)) {
			return true;
		}
	}
	return false;
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
		while (split.next()) |word| {
			wordCount += 1;
			if (!hasWord(word)) {
				failureText.print("The {}{s} word of the seed phrase is not a part of the wordlist.\n", .{wordCount, if (wordCount == 1) "st" else if (wordCount == 2) "nd" else if (wordCount == 3) "rd" else "th"});
			}
		}

		if (wordCount != 16) { // TODO: Decide on a count
			failureText.print("The seed phrase contains an invalid number of words. Should be 16.\n", .{});
		}

		// TODO: Checksum check

		return .{
			.text = main.globalAllocator.dupe(u8, result.items),
		};
	}

	pub fn deinit(self: SeedPhrase) void {
		@memset(self.text, 0);
		main.globalAllocator.free(self.text);
	}
};