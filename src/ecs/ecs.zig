const std = @import("std");

const main = @import("main");

const ZonElement = main.ZonElement;

const Entity = main.server.Entity;

pub const componentlist = @import("components/_components.zig");
pub const systemlist = @import("systems/_systems.zig");

const SparseSet = main.utils.SparseSet;

pub const Components = std.meta.DeclEnum(componentlist);
pub const Systems = std.meta.DeclEnum(systemlist);

const ComponentBitset = listToBitset(componentlist);
const ComponentSelection = listToSelection(componentlist);

var ecsArena: main.heap.NeverFailingArenaAllocator = .init(main.globalAllocator);
pub var ecsAllocator: main.heap.NeverFailingAllocator = ecsArena.allocator();

var entityTypes: SparseSet(u16, u32) = .{};

var freeEntityIds: main.ListUnmanaged(u32) = .{};
pub var componentStorage: listToSparseSets(componentlist, u32) = undefined;

var componentDefaultStorage: listToSparseSets(componentlist, u16) = undefined;
var componentBitsetStorage: [main.entity.maxEntityTypeCount]ComponentBitset = undefined;

fn listToSparseSets(comptime list: type, comptime idType: type) type {
	var outFields: [@typeInfo(list).@"struct".decls.len]std.builtin.Type.StructField = undefined;

	for (@typeInfo(list).@"struct".decls, 0..) |decl, i| {
		const name = decl.name;
		const typ = @field(list, name);
		outFields[i] = .{
			.name = name,
			.type = SparseSet(typ, idType),
			.default_value_ptr = null,
			.is_comptime = false,
			.alignment = @alignOf(SparseSet(typ, idType)),
		};
	}

	return @Type(.{.@"struct" = .{
		.layout = .auto,
        .fields = &outFields,
        .decls = &.{},
        .is_tuple = false,
	}});
}

fn listToBitset(comptime list: type) type {
	var outFields: [@typeInfo(list).@"struct".decls.len]std.builtin.Type.StructField = undefined;

	for (@typeInfo(list).@"struct".decls, 0..) |decl, i| {
		const name = decl.name;
		outFields[i] = .{
			.name = name,
			.type = bool,
			.default_value_ptr = null,
			.is_comptime = false,
			.alignment = 0,
		};
	}

	return @Type(.{.@"struct" = .{
		.layout = .@"packed",
        .fields = &outFields,
        .decls = &.{},
        .is_tuple = false,
	}});
}

fn listToSelection(comptime list: type) type {
	var outFields: [@typeInfo(list).@"struct".decls.len]std.builtin.Type.StructField = undefined;
	const defaultSelection: ?bool = null;

	for (@typeInfo(list).@"struct".decls, 0..) |decl, i| {
		const name = decl.name;
		outFields[i] = .{
			.name = name,
			.type = ?bool,
			.default_value_ptr = &defaultSelection,
			.is_comptime = false,
			.alignment = @alignOf(?bool),
		};
	}

	return @Type(.{.@"struct" = .{
		.layout = .auto,
        .fields = &outFields,
        .decls = &.{},
        .is_tuple = false,
	}});
}

pub const EntityTypeIndex = struct {
	index: u16,
};

pub const EntityIndex = struct {
	index: u16,
};

pub fn addComponent(entityType: u16, assetFolder: []const u8, id: []const u8, comptime component: Components, zon: ZonElement) void {
	const componentType = @field(componentlist, @tagName(component));

	var sparseSet = @field(componentDefaultStorage, @tagName(component));
	sparseSet.set(ecsAllocator, entityType, componentType.loadFromZon(assetFolder, id, zon));
	@field(componentBitsetStorage[entityType], @tagName(component)) = true;
}

pub fn addEntity(entityType: u16) u32 {
	const entityId: u32 = freeEntityIds.popOrNull() orelse @intCast(entityTypes.dense.items.len);
	
	inline for (@typeInfo(@TypeOf(componentStorage)).@"struct".fields) |field| {
		var default = @field(componentDefaultStorage, field.name).get(entityType) orelse return 0;
		@field(componentStorage, field.name).set(ecsAllocator, entityId, default.copy());
		@field(componentStorage, field.name).get(entityId).?.entityId = entityId;
		if (@hasField(@field(componentlist, field.name), "createFromDefaults")) {
			if (@field(componentStorage, field.name).get(entityId).?) |out| {
				out.createFromDefaults();
			}
		}
	}

	entityTypes.set(ecsAllocator, entityId, entityType);

	const list = main.ZonElement.initArray(main.stackAllocator);
	defer list.deinit(main.stackAllocator);

	const data = main.ZonElement.initObject(main.stackAllocator);
	defer data.deinit(main.stackAllocator);

	list.append(data);

	const updateData = list.toStringEfficient(main.stackAllocator, &.{});
	defer main.stackAllocator.free(updateData);

	const userList = main.server.getUserListAndIncreaseRefCount(main.stackAllocator);
	defer main.server.freeUserListAndDecreaseRefCount(main.stackAllocator, userList);
	for(userList) |user| {
		main.network.Protocols.entity.send(user.conn, updateData);
	}

	return entityId;
}

// It would be for the best if it could return based on component, but zig doesn't like it and then wants to make entity comptime
pub fn getComponent(entity: u32, comptime component: Components) *anyopaque {
	var storage = @field(componentStorage, @tagName(component));

	return storage.get(entity) orelse {
		std.log.err("Component of type {s} in entity {d} missing, returning undefined.", .{@tagName(component), entity});
		return undefined;
	};
}

fn bitsetMatchesSelection(bitset: ComponentBitset, selection: ComponentSelection) bool {
	inline for (@typeInfo(ComponentBitset).@"struct".fields) |field| {
		const expected = @field(selection, field.name);
		const selected = @field(bitset, field.name);

		if (expected == null) {
			continue;
		}

		if (selected != expected) {
			return false;
		}
	}

	return true;
}

const ViewIterator = struct {
	validTypes: [main.entity.maxEntityTypeCount]bool,
	current: u32,

	pub fn next(self: *ViewIterator) !?u32 {
		self.current +%= 1;
		while (true) : (self.current += 1) {
			if (entityTypes.get(self.current)) |entityType| {
				if (self.validTypes[entityType]) {
					return self.current;
				}
			} else if (self.current >= entityTypes.dense.items.len) {
				return null;
			}
		}
	}
};

pub fn selectAll(selection: ComponentSelection) ViewIterator {
	var validTypes: [main.entity.maxEntityTypeCount]bool = undefined;
	for (0..main.entity.numRegisteredEntites()) |i| {
		validTypes[i] = bitsetMatchesSelection(componentBitsetStorage[i], selection);
	}
	
	return .{
		.validTypes = validTypes,
		.current = std.math.maxInt(u32),
	};
}

pub fn init() void {}

pub fn deinit() void {
	ecsArena.deinit();
}

pub fn finalize() void {
	inline for (@typeInfo(@TypeOf(componentDefaultStorage)).@"struct".fields) |field| {
		if (@hasField(@field(componentlist, field.name), "finalize")) {
			@field(componentlist, field.name).finalize();
		}
	}
}