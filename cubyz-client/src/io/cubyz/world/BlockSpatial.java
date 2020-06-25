package io.cubyz.world;

import org.joml.Vector3f;

import io.cubyz.blocks.BlockInstance;
import io.cubyz.client.Meshes;
import io.jungle.Spatial;

public class BlockSpatial extends Spatial {
	private BlockInstance owner;
	
	public BlockSpatial(BlockInstance bi) {
		super(Meshes.blockMeshes.get(bi.getBlock()), bi.light);
		setPosition(bi.getX(), bi.getY(), bi.getZ());
		this.owner = bi;
	}
	
	@Override
	public void setPosition(Vector3f position) {
		super.setPosition(position);
	}

	@Override
	public void setPosition(float x, float y, float z) {
        super.setPosition(x, y, z);
    }

	public BlockInstance getBlockInstance() {
		return owner;
	}
	
}
