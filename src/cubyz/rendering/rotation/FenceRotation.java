package cubyz.rendering.rotation;

import org.joml.RayAabIntersection;
import org.joml.Vector3d;
import org.joml.Vector3f;
import org.joml.Vector3i;
import org.joml.Vector4d;

import cubyz.api.Resource;
import cubyz.client.BlockMeshes;
import cubyz.rendering.models.Model;
import cubyz.utils.datastructures.IntWrapper;
import cubyz.utils.VertexAttribList;
import cubyz.utils.datastructures.IntFastList;
import cubyz.world.Neighbors;
import cubyz.world.NormalChunk;
import cubyz.world.Chunk;
import cubyz.world.World;
import cubyz.world.blocks.Blocks;
import cubyz.world.blocks.BlockInstance;
import cubyz.world.blocks.RotationMode;
import cubyz.world.entity.Entity;

import static cubyz.client.NormalChunkMesh.*;

public class FenceRotation implements RotationMode {
	Resource id = new Resource("cubyz", "fence");
	@Override
	public Resource getRegistryID() {
		return id;
	}

	@Override
	public boolean generateData(World world, int x, int y, int z, Vector3d relativePlayerPosition, Vector3f playerDirection, Vector3i relativeDirection, IntWrapper currentData, boolean blockPlacing) {
		if (!blockPlacing) return false;
		NormalChunk chunk = world.getChunk(x, y, z);
		int data = 0;
		// Get all neighbors and set the corresponding bits:
		int[] neighbors = chunk.getNeighbors(x, y , z);
		if (Blocks.solid(neighbors[Neighbors.DIR_NEG_X])) {
			data |= 1 << Neighbors.DIR_NEG_X;
		}
		if (Blocks.solid(neighbors[Neighbors.DIR_POS_X])) {
			data |= 1 << Neighbors.DIR_POS_X;
		}
		if (Blocks.solid(neighbors[Neighbors.DIR_NEG_Z])) {
			data |= 1 << Neighbors.DIR_NEG_Z;
		}
		if (Blocks.solid(neighbors[Neighbors.DIR_POS_Z])) {
			data |= 1 << Neighbors.DIR_POS_Z;
		}
		currentData.data = (currentData.data & Blocks.TYPE_MASK) | (data << 16);
		return true;
	}

	@Override
	public boolean dependsOnNeightbors() {
		return true;
	}

	@Override
	public int updateData(int block, int dir, int newNeighbor) {
		if (dir == Neighbors.DIR_DOWN || dir == Neighbors.DIR_UP) return block;
		int mask = 1 << (16 + dir);
		block &= ~mask;
		if (Blocks.solid(newNeighbor))
			block |= mask;
		return block;
	}

	@Override
	public boolean checkTransparency(int block, int dir) {
		return true;
	}

	@Override
	public int getNaturalStandard(int block) {
		return block;
	}

	@Override
	public boolean changesHitbox() {
		return true;
	}

	@Override
	public float getRayIntersection(RayAabIntersection intersection, BlockInstance bi, Vector3f min, Vector3f max, Vector3f transformedPosition) {
		// Check the +. TODO: Check the actual model.
		float xOffset = 0;
		float xLen = 1;
		float zOffset = 0;
		float zLen = 1;
		int data = bi.getBlock() >>> 16;
		if ((data & (1 << Neighbors.DIR_NEG_X)) == 0) {
			xOffset += 0.5f;
			xLen -= 0.5f;
		}
		if ((data & (1 << Neighbors.DIR_POS_X)) == 0) {
			xLen -= 0.5f;
		}
		if ((data & (1 << Neighbors.DIR_NEG_Z)) == 0) {
			zOffset += 0.5f;
			zLen -= 0.5f;
		}
		if ((data & (1 << Neighbors.DIR_POS_Z)) == 0) {
			zLen -= 0.5f;
		}
		min.z += zOffset;
		max.z = min.z + zLen;
		if (!intersection.test(min.x + 0.375f, min.y, min.z, max.x - 0.375f, max.y, max.z)) {
			min.z -= zOffset;
			max.z = min.z + 1;
			min.x += xOffset;
			max.x = min.x + xLen;
			if (!intersection.test(min.x, min.y, min.z + 0.375f, max.x, max.y, max.z - 0.375f)) {
				return Float.MAX_VALUE;
			}
		}
		return min.add(0.5f, 0.5f, 0.5f).sub(transformedPosition).length();
	}

