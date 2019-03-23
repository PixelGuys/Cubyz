package io.cubyz.entity;

import org.joml.AABBf;
import org.joml.Vector3f;
import org.joml.Vector3i;

import io.cubyz.api.CubzRegistries;
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
		super(CubzRegistries.ENTITY_REGISTRY.getByID("cubyz:"));
		this.local = local;
//		try {
//			mesh = loadMesh("uglyplayer");
//			Material mat = new Material(new Vector4f(0.1F, 0.5F, 0.5F, 0.0F), 1.0F);
//			mesh.setBoundingRadius(10.0F);
//			mesh.setMaterial(mat);
//		} catch (Exception e) {
//			e.printStackTrace();
//		}
//		spatial = new Spatial(mesh);
//		spatial.setScale(0.5F);
	}
	
	public boolean isLocal() {
		return local;
	}
	
	public void move(Vector3f inc, Vector3f rot) {
		if (inc.z != 0) {
			position.x += _getX((float) Math.sin(Math.toRadians(rot.y)) * -1.0F * inc.z);
			position.z += _getZ((float) Math.cos(Math.toRadians(rot.y)) * inc.z);
		}
		if (inc.x != 0) {
			position.x += _getX((float) Math.sin(Math.toRadians(rot.y - 90)) * -1.0F * inc.x);
			position.z += _getZ((float) Math.cos(Math.toRadians(rot.y - 90)) * inc.x);
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
		if (vy < 0) {
			Vector3i bp = new Vector3i((int) Math.round(position.x), (int) Math.floor(position.y), (int) Math.round(position.z));
			float relX = position.x + 0.5F - bp.x;
			float relZ = position.z + 0.5F - bp.z;
			if(checkBlock(bp.x, bp.y, bp.z)) {
				vy = 0;
			}
			else if (relX < 0.3) {
				if (checkBlock(bp.x - 1, bp.y, bp.z)) {
					vy = 0;
				}
				else if (relZ < 0.3 && checkBlock(bp.x - 1, bp.y, bp.z - 1)) {
					vy = 0;
				}
				else if (relZ > 0.7 && checkBlock(bp.x - 1, bp.y, bp.z + 1)) {
					vy = 0;
				}
			}
			else if (relX > 0.7) {
				if (checkBlock(bp.x + 1, bp.y, bp.z)) {
					vy = 0;
				}
				else if (relZ < 0.3 && checkBlock(bp.x + 1, bp.y, bp.z - 1)) {
					vy = 0;
				}
				else if (relZ > 0.7 && checkBlock(bp.x + 1, bp.y, bp.z + 1)) {
					vy = 0;
				}
			}
			if (relZ < 0.3 && checkBlock(bp.x, bp.y, bp.z - 1)) {
				vy = 0;
			}
			else if (relZ > 0.7 && checkBlock(bp.x, bp.y, bp.z + 1)) {
				vy = 0;
			}
		}
		position.add(0, vy, 0);
		if (flying) {
			vy = 0;
		}
	}
	
}
