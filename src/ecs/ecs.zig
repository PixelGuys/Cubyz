const main = @import("main");

const components = @import("components/_components.zig");

const Health = components.Health;
const Model = components.Model;
const Transform = components.Transform;

const SparseSet = main.utils.SparseSet;

var healthSet: SparseSet(Health, u32) = undefined;
var modelSet: SparseSet(Model, u32) = undefined;
var transformSet: SparseSet(Transform, u32) = undefined;

const ComponentBitset = packed struct {
	model: bool,
	health: bool,
	transform: bool,
};

const SystemBitset = packed struct {
	render: bool,
};

pub fn init() void {
	healthSet = .init(main.globalAllocator);
	modelSet = .init(main.globalAllocator);
	transformSet = .init(main.globalAllocator);
}

pub fn deinit() void {
	healthSet.deinit();
	modelSet.deinit();
	transformSet.deinit();
}