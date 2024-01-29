const std = @import("std");

const blocks = @import("blocks.zig");
const Block = blocks.Block;
const chunk = @import("chunk.zig");
const Neighbors = chunk.Neighbors;
const main = @import("main.zig");
const vec = main.vec;
const Vec3i = vec.Vec3i;
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;


pub const Permutation = packed struct(u6) {
	/// 0 if x is x, 1 if x and y are swapped, 2 if x and z are swapped
	permutationX: u2 = 0,
	/// whether y and z are swapped (applied after permutationX)
	permutationYZ: bool = false,
	/// whether the x coordinate of the original model(applied before permutations) is flipped
	mirrorX: bool = false,
	/// whether the y coordinate of the original model(applied before permutations) is flipped
	mirrorY: bool = false,
	/// whether the z coordinate of the original model(applied before permutations) is flipped
	mirrorZ: bool = false,

	pub fn toInt(self: Permutation) u6 {
		return @bitCast(self);
	}

	pub fn transform(self: Permutation, _x: anytype) @TypeOf(_x) {
		var x = _x;
		if(@typeInfo(@TypeOf(x)) != .Vector) @compileError("Can only transform vector types.");
		if(@typeInfo(@TypeOf(x)).Vector.len != 3) @compileError("Vector needs to have length 3.");
		if(self.mirrorX) x[0] = -x[0];
		if(self.mirrorY) x[1] = -x[1];
		if(self.mirrorZ) x[2] = -x[2];
		switch(self.permutationX) {
			0 => {},
			1 => {
				const swap = x[0];
				x[0] = x[1];
				x[1] = swap;
			},
			2 => {
				const swap = x[0];
				x[0] = x[2];
				x[2] = swap;
			},
			else => unreachable,
		}
		if(self.permutationYZ) {
			const swap = x[1];
			x[1] = x[2];
			x[2] = swap;
		}
		return x;
	}

	pub fn permuteNeighborIndex(self: Permutation, neighbor: u3) u3 {
		// TODO: Make this more readable. Not sure how though.
		const mirrored: u3 = switch(neighbor) {
			Neighbors.dirNegX,
			Neighbors.dirPosX => (
				if(self.mirrorX) neighbor ^ 1
				else neighbor
			),
			Neighbors.dirDown,
			Neighbors.dirUp => (
				if(self.mirrorY) neighbor ^ 1
				else neighbor
			),
			Neighbors.dirNegZ,
			Neighbors.dirPosZ => (
				if(self.mirrorZ) neighbor ^ 1
				else neighbor
			),
			else => unreachable,
		};
		const afterXPermutation: u3 = switch(mirrored) {
			Neighbors.dirNegX,
			Neighbors.dirPosX => (
				if(self.permutationX == 1) mirrored +% (Neighbors.dirDown -% Neighbors.dirNegX)
				else if(self.permutationX == 2) mirrored +% (Neighbors.dirNegZ -% Neighbors.dirNegX)
				else mirrored
			),
			Neighbors.dirDown,
			Neighbors.dirUp => (
				if(self.permutationX == 1) mirrored +% (Neighbors.dirNegX -% Neighbors.dirDown)
				else mirrored
			),
			Neighbors.dirNegZ,
			Neighbors.dirPosZ => (
				if(self.permutationX == 2) mirrored +% (Neighbors.dirNegX -% Neighbors.dirNegZ)
				else mirrored
			),
			else => unreachable,
		};
		const afterYZPermutation: u3 = switch(afterXPermutation) {
			Neighbors.dirNegX,
			Neighbors.dirPosX => afterXPermutation,
			Neighbors.dirDown,
			Neighbors.dirUp => (
				if(self.permutationYZ) afterXPermutation +% (Neighbors.dirNegZ -% Neighbors.dirDown)
				else afterXPermutation
			),
			Neighbors.dirNegZ,
			Neighbors.dirPosZ => (
				if(self.permutationYZ) afterXPermutation +% (Neighbors.dirDown -% Neighbors.dirNegZ)
				else afterXPermutation
			),
			else => unreachable,
		};
		return afterYZPermutation;
	}
};

