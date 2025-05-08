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
const ComponentIds = listToIds(componentlist);
const ComponentSelection = listToSelection(componentlist);

var ecsArena: main.heap.NeverFailingArenaAllocator = .init(main.globalAllocator);
pub var ecsAllocator: main.heap.NeverFailingAllocator = ecsArena.allocator();

var entityTypes: SparseSet(u16, u16) = .{};

pub var componentStorage: listToSparseSets(componentlist, u16) = undefined;
var componentIdStorage: SparseSet(ComponentIds, u32) = .{};

var componentDefaultStorage: listToSparseSets(componentlist, u16) = .{};
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

fn listToIds(comptime list: type) type {
	var outFields: [@typeInfo(list).@"struct".decls.len]std.builtin.Type.StructField = undefined;
	const noId: u16 = std.math.maxInt(u16);

	for (@typeInfo(list).@"struct".decls, 0..) |decl, i| {
		const name = decl.name;
		outFields[i] = .{
			.name = name,
			.type = u16,
			.default_value_ptr = &noId,
			.is_comptime = false,
			.alignment = @alignOf(u16),
		};
	}

	return @Type(.{.@"struct" = .{
		.layout = .auto,
        .fields = outFields[0..],
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
	if (sparseSet.sparse.items.len < entityType) {
		sparseSet.sparse.appendNTimes(ecsAllocator, @TypeOf(sparseSet).noValue, entityType - sparseSet.sparse.items.len);
	}

	_ = sparseSet.add(ecsAllocator, componentType.loadFromZon(assetFolder, id, zon));
	@field(componentBitsetStorage[entityType], @tagName(component)) = true;
}

pub fn addEntity(entityType: u16) u32 {
	const entityId = componentIdStorage.add(.{});
	var idsPtr = componentIdStorage.get(entityId) catch return 0;

	inline for (@typeInfo(@TypeOf(componentStorage)).@"struct".fields) |field| {
		var default = @field(componentDefaultStorage, field.name).get(entityType) catch return 0;
		const id = @field(componentStorage, field.name).add(default.copy());
		if (@hasField(@field(componentlist, field.name), "createFromDefaults")) {
			if (@field(componentStorage, field.name).get(id) catch continue) |out| {
				out.createFromDefaults(entityId);
			}
		}
		@field(idsPtr, field.name) = id;
	}

	_ = entityTypes.add(entityType);

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
pub fn getComponent(entity: u32, comptime component: Components) *align(32) anyopaque {
	const idStorage = componentIdStorage.get(entity) catch {
		std.log.err("Failed to get component {s} from entity {d}, returning undefined.", .{@tagName(component), entity});
		return undefined;
	};

	const id = @field(idStorage, @tagName(component));

	if (id == std.math.maxInt(u16)) {
		std.log.err("Entity {d} does not have component {s}, returning undefined.", .{entity, @tagName(component)});
		return undefined;
	}

	var storage = @field(componentStorage, @tagName(component));

	return storage.get(id) catch {
		std.log.err("Component of type {s} with id {d} missing, returning undefined.", .{@tagName(component), id});
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
			if (entityTypes.get(self.current) catch |err| {
				switch (err) {
					.idOutOfBounds => return null,
					.valueDoesntExist => continue,
				}
			}) {
				if (self.validTypes[try entityTypes.get(self.current)]) {
					return self.current;
				}
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

pub fn init() void {
	inline for (@typeInfo(@TypeOf(componentStorage)).@"struct".fields) |field| {
		@field(componentStorage, field.name) = .init(ecsAllocator);
	}

	inline for (@typeInfo(@TypeOf(componentDefaultStorage)).@"struct".fields) |field| {
		@field(componentDefaultStorage, field.name) = .init(ecsAllocator);
	}

	componentIdStorage = .init(ecsAllocator);
	entityTypes = .init(ecsAllocator);
}

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