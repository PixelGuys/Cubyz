package io.cubyz.world;

import org.joml.Vector3f;

import io.cubyz.blocks.BlockInstance;
import io.cubyz.client.Meshes;
import io.jungle.Spatial;

public class BlockSpatial extends Spatial {
	private static final Vector3f ZERO = new Vector3f(0, 0, 0);
	private BlockInstance owner;
	private Vector3f offset = ZERO; // Offset from the block center.
	
	public BlockSpatial(BlockInstance bi) {
		super(Meshes.blockMeshes.get(bi.getBlock()), bi.light);
		this.owner = bi;
	}
	
	public void setOffset(Vector3f offset) {
		this.offset = offset;
	}
	
	@Override
	public void setPosition(Vector3f position) {
		super.setPosition(position.sub(offset));
	}

	@Override
	public void setPosition(float x, float y, float z) {
        super.setPosition(x + offset.x, y + offset.y, z + offset.z);
    }

	public BlockInstance getBlockInstance() {
		return owner;
	}
	
}
