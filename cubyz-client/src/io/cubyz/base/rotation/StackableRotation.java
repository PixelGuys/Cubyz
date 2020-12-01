package io.cubyz.base.rotation;

import org.joml.RayAabIntersection;
import org.joml.Vector3f;
import org.joml.Vector3i;
import org.joml.Vector4f;

import io.cubyz.api.Resource;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.blocks.RotationMode;
import io.cubyz.client.Meshes;
import io.cubyz.entity.Entity;
import io.cubyz.entity.Player;
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

	/*@Override
	public Object[] generateSpatials(BlockInstance bi, byte data, Player player, int worldSizeX, int worldSizeZ) {
		BlockSpatial[] spatials = new BlockSpatial[1];
		BlockSpatial tmp = new BlockSpatial(bi, player, worldSizeX, worldSizeZ);
		tmp.setScale(1, data/16.0f, 1);
		tmp.setPosition(bi.getX(), bi.getY(), bi.getZ(), player, worldSizeX, worldSizeZ);
		spatials[0] = tmp;
		return spatials;
	}*/

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
	public boolean checkEntity(Entity ent, int x, int y, int z, byte data) {
		return 	   y + data/16.0f >= ent.getPosition().y
				&& y     <= ent.getPosition().y + ent.height
				&& x + 1 >= ent.getPosition().x - ent.width
				&& x     <= ent.getPosition().x + ent.width
				&& x + 1 >= ent.getPosition().z - ent.width
				&& x     <= ent.getPosition().z + ent.width;
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
		// TODO: Perform face cutting.
		Meshes.blockMeshes.get(bi.getBlock()).model.addToChunkMesh(bi.x & 15, bi.y, bi.z & 15, bi.getBlock().atlasX, bi.getBlock().atlasY, bi.light, bi.getNeighbors(), vertices, normals, faces, lighting, texture, renderIndices, renderIndex);
		return renderIndex + 1;
	}
}
