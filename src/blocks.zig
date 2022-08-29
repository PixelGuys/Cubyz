const std = @import("std");

const JsonElement = @import("json.zig").JsonElement;

pub const BlockClass = enum(u8) {
	wood,
	stone,
	sand,
	unbreakable,
	leaf,
	fluid,
	air
};

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var allocator = arena.allocator();

pub const MaxBLockCount: usize = 65536; // 16 bit limit

pub const BlockDrop = u0; // TODO!
pub const RotationMode = u0; // TODO!

var _lightingTransparent: [MaxBLockCount]bool = undefined;
var _transparent: [MaxBLockCount]bool = undefined;
var _id: [MaxBLockCount][]u8 = undefined;
/// Time in seconds to break this block by hand.
var _hardness: [MaxBLockCount]f32 = undefined;
/// Minimum pickaxe/axe/shovel power required.
var _breakingPower: [MaxBLockCount]f32 = undefined;
var _solid: [MaxBLockCount]bool = undefined;
var _selectable: [MaxBLockCount]bool = undefined;
var _blockDrops: [MaxBLockCount][]BlockDrop = undefined;
/// Meaning undegradable parts of trees or other structures can grow through this block.
var _degradable: [MaxBLockCount]bool = undefined;
var _viewThrough: [MaxBLockCount]bool = undefined;
var _blockClass: [MaxBLockCount]BlockClass = undefined;
var _light: [MaxBLockCount]u32 = undefined;
/// How much light this block absorbs if it is transparent
var _absorption: [MaxBLockCount]u32 = undefined;
/// GUI that is opened on click.
var _gui: [MaxBLockCount][]u8 = undefined;
var _mode: [MaxBLockCount]RotationMode = undefined;

var reverseIndices = std.StringHashMap(u16).init(arena.allocator());

var size: u32 = 0;

pub fn register(id: []const u8, json: JsonElement) !void {
	if(reverseIndices.contains(id)) {
		std.log.warn("Registered block with id {s} twice!", .{id});
	}
	_id[size] = try allocator.dupe(u8, id);
	try reverseIndices.put(_id[size], @intCast(u16, size));
//		TODO:
//		_mode[size] = CubyzRegistries.ROTATION_MODE_REGISTRY.getByID(json.getString("rotation", "cubyz:no_rotation"));
//		_blockDrops[size] = new BlockDrop[0];
	_breakingPower[size] = json.get(f32, "breakingPower", 0);
	_hardness[size] = json.get(f32, "hardness", 1);

	var blockClassString = json.get([]const u8, "class", "stone");
	_blockClass[size] = .stone;
	inline for(@typeInfo(BlockClass).Enum.fields) |field| {
		if(std.mem.eql(u8, blockClassString, field.name)) {
			_blockClass[size] = @field(BlockClass, field.name);
		}
	}
	_light[size] = json.get(u32, "emittedLight", 0);
	_absorption[size] = json.get(u32, "absorbedLight", 0);
	_lightingTransparent[size] = json.getChild("absorbedLight") != .JsonNull;
	_degradable[size] = json.get(bool, "degradable", false);
	_selectable[size] = json.get(bool, "selectable", true);
	_solid[size] = json.get(bool, "solid", true);
	_gui[size] = try allocator.dupe(u8, json.get([]const u8, "GUI", ""));
	_transparent[size] = json.get(bool, "transparent", false);
	_viewThrough[size] = json.get(bool, "viewThrough", false) or _transparent[size];

	size += 1;
}

pub fn reset() void {
	size = 0;
	// TODO: Use arena.reset() instead.
	arena.deinit();
	arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
	reverseIndices = std.StringHashMap([]const u8).init(arena);
}

pub fn getByID(id: []const u8) u16 {
	if(reverseIndices.get(id)) |result| {
		return result;
	} else {
		std.log.warn("Couldn't find block {s}. Replacing it with air...", .{id});
		return 0;
	}
}

pub const Block = struct {
	typ: u16,
	data: u16,
	pub fn lightingTransparent(self: Block) bool {
		return _lightingTransparent[self.typ];
	}

	pub fn transparent(self: Block) bool {
		return _transparent[self.typ];
	}

	pub fn id(self: Block) []u8 {
		return _id[self.typ];
	}

	/// Time in seconds to break this block by hand.
	pub fn hardness(self: Block) f32 {
		return _hardness[self.typ];
	}

	/// Minimum pickaxe/axe/shovel power required.
	pub fn breakingPower(self: Block) f32 {
		return _breakingPower[self.typ];
	}

	pub fn solid(self: Block) bool {
		return _solid[self.typ];
	}

	pub fn selectable(self: Block) bool {
		return _selectable[self.typ];
	}

	pub fn blockDrops(self: Block) []BlockDrop {
		return _blockDrops[self.typ];
	}

	/// Meaning undegradable parts of trees or other structures can grow through this block.
	pub fn degradable(self: Block) bool {
		return _degradable[self.typ];
	}

	pub fn viewThrough(self: Block) bool {
		return _viewThrough[self.typ];
	}

	pub fn blockClass(self: Block) BlockClass {
		return _blockClass[self.typ];
	}

	pub fn light(self: Block) u32 {
		return _light[self.typ];
	}

	/// How much light this block absorbs if it is transparent.
	pub fn absorption(self: Block) u32 {
		return _absorption[self.typ];
	}
	
	/// GUI that is opened on click.
	pub fn gui(self: Block) []u8 {
		return _gui[self.typ];
	}
	
	pub fn mode(self: Block) RotationMode {
		return _mode[self.typ];
	}

//	TODO:
//	/**
//	 * Fires the blocks on click event(usually nothing or GUI opening).
//	 * @param world
//	 * @param pos
//	 * @return if the block did something on click.
//	 */
//	public static boolean onClick(int block, World world, Vector3i pos) {
//		if (gui[block & TYPE_MASK] != null) {
//			GameLauncher.logic.openGUI("cubyz:workbench", new Inventory(26)); // TODO: Care about the inventory.
//			return true;
//		}
//		return false;
//	}
};