pub const RotatedModel = struct {
	modelIndex: u16,
	permutation: Permutation = Permutation{},
};

// TODO: Why not just use a tagged union?
/// Each block gets 16 bit of additional storage(apart from the reference to the block type).
/// These 16 bits are accessed and interpreted by the `RotationMode`.
/// With the `RotationMode` interface there is almost no limit to what can be done with those 16 bit.
pub const RotationMode = struct {
	const DefaultFunctions = struct {
		fn model(block: Block) RotatedModel {
			return RotatedModel{
				.modelIndex = blocks.meshes.modelIndexStart(block),
			};
		}
		fn generateData(_: *main.game.World, _: Vec3i, _: Vec3d, _: Vec3f, _: Vec3i, _: *Block, blockPlacing: bool) bool {
			return blockPlacing;
		}
	};

	/// if the block should be destroyed or changed when a certain neighbor is removed.
	dependsOnNeighbors: bool = false,

	model: *const fn(block: Block) RotatedModel = &DefaultFunctions.model,

	/// Updates the block data of a block in the world or places a block in the world.
	/// return true if the placing was successful, false otherwise.
	generateData: *const fn(world: *main.game.World, pos: Vec3i, relativePlayerPos: Vec3d, playerDir: Vec3f, relativeDir: Vec3i, currentData: *Block, blockPlacing: bool) bool = DefaultFunctions.generateData,
};

//public interface RotationMode extends RegistryElement {
//	/**
//	 * Update or place a block.
//	 * @param world
//	 * @param x
//	 * @param y
//	 * @param z
//	 * @param relativePlayerPosition Position of the player head relative to the (0, 0, 0) corner of the block.
//	 * @param playerDirection
//	 * @param relativeDir the direction in which the selected neighbor is.
//	 * @param currentData 0 if no block was there before.
//	 * @param blockPlacing true if the position of the block was previously empty/nonsolid.
//	 * @return true if the placing was successful, false otherwise.
//	 */
//	boolean generateData(World world, int x, int y, int z, Vector3d relativePlayerPosition, Vector3f playerDirection, Vector3i relativeDir, IntWrapper currentData, boolean blockPlacing);
//	
//	/**
//	 * Updates data of a placed block if the RotationMode dependsOnNeighbors().
//	 * If the returned value is null, then the block will be removed instead of only updating the data.
//	 * @param oldBlock
//	 * @param removedDir given as neighbor index (See NormalChunk.)
//	 * @return new data
//	 */
//	int updateData(int oldBlock, int removedDir, int newNeighbor);
//	
//	/**
//	 * A RotationMode may even alter the blocks transparency. Here is where it's done.
//	 * @param block The blocks data
//	 * @param neighbor the inverted(!) neighbor index(see Neighbors.java).
//	 */
//	boolean checkTransparency(int block, int neighbor);
//	
//	/**
//	 * @return standard data for natural generation.
//	 */
//	int getNaturalStandard(int block);
//	
//	/**
//	 * @param min minimal point of the surrounding block. May be overwritten.
//	 * @param max maximal point of the surrounding block. May be overwritten.
//	 */
//	float getRayIntersection(RayAabIntersection intersection, int block, Vector3f min, Vector3f max, Vector3f transformedPosition);
//
//	/**
//	 * Check if the entity would collide with the block.
//	 * @return Whether the entity and block hitboxes overlap.
//	 */
//	boolean checkEntity(Vector3d pos, double width, double height, int x, int y, int z, int block);
//	
//	/**
//	 * Check if the entity would collide with the block, if its position was changed by `vel`.
//	 * If a collision occurs, adjust the velocity in way such that the entity does not move inside the block.
//	 * @param vel Velocity of the entity. The 4th element is reserved for stepping: a y-movement that is done exactly once.
//	 * @return Returns true if the block behaves like a normal block and therefor needs to be handled like a normal block in the specified direction. Returns false if everything has been handled already in here.
//	 */
//	boolean checkEntityAndDoCollision(Entity ent, Vector4d vel, int x, int y, int z, int block);
//}