	@Override
	public boolean checkEntity(Vector3d pos, double width, double height, int x, int y, int z, int block) {
		// Hit area is just a simple + with a width of 0.25:
		return y >= pos.y
				&& y <= pos.y + height
				&&
				(
					( // - of the +:
						x + 0.625f >= pos.x - width
						&& x + 0.375f <= pos.x+ width
						&& z + 1 >= pos.x - width
						&& z <= pos.x + width
					)
					||
					( // | of the +:
						z + 0.625f >= pos.z - width
						&& z + 0.375f <= pos.z+ width
						&& x + 1 >= pos.x - width
						&& x <= pos.x + width
					)
				);
	}

	@Override
	public boolean checkEntityAndDoCollision(Entity ent, Vector4d vel, int x, int y, int z, int block) {
		// Hit area is just a simple + with a width of 0.25:
		int blockData = block >>> 16;
		float xOffset = 0;
		float xLen = 1;
		float zOffset = 0;
		float zLen = 1;
		if ((blockData & (1 << Neighbors.DIR_NEG_X)) == 0) {
			xOffset += 0.5f;
			xLen -= 0.5f;
		}
		if ((blockData & (1 << Neighbors.DIR_POS_X)) == 0) {
			xLen -= 0.5f;
		}
		if ((blockData & (1 << Neighbors.DIR_NEG_Z)) == 0) {
			zOffset += 0.5f;
			zLen -= 0.5f;
		}
		if ((blockData & (1 << Neighbors.DIR_POS_Z)) == 0) {
			zLen -= 0.5f;
		}
		
		ent.aabCollision(vel, x + xOffset, y, z + 0.375f, xLen, 1, 0.25f, block);
		ent.aabCollision(vel, x + 0.375f, y, z + zOffset, 0.35f, 1, zLen, block);
		return false;
	}
	
	@Override
	public void generateChunkMesh(BlockInstance bi, VertexAttribList vertices, IntFastList faces) {
		Model model = BlockMeshes.mesh(bi.getBlock() & Blocks.TYPE_MASK).model;
		int x = bi.x & Chunk.chunkMask;
		int y = bi.y & Chunk.chunkMask;
		int z = bi.z & Chunk.chunkMask;
		int[] textureIndices = BlockMeshes.textureIndices(bi.getBlock());
		int blockData = bi.getBlock() >>> 16;
		boolean negX = (blockData & (1 << Neighbors.DIR_NEG_X)) == 0;
		boolean posX = (blockData & (1 << Neighbors.DIR_POS_X)) == 0;
		boolean negZ = (blockData & (1 << Neighbors.DIR_NEG_Z)) == 0;
		boolean posZ = (blockData & (1 << Neighbors.DIR_POS_Z)) == 0;
		
		// Simply copied the code from model and move all vertices to the center that touch an edge that isn't connected to another fence.
		int indexOffset = vertices.currentVertex();
		int[] light = bi.light;
		for(int i3 = 0; i3 < model.positions.length; i3 += 3) {
			int i2 = i3*2/3;
			float newX = model.positions[i3];
			if (newX == 0 && negX) newX = 0.5f;
			if (newX == 1 && posX) newX = 0.5f;
			newX += x;
			float newY = model.positions[i3+1] + y;
			float newZ = model.positions[i3+2];
			if (newZ == 0 && negZ) newZ = 0.5f;
			if (newZ == 1 && posZ) newZ = 0.5f;
			newZ += z;
			vertices.add(POSITION_X, newX);
			vertices.add(POSITION_Y, newY);
			vertices.add(POSITION_Z, newZ);
			
			vertices.add(LIGHTING, Model.interpolateLight(model.positions[i3], model.positions[i3+1], model.positions[i3+2], model.normals[i3], model.normals[i3+1], model.normals[i3+2], light));
			
			vertices.add(TEXTURE_X, model.textCoords[i2]);
			vertices.add(TEXTURE_Y, model.textCoords[i2+1]);
			vertices.add(TEXTURE_Z, (float)textureIndices[Model.normalToNeighbor(model.normals[i3], model.normals[i3+1], model.normals[i3+2])]);
			
			vertices.add(NORMAL_X, model.normals[i3]);
			vertices.add(NORMAL_Y, model.normals[i3+1]);
			vertices.add(NORMAL_Z, model.normals[i3+2]);
			
			vertices.endVertex();
		}
		
		for(int i = 0; i < model.indices.length; i++) {
			faces.add(model.indices[i] + indexOffset);
		}
	}
}
