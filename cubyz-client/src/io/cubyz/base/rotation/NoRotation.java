package io.cubyz.base.rotation;

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

public class NoRotation implements RotationMode {
	Resource id = new Resource("cubyz", "no_rotation");
	@Override
	public Resource getRegistryID() {
		return id;
	}

	@Override
	public byte generateData(Vector3i dir, byte oldData) {
		return 0;
	}

	@Override
	public Object[] generateSpatials(BlockInstance bi, byte data, Player player, int worldSize) {
		return new BlockSpatial[] {new BlockSpatial(bi, player, worldSize)};
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
