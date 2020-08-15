package io.cubyz.base.rotation;

import org.joml.Vector3i;

import io.cubyz.api.Resource;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.blocks.RotationMode;
import io.cubyz.entity.Player;
import io.cubyz.world.BlockSpatial;

public class TransparentRotation implements RotationMode {
	private static final float PI = (float)Math.PI;
	private static final float PI_HALF = PI/2;
	
	Resource id = new Resource("cubyz", "transparent");
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
		BlockSpatial[] spatials = new BlockSpatial[6];
		int total = 0;
		for(int i = 0; i < 6; i++) {
			if(!bi.getNeighbors()[i]) {
				BlockSpatial tmp = new BlockSpatial(bi, player, worldSize);
				switch(i) {
					default:
						break;
					case 4:
						tmp.setRotation(PI, 0, 0);
						break;
					case 0:
						tmp.setRotation(0, 0, -PI_HALF);
						break;
					case 1:
						tmp.setRotation(0, 0, PI_HALF);
						break;
					case 2:
						tmp.setRotation(PI_HALF, 0, 0);
						break;
					case 3:
						tmp.setRotation(-PI_HALF, 0, 0);
						break;
				}
				spatials[i] = tmp;
				total++;
			}
		}
		BlockSpatial[] out = new BlockSpatial[total];
		total = 0;
		for(int i = 0; i < 6; i++) {
			if(spatials[i] != null) {
				out[total++] = spatials[i];
			}
		}
		return out;
	}

	@Override
	public boolean dependsOnNeightbors() {
		return true;
	}

	@Override
	public Byte updateData(byte data, int dir) {
		return 0;
	}
}
