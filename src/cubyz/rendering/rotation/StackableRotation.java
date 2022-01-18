package cubyz.rendering.rotation;

import org.joml.Intersectiond;
import org.joml.RayAabIntersection;
import org.joml.Vector2d;
import org.joml.Vector3d;
import org.joml.Vector3f;
import org.joml.Vector3i;
import org.joml.Vector4d;

import cubyz.utils.Logger;
import cubyz.utils.VertexAttribList;
import cubyz.api.Resource;
import cubyz.client.BlockMeshes;
import cubyz.rendering.models.CubeModel;
import cubyz.rendering.models.Model;
import cubyz.utils.datastructures.IntWrapper;
import cubyz.utils.datastructures.IntFastList;
import cubyz.world.Neighbors;
import cubyz.world.Chunk;
import cubyz.world.World;
import cubyz.world.blocks.BlockInstance;
import cubyz.world.blocks.Blocks;
import cubyz.world.blocks.RotationMode;
import cubyz.world.entity.Entity;

import static cubyz.client.NormalChunkMesh.*;

/**
 * For stackable partial blocks, like snow.
 */

public class StackableRotation implements RotationMode {
	
	Resource id = new Resource("cubyz", "stackable");
	@Override
	public Resource getRegistryID() {
		return id;
	}

	@Override
	public boolean generateData(World world, int x, int y, int z, Vector3d relativePlayerPosition, Vector3f playerDirection, Vector3i relativeDirection, IntWrapper currentData, boolean blockPlacing) {
		if (blockPlacing) {
			currentData.data |= 0x10000;
			return true;
		}
		Vector3d dir = new Vector3d(playerDirection);
		Vector3d min = new Vector3d();
		Vector3d max = new Vector3d(1, currentData.data/16.0f, 1);
		Vector2d result = new Vector2d();
		// Check if the ray is going through the block:
		if (Intersectiond.intersectRayAab(relativePlayerPosition, dir, min, max, result)) {
			// Check if the ray is going through the top layer and going the right direction:
			min.y = max.y - 0.0001f;
			if (playerDirection.y < 0 && Intersectiond.intersectRayAab(relativePlayerPosition, dir, min, max, result)) {
				if (currentData.data >>> 16 == 16) return false;
				currentData.data += 0x10000;
				return true;
			}
			return false;
		} else {
			if (currentData.data >>> 16 == 16) return false;
			currentData.data += 0x10000;
			return true;
		}
	}

	@Override
	public boolean dependsOnNeightbors() {
		return false;
	}

	@Override
	public int updateData(int block, int dir, int newNeighbor) {
		return block;
	}

	@Override
	public boolean checkTransparency(int block, int dir) {
		if (block >>> 16 < 16 && dir != Neighbors.DIR_UP) {
			return true;
		}
		return false;
	}

	@Override
	public int getNaturalStandard(int block) {
		return block | (16 << 16);
	}

	@Override
	public boolean changesHitbox() {
		return true;
	}

	@Override
	public float getRayIntersection(RayAabIntersection intersection, BlockInstance bi, Vector3f min, Vector3f max, Vector3f transformedPosition) {
		int data = Math.max(16, bi.getBlock() >>> 16);
		max.add(0, data/16.0f - 1.0f, 0);
		// Because of the huge number of different BlockInstances that will be tested, it is more efficient to use RayAabIntersection and determine the distance seperately:
		if (intersection.test(min.x, min.y, min.z, max.x, max.y, max.z)) {
			return min.add(0.5f, data/32.0f, 0.5f).sub(transformedPosition).length();
		} else {
			return Float.MAX_VALUE;
		}
	}

	@Override
	public boolean checkEntity(Vector3d pos, double width, double height, int x, int y, int z, int block) {
		return 	   y + Math.max(1, (block >>> 16)/16.0f) >= pos.y
				&& y     <= pos.y + height
				&& x + 1 >= pos.x - width
				&& x     <= pos.x + width
				&& z + 1 >= pos.z - width
				&& z     <= pos.z + width;
	}

