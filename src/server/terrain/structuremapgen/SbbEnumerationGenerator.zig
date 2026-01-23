const std = @import("std");

const main = @import("main");
const random = main.random;
const ZonElement = main.ZonElement;
const terrain = main.server.terrain;
const biomes = terrain.biomes;
const noise = terrain.noise;
const StructureMapFragment = terrain.StructureMap.StructureMapFragment;
const SurfaceMap = terrain.SurfaceMap;
const MapFragment = SurfaceMap.MapFragment;
const CaveMapView = terrain.CaveMap.CaveMapView;
const CaveBiomeMapView = terrain.CaveBiomeMap.CaveBiomeMapView;
const SbbGen = @import("../simple_structures/SbbGen.zig");
const ServerChunk = main.chunk.ServerChunk;
const SimpleStructure = @import("SimpleStructureGen.zig").SimpleStructure;
const StructureBuildingBlock = terrain.structure_building_blocks.StructureBuildingBlock;
const vec = main.vec;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;

pub const id = "cubyz:sbb_enumeration_generator";

pub const priority = 131072;

pub const generatorSeed = 0x7568492764892;

pub const defaultState = .disabled;

var sbbList: []main.server.terrain.biomes.SimpleStructureModel = undefined;
var signBlock: main.blocks.Block = undefined;

pub fn init(parameters: ZonElement) void {
	_ = parameters;

	const Entry = struct {sbb: *const StructureBuildingBlock, hasParent: bool, reachable: bool};
	var localSbbList: main.ListUnmanaged(Entry) = .{};
	defer localSbbList.deinit(main.stackAllocator);
	for(terrain.structure_building_blocks.list()) |*entry| {
		localSbbList.append(main.stackAllocator, .{.sbb = entry, .hasParent = false, .reachable = false});
	}

	{ // Mark all SBBs that are children of other SBBs.
		outer: for(localSbbList.items) |*candidate| {
			for(localSbbList.items) |other| {
				if(other.sbb == candidate.sbb) continue;
				for(other.sbb.children) |child| {
					if(child == candidate.sbb) {
						candidate.hasParent = true;
						continue :outer;
					}
				}
			}
		}
	}
	var rootSbbList: main.ListUnmanaged(*const StructureBuildingBlock) = .initCapacity(main.stackAllocator, localSbbList.items.len);
	defer rootSbbList.deinit(main.stackAllocator);
	{ // Ensure that every structure was reachable (in case of recursion)
		var unreachables: main.ListUnmanaged(*Entry) = .initCapacity(main.stackAllocator, localSbbList.items.len);
		defer unreachables.deinit(main.stackAllocator);

		for(localSbbList.items) |*candidate| {
			if(candidate.hasParent) {
				unreachables.appendAssumeCapacity(candidate);
			} else {
				candidate.reachable = true;
				rootSbbList.appendAssumeCapacity(candidate.sbb);
			}
		}

		while(unreachables.items.len != 0) {
			var lastLen: usize = 0;
			while(lastLen != unreachables.items.len) {
				lastLen = unreachables.items.len;
				var i: usize = 0;
				outer: while(i < unreachables.items.len) {
					const candidate = unreachables.items[i];
					for(localSbbList.items) |other| {
						if(!other.reachable) continue;
						for(other.sbb.children) |child| {
							if(child == candidate.sbb) {
								candidate.reachable = true;
								_ = unreachables.swapRemove(i);
								continue :outer;
							}
						}
					}
					i += 1;
				}
			}
			const recursiveOne = unreachables.popOrNull() orelse break;
			recursiveOne.reachable = true;
			rootSbbList.appendAssumeCapacity(recursiveOne.sbb);
		}
	}

	std.sort.insertion(*const StructureBuildingBlock, rootSbbList.items, {}, struct {
		fn lessThanFn(_: void, lhs: *const StructureBuildingBlock, rhs: *const StructureBuildingBlock) bool {
			return std.ascii.orderIgnoreCase(lhs.id, rhs.id) == .lt;
		}
	}.lessThanFn);

	sbbList = main.worldArena.alloc(main.server.terrain.biomes.SimpleStructureModel, rootSbbList.items.len);

	for (rootSbbList.items, 0..) |sbb, i| {
		const structureData = main.worldArena.create(SbbGen);
		structureData.* = .{
			.structureRef = sbb,
			.placeMode = .all,
			.rotation = .{.fixed = .@"0"},
		};
		sbbList[i] = .{
			.chance = undefined,
			.generationMode = .floor,
			.priority = 1.0,
			.vtable = .{
				.generate = main.meta.castFunctionSelfToAnyopaque(SbbGen.generate),
				.generationMode = .floor,
				.hashFunction = undefined,
				.loadModel = undefined,
			},
			.data = structureData,
		};
	}

	signBlock.typ = main.blocks.getBlockById("cubyz:sign/oak") catch |err| blk: {
		std.log.err("Could not find sign with id cubyz:sign/oak: {s}", .{@errorName(err)});
		break :blk 0;
	};
	signBlock.data = 6;
}