var rotationModes: std.StringHashMap(RotationMode) = undefined;

const RotationModes = struct {
	pub const NoRotation = struct {
		pub const id: []const u8 = "no_rotation";
	};
	pub const Log = struct {
		pub const id: []const u8 = "log";

		pub fn model(block: Block) RotatedModel {
			const permutation: Permutation = switch(block.data) {
				else => Permutation {},
				1 => Permutation {.mirrorX = true, .mirrorY = true},
				2 => Permutation {.permutationX = 1, .mirrorX = true, .mirrorY = true},
				3 => Permutation {.permutationX = 1},
				4 => Permutation {.permutationYZ = true, .mirrorZ = true, .mirrorY = true},
				5 => Permutation {.permutationYZ = true},
			};
			return RotatedModel{
				.modelIndex = blocks.meshes.modelIndexStart(block),
				.permutation = permutation,
			};
		}
	};
	pub const Fence = struct {
		pub const id: []const u8 = "fence";

		pub fn model(block: Block) RotatedModel {
			const data = block.data>>2 & 15; // TODO: This is just for compatibility with the java version. Remove it.
			const modelIndexOffsets = [16]u16 {
				0, // 0b0000
				1, // 0b0001
				1, // 0b0010
				3, // 0b0011
				1, // 0b0100
				2, // 0b0101
				2, // 0b0110
				4, // 0b0111
				1, // 0b1000
				2, // 0b1001
				2, // 0b1010
				4, // 0b1011
				3, // 0b1100
				4, // 0b1101
				4, // 0b1110
				5, // 0b1111
			};
			const permutations = [16]Permutation {
				Permutation{}, // 0b0000
				Permutation{.mirrorX = true, .mirrorZ = true}, // 0b0001
				Permutation{}, // 0b0010
				Permutation{}, // 0b0011
				Permutation{.permutationX = 2, .mirrorZ = true}, // 0b0100
				Permutation{.mirrorX = true, .mirrorZ = true}, // 0b0101
				Permutation{.permutationX = 2, .mirrorZ = true}, // 0b0110
				Permutation{.permutationX = 2, .mirrorX = true}, // 0b0111
				Permutation{.permutationX = 2, .mirrorX = true}, // 0b1000
				Permutation{.permutationX = 2, .mirrorX = true}, // 0b1001
				Permutation{}, // 0b1010
				Permutation{.permutationX = 2, .mirrorZ = true}, // 0b1011
				Permutation{.permutationX = 2, .mirrorX = true}, // 0b1100
				Permutation{}, // 0b1101
				Permutation{.mirrorX = true, .mirrorZ = true}, // 0b1110
				Permutation{}, // 0b1111
			};
			return RotatedModel{
				.modelIndex = blocks.meshes.modelIndexStart(block) + modelIndexOffsets[data],
				.permutation = permutations[data],
			};
		}
	};
};

pub fn init() void {
	rotationModes = std.StringHashMap(RotationMode).init(main.globalAllocator.allocator);
	inline for(@typeInfo(RotationModes).Struct.decls) |declaration| {
		register(@field(RotationModes, declaration.name));
	}
}

pub fn deinit() void {
	rotationModes.deinit();
}

pub fn getByID(id: []const u8) *RotationMode {
	if(rotationModes.getPtr(id)) |mode| return mode;
	std.log.warn("Could not find rotation mode {s}. Using no_rotation instead.", .{id});
	return rotationModes.getPtr("no_rotation").?;
}

pub fn register(comptime Mode: type) void {
	var result: RotationMode = RotationMode{};
	inline for(@typeInfo(RotationMode).Struct.fields) |field| {
		if(@hasDecl(Mode, field.name)) {
			if(field.type == @TypeOf(@field(Mode, field.name))) {
				@field(result, field.name) = @field(Mode, field.name);
			} else {
				@field(result, field.name) = &@field(Mode, field.name);
			}
		}
	}
	rotationModes.putNoClobber(Mode.id, result) catch unreachable;
}