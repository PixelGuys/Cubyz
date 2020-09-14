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
						tmp.setPosition(bi.getX(), bi.getY() + 0.5f, bi.getZ(), player, worldSize);
						break;
					case 4:
						tmp.setRotation(PI, 0, 0);
						tmp.setPosition(bi.getX(), bi.getY() - 0.5f, bi.getZ(), player, worldSize);
						break;
					case 0:
						tmp.setRotation(0, 0, -PI_HALF);
						tmp.setPosition(bi.getX() - 0.5f, bi.getY(), bi.getZ(), player, worldSize);
						break;
					case 1:
						tmp.setRotation(0, 0, PI_HALF);
						tmp.setPosition(bi.getX() + 0.5f, bi.getY(), bi.getZ(), player, worldSize);
						break;
					case 2:
						tmp.setRotation(PI_HALF, 0, 0);
						tmp.setPosition(bi.getX(), bi.getY(), bi.getZ() - 0.5f, player, worldSize);
						break;
					case 3:
						tmp.setRotation(-PI_HALF, 0, 0);
						tmp.setPosition(bi.getX(), bi.getY(), bi.getZ() + 0.5f, player, worldSize);
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