	@Override
	public boolean checkEntityAndDoCollision(Entity ent, Vector4d vel, int x, int y, int z, int block) {
		// Check if the player can step onto this:
		float yOffset = Math.max(1, (block >>> 16)/16.0f);
		if (y + yOffset - ent.getPosition().y > 0 && y + yOffset - ent.getPosition().y <= ent.stepHeight) {
			vel.w = Math.max(vel.w, y + yOffset - ent.getPosition().y);
			return false;
		}
		if (vel.y == 0) {
			return	   y + yOffset >= ent.getPosition().y
					&& y <= ent.getPosition().y + ent.height;
		}
		if (vel.y >= 0) {
			return true;
		}
		if (y + yOffset >= ent.getPosition().y + vel.y) {
			vel.y = y + yOffset + 0.01f - ent.getPosition().y;
		}
		return false;
	}
	
	@Override
	public void generateChunkMesh(BlockInstance bi, VertexAttribList vertices, IntFastList faces) {
		Model model = BlockMeshes.mesh(bi.getBlock() & Blocks.TYPE_MASK).model;
		if (!(model instanceof CubeModel)) {
			Logger.error("Unsupported model "+model.getRegistryID()+" in block "+Blocks.id(bi.getBlock())+" for stackable block type. Skipping block.");
			return;
		}
		int x = bi.x & Chunk.chunkMask;
		int y = bi.y & Chunk.chunkMask;
		int z = bi.z & Chunk.chunkMask;
		byte neighbors = bi.getNeighbors();
		int[] light = bi.light;
		int[] textureIndices = BlockMeshes.textureIndices(bi.getBlock());
		
		// Copies code from CubeModel and applies height transformation to it:
		int indexOffset = vertices.currentVertex();
		int size = model.positions.length/3;
		float factor = Math.min(1, (bi.getBlock() >>> 16)/16.0f);
		IntFastList indexesAdded = new IntFastList(24);
		for(int i = 0; i < size; i++) {
			int i2 = i*2;
			int i3 = i*3;
			float nx = model.normals[i3];
			float ny = model.normals[i3+1];
			float nz = model.normals[i3+2];
			if (nx == -1 && (neighbors & Neighbors.BIT_MASK[Neighbors.DIR_NEG_X]) != 0 ||
			   nx == 1 && (neighbors & Neighbors.BIT_MASK[Neighbors.DIR_POS_X]) != 0 ||
			   nz == -1 && (neighbors & Neighbors.BIT_MASK[Neighbors.DIR_NEG_Z]) != 0 ||
			   nz == 1 && (neighbors & Neighbors.BIT_MASK[Neighbors.DIR_POS_Z]) != 0 ||
			   ny == -1 && ((neighbors & Neighbors.BIT_MASK[Neighbors.DIR_DOWN]) != 0 || factor == 1) ||
			   ny == 1 && (neighbors & Neighbors.BIT_MASK[Neighbors.DIR_UP]) != 0) {
				vertices.add(POSITION_X, model.positions[i3] + x);
				if (ny != -1)
					vertices.add(POSITION_Y, model.positions[i3+1]*factor + y);
				else
					vertices.add(POSITION_Y, model.positions[i3+1] + y);
				vertices.add(POSITION_Z, model.positions[i3+2] + z);
				vertices.add(NORMAL_X, nx);
				vertices.add(NORMAL_Y, ny);
				vertices.add(NORMAL_Z, nz);
				
				vertices.add(LIGHTING, Model.interpolateLight(model.positions[i3], ny != -1 ? model.positions[i3+1]*factor : model.positions[i3+1], model.positions[i3+2], model.normals[i3], model.normals[i3+1], model.normals[i3+2], light));

				vertices.add(TEXTURE_X, model.textCoords[i2]);
				if (ny == 0) {
					vertices.add(TEXTURE_Y, model.textCoords[i2+1]*factor);
				} else {
					vertices.add(TEXTURE_Y, model.textCoords[i2+1]);
				}

				vertices.add(TEXTURE_Z, (float)textureIndices[Model.normalToNeighbor(model.normals[i3], model.normals[i3+1], model.normals[i3+2])]);
				indexesAdded.add(i);
				vertices.endVertex();
			}
		}
		
		for(int i = 0; i < model.indices.length; i += 3) {
			if (indexesAdded.contains(model.indices[i]) && indexesAdded.contains(model.indices[i+1]) && indexesAdded.contains(model.indices[i+2])) {
				faces.add(indexesAdded.indexOf(model.indices[i]) + indexOffset, indexesAdded.indexOf(model.indices[i+1]) + indexOffset, indexesAdded.indexOf(model.indices[i+2]) + indexOffset);
			}
		}
	}
}
