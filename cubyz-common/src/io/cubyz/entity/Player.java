package io.cubyz.entity;

import org.joml.AABBf;
import org.joml.Vector3f;
import org.joml.Vector3i;

import io.cubyz.command.ICommandSource;

//NOTE: Player is 2 Blocks Tall (2 Meters)
public class Player extends Entity implements ICommandSource {

	private boolean local = false;
	private boolean flying = false;
	
	public boolean isFlying() {
		return flying;
	}
	
	public void setFlying(boolean fly) {
		flying = fly;
	}
	
	public Player(boolean local) {
		this.local = local;
//		try {
//			mesh = loadMesh("uglyplayer");
//			Material mat = new Material(new Vector4f(0.1F, 0.5F, 0.5F, 0.0F), 1.0F); //NOTE: Normal > 0.1F || 0.5F || 0.5F || 0.0F || 1.0F
//			mesh.setBoundingRadius(10.0F); //NOTE: Normal > 10.0F
//			mesh.setMaterial(mat);
//		} catch (Exception e) {
//			e.printStackTrace();
//		}
//		spatial = new Spatial(mesh);
//		spatial.setScale(0.5F); //NOTE: Normal > 0.5F
		setRegistryName("cubz:player");
	}
	
	public boolean isLocal() {
		return local;
	}
	
	public void move(Vector3f inc, Vector3f rot) {
		if (inc.z != 0) {
			position.x += (float) Math.sin(Math.toRadians(rot.y)) * -1.0F * inc.z; //NOTE: Normal > -1.0F
			position.z += (float) Math.cos(Math.toRadians(rot.y)) * inc.z;
		}
		if (inc.x != 0) {
			position.x += (float) Math.sin(Math.toRadians(rot.y - 90)) * -1.0F * inc.x; //NOTE: Normal > 90 || -1.0F
			position.z += (float) Math.cos(Math.toRadians(rot.y - 90)) * inc.x; //NOTE: Normal > 90
		}
		if (inc.y != 0) {
			vy = inc.y;
		}
	}
	
	@Override
	public void update() {
		super.update();
		if (!flying) {
			vy -= 0.015F;
		}
		Vector3i bp = new Vector3i((int) Math.ceil(position.x), (int) Math.ceil(position.y)-1, (int) Math.ceil(position.z));
		if (world.getBlock(bp) != null) {
			AABBf other = new AABBf();
			other.setMin(new Vector3f(bp));
			other.setMax(new Vector3f(bp.x + 1.0F, bp.y + 1.0F, bp.z + 1.0F)); //NOTE: Normal > 1.0F || 1.0F || 1.0F
			boolean b = aabb.testAABB(other);
			if (b) {
				if (vy < 0) {
					vy = 0;
				}
			}
		}
		position.add(0, vy, 0);
		if (flying) {
			vy = 0;
		}
	}
	
}
