package io.cubyz.base.rotation;

import org.joml.RayAabIntersection;
import org.joml.Vector3f;
import org.joml.Vector3i;
import org.joml.Vector4f;

import io.cubyz.CubyzLogger;
import io.cubyz.api.Resource;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.blocks.RotationMode;
import io.cubyz.client.Meshes;
import io.cubyz.entity.Entity;
import io.cubyz.models.CubeModel;
import io.cubyz.models.Model;
import io.cubyz.util.FloatFastList;
import io.cubyz.util.IntFastList;

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
	public byte generateData(Vector3i dir, byte oldData) {
		byte data = 1;
		return data;
	}

	@Override
	public boolean dependsOnNeightbors() {
		return false;
	}

	@Override
	public Byte updateData(byte data, int dir) {
		if(data != 16)
			data++;
		return data;
	}

	@Override
	public boolean checkTransparency(byte data, int dir) {
		if(data < 16) {//TODO: && ((dir & 1) != 0 || (dir & 512) == 0)) {
			return true;
		}
		return false;
	}

	@Override
	public byte getNaturalStandard() {
		return 16;
	}

	@Override
	public boolean changesHitbox() {
		return true;
	}

	@Override
	public float getRayIntersection(RayAabIntersection intersection, BlockInstance bi, Vector3f min, Vector3f max, Vector3f transformedPosition) {
		max.add(0, bi.getData()/16.0f - 1.0f, 0);
		// Because of the huge number of different BlockInstances that will be tested, it is more efficient to use RayAabIntersection and determine the distance seperately:
		if (intersection.test(min.x, min.y, min.z, max.x, max.y, max.z)) {
			return min.add(0.5f, bi.getData()/32.0f, 0.5f).sub(transformedPosition).length();
		} else {
			return Float.MAX_VALUE;
		}
	}

	@Override
	public boolean checkEntity(Vector3f pos, float width, float height, int x, int y, int z, byte blockData) {
		return 	   y + blockData/16.0f >= pos.y
				&& y     <= pos.y + height
				&& x + 1 >= pos.x - width
				&& x     <= pos.x + width
				&& x + 1 >= pos.z - width
				&& x     <= pos.z + width;
	}

	@Override
	public boolean checkEntityAndDoCollision(Entity ent, Vector4f vel, int x, int y, int z, byte data) {
		// Check if the player can step onto this:
		if(y + data/16.0f - ent.getPosition().y > 0 && y + data/16.0f - ent.getPosition().y <= ent.stepHeight) {
			vel.w = Math.max(vel.w, y + data/16.0f - ent.getPosition().y);
			return false;
		}
		if(vel.y == 0) {
			return	   y + data/16.0f >= ent.getPosition().y
					&& y <= ent.getPosition().y + ent.height;
		}
		if(vel.y >= 0) {
			return true;
		}
		if(y + data/16.0f >= ent.getPosition().y + vel.y) {
			vel.y = y + data/16.0f + 0.01f - ent.getPosition().y;
		}
		return false;
	}
	
	@Override
	public int generateChunkMesh(BlockInstance bi, FloatFastList vertices, FloatFastList normals, IntFastList faces, IntFastList lighting, FloatFastList texture, IntFastList renderIndices, int renderIndex) {
		Model model = Meshes.blockMeshes.get(bi.getBlock()).model;
		if(!(model instanceof CubeModel)) {
			CubyzLogger.logger.severe("Unsupported model "+model.getRegistryID()+" in block "+bi.getBlock().getRegistryID()+" for stackable block type. Skipping block.");
			return renderIndex;
		}
		int x = bi.getX()&15;
		int y = bi.getY();
		int z = bi.getZ()&15;
		boolean[] neighbors = bi.getNeighbors();
		int[] light = bi.light;
		int offsetX = bi.getBlock().atlasX;
		int offsetY = bi.getBlock().atlasY;
		
		// Copies code from CubeModel and applies height transformation to it:
		int indexOffset = vertices.size/3;
		int size = model.positions.length/3;
		float factor = bi.getData()/16.0f;
		IntFastList indexesAdded = new IntFastList(24);
		for(int i = 0; i < size; i++) {
			int i2 = i*2;
			int i3 = i*3;
			float nx = model.normals[i3];
			float ny = model.normals[i3+1];
			float nz = model.normals[i3+2];
			if(nx == -1 && !neighbors[0] ||
			   nx == 1 && !neighbors[1] ||
			   nz == -1 && !neighbors[2] ||
			   nz == 1 && !neighbors[3] ||
			   ny == -1 && (!neighbors[4] || factor == 1) ||
			   ny == 1 && !neighbors[5]) {
				vertices.add(model.positions[i3] + x);
				if(ny != -1)
					vertices.add(model.positions[i3+1]*factor + y);
				else
					vertices.add(model.positions[i3+1] + y);
				vertices.add(model.positions[i3+2] + z);
				normals.add(nx);
				normals.add(ny);
				normals.add(nz);
				
				lighting.add(Model.interpolateLight(model.positions[i3], ny != -1 ? model.positions[i3+1]*factor : model.positions[i3+1], model.positions[i3+2], light));
				renderIndices.add(renderIndex);

				texture.add((model.textCoords[i2] + offsetX)/Meshes.atlasSize);
				if(ny == 0)
					texture.add((model.textCoords[i2+1]*factor + offsetY)/Meshes.atlasSize);
				else
					texture.add((model.textCoords[i2+1] + offsetY)/Meshes.atlasSize);
				indexesAdded.add(i);
			}
		}
		
		for(int i = 0; i < model.indices.length; i += 3) {
			if(indexesAdded.contains(model.indices[i]) && indexesAdded.contains(model.indices[i+1]) && indexesAdded.contains(model.indices[i+2])) {
				faces.add(indexesAdded.indexOf(model.indices[i]) + indexOffset, indexesAdded.indexOf(model.indices[i+1]) + indexOffset, indexesAdded.indexOf(model.indices[i+2]) + indexOffset);
			}
		}
		return renderIndex + 1;
	}
}