pub fn generate(map: *StructureMapFragment, worldSeed: u64) void {
	const size = StructureMapFragment.size*map.pos.voxelSize;
	const margin = 16;
	const marginZ = 32;
	var px: i32 = 0;
	while (px < size + 2*margin) : (px += 32) {
		var py: i32 = 0;
		while (py < size + 2*margin) : (py += 32) {
			const wpx = px +% map.pos.wx;
			const wpy = py +% map.pos.wy;
			const index: u32 = @intCast(@mod(@divFloor(wpx, 32), @as(i32, @intCast(sbbList.len))));
			const sbb = &sbbList[index];

			inline for (.{0, 128}) |startZ| blk: {
				const relZ = startZ -% map.pos.wz;
				if (relZ < -32 or relZ >= size + 32) break :blk;

				const signRow = wpy & 1023 == 0;
				if (signRow) {
					const structure = map.allocator.create(SignGenerator);
					structure.* = .{
						.wx = wpx,
						.wy = wpy,
						.wz = map.pos.wz +% relZ,
						.id = @as(*SbbGen, @ptrCast(@alignCast(sbb.data))).structureRef.id,
					};
					map.addStructure(.{
						.internal = .{
							.data = structure,
							.generateFn = main.meta.castFunctionSelfToConstAnyopaque(SignGenerator.generate),
						},
						.priority = sbb.priority,
					}, .{px, py, structure.wz -% map.pos.wz}, .{px +% 1, py +% 1, structure.wz -% map.pos.wz +% 1});
				} else {
					const structure = map.allocator.create(SimpleStructure);
					structure.* = .{
						.wx = wpx,
						.wy = wpy,
						.wz = map.pos.wz +% relZ,
						.seed = worldSeed*%@as(u32, @bitCast(wpy)),
						.model = sbb,
						.isCeiling = false,
					};
					map.addStructure(.{
						.internal = .{
							.data = structure,
							.generateFn = main.meta.castFunctionSelfToConstAnyopaque(SimpleStructure.generate),
						},
						.priority = sbb.priority,
					}, .{px -% margin, py -% margin, structure.wz -% map.pos.wz -% marginZ}, .{px +% margin, py +% margin, structure.wz -% map.pos.wz +% marginZ});
				}
			}
		}
	}
}

const SignGenerator = struct {
	wx: i32,
	wy: i32,
	wz: i32,
	id: []const u8,

	pub fn generate(self: *const SignGenerator, chunk: *ServerChunk, _: terrain.CaveMap.CaveMapView, _: terrain.CaveBiomeMap.CaveBiomeMapView) void {
		if (chunk.super.pos.voxelSize != 1) return;
		const relX = self.wx - chunk.super.pos.wx;
		const relY = self.wy - chunk.super.pos.wy;
		const relZ = self.wz - chunk.super.pos.wz;
		if (signBlock.blockEntity()) |blockEntity| {
			chunk.updateBlockIfDegradable(relX, relY, relZ, signBlock);
			var reader: main.utils.BinaryReader = .init(self.id);
			blockEntity.onLoadServer(.{self.wx, self.wy, self.wz}, &chunk.super, &reader) catch |err| {
				std.log.err("Error while loading id to sign: {s}", .{@errorName(err)});
			};
		}
	}
};
