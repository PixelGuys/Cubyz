package io.cubyz.base.rotation;

import org.joml.Vector3i;

import io.cubyz.api.Resource;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.blocks.RotationMode;
import io.cubyz.entity.Player;
import io.cubyz.world.BlockSpatial;

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
	public Object[] generateSpatials(BlockInstance bi, byte data, Player player, int worldSize) {
		BlockSpatial[] spatials = new BlockSpatial[1];
		BlockSpatial tmp = new BlockSpatial(bi, player, worldSize);
		tmp.setScale(1, data/16.0f, 1);
		tmp.setPosition(bi.getX(), bi.getY() - 0.5f + data/32.0f, bi.getZ(), player, worldSize);
		spatials[0] = tmp;
		return spatials;
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
}
