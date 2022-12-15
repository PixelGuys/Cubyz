const std = @import("std");

const blocks = @import("blocks.zig");
const Block = blocks.Block;
const main = @import("main.zig");


/// Each block gets 16 bit of additional storage(apart from the reference to the block type).
/// These 16 bits are accessed and interpreted by the `RotationMode`.
/// With the `RotationMode` interface there is almost no limit to what can be done with those 16 bit.
pub const RotationMode = struct {
	const DefaultFunctions = struct {
		fn modelIndex(block: Block) u16 {
			return blocks.meshes.modelIndexStart(block);
		}
	};

	id: []const u8,
	/// if the block should be destroyed or changed when a certain neighbor is removed.
	dependsOnNeighbors: bool = false,

	modelIndex: *const fn(block: Block) u16 = &DefaultFunctions.modelIndex,
};

//public interface RotationMode extends RegistryElement {
//	/**
//	 * Called when generating the chunk mesh.
//	 * @param bi
//	 * @param vertices
//	 * @param faces
//	 * @return incremented renderIndex
//	 */
//	void generateChunkMesh(BlockInstance bi, VertexAttribList vertices, IntSimpleList faces);
//	
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
	const NoRotation = struct {
		const id: []const u8 = "cubyz:no_rotation";
	};
};

pub fn init() !void {
	rotationModes = std.StringHashMap(RotationMode).init(main.globalAllocator);
	inline for(@typeInfo(RotationModes).Struct.decls) |declaration| {
		try register(@field(RotationModes, declaration.name));
	}
}

pub fn deinit() void {
	rotationModes.deinit();
}

pub fn getByID(id: []const u8) *RotationMode {
	if(rotationModes.getPtr(id)) |mode| return mode;
	std.log.warn("Could not find rotation mode {s}. Using cubyz:no_rotation instead.", .{id});
	return rotationModes.getPtr("cubyz:no_rotation").?;
}

pub fn register(comptime Mode: type) !void {
	var result: RotationMode = RotationMode{.id = Mode.id};
	inline for(@typeInfo(RotationMode).Struct.fields) |field| {
		if(@hasDecl(Mode, field.name)) {
			if(field.field_type == @TypeOf(@field(Mode, field.name))) {
				@field(result, field.name) = @field(Mode, field.name);
			} else {
				@field(result, field.name) = &@field(Mode, field.name);
			}
		}
	}
	try rotationModes.putNoClobber(result.id, result);
}