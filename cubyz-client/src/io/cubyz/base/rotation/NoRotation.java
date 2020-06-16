package io.cubyz.base.rotation;

import org.joml.Vector3i;

import io.cubyz.ClientOnly;
import io.cubyz.api.Resource;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.blocks.RotationMode;
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
	public Object[] generateSpatials(BlockInstance bi, byte data) {
		return new BlockSpatial[] {(BlockSpatial)ClientOnly.createBlockSpatial.apply(bi)};
	}

}
