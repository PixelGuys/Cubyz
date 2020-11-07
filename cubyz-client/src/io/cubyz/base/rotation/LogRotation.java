package io.cubyz.base.rotation;

/**
 * Rotates the block based on the direction the player is placing it.
 */

import org.joml.RayAabIntersection;
import org.joml.Vector3f;
import org.joml.Vector3i;
import org.joml.Vector4f;

import io.cubyz.api.Resource;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.blocks.RotationMode;
import io.cubyz.entity.Entity;
import io.cubyz.entity.Player;
import io.cubyz.world.BlockSpatial;

import static io.cubyz.Constants.PI;
import static io.cubyz.Constants.PI_HALF;

public class LogRotation implements RotationMode {
	
	Resource id = new Resource("cubyz", "log");
	@Override
	public Resource getRegistryID() {
		return id;
	}

	@Override
	public byte generateData(Vector3i dir, byte oldData) {
		byte data = 0;
		if(dir.x == 1) data = (byte)0b10;
		if(dir.x == -1) data = (byte)0b11;
		if(dir.y == -1) data = (byte)0b0;
		if(dir.y == 1) data = (byte)0b1;
		if(dir.z == 1) data = (byte)0b100;
		if(dir.z == -1) data = (byte)0b101;
		return data;
	}

	@Override
	public Object[] generateSpatials(BlockInstance bi, byte data, Player player, int worldSizeX, int worldSizeZ) {
		BlockSpatial[] spatials = new BlockSpatial[1];
		BlockSpatial tmp = new BlockSpatial(bi, player, worldSizeX, worldSizeZ);
		switch(data) {
			default:
				break;
			case 1:
				tmp.setRotation(PI, 0, 0);
				break;
			case 2:
				tmp.setRotation(0, 0, -PI_HALF);
				break;
			case 3:
				tmp.setRotation(0, 0, PI_HALF);
				break;
			case 4:
				tmp.setRotation(PI_HALF, 0, 0);
				break;
			case 5:
				tmp.setRotation(-PI_HALF, 0, 0);
				break;
		}
		spatials[0] = tmp;
		return spatials;
	}

	@Override
	public boolean dependsOnNeightbors() {
		return false;
	}

	@Override
	public Byte updateData(byte data, int dir) {
		return 0;
	}

	@Override
	public boolean checkTransparency(byte data, int dir) {
		return false;
	}

	@Override
	public byte getNaturalStandard() {
		return 0;
	}

	@Override
	public boolean changesHitbox() {
		return false;
	}

	@Override
	public float getRayIntersection(RayAabIntersection arg0, BlockInstance arg1, Vector3f min, Vector3f max, Vector3f transformedPosition) {
		return 0;
	}

	@Override
	public boolean checkEntity(Entity arg0, int x, int y, int z, byte arg2) {
		return false;
	}

	@Override
	public boolean checkEntityAndDoCollision(Entity arg0, Vector4f arg1, int x, int y, int z, byte arg2) {
		return true;
	}
}
