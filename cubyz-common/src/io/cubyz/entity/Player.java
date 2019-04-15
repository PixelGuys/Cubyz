package io.cubyz.entity;

import org.joml.Vector3f;
import org.joml.Vector3i;

import io.cubyz.api.CubzRegistries;
import io.cubyz.command.ICommandSource;

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
		float deltaX = 0;
		float deltaZ = 0;
		if (inc.z != 0) {
			deltaX += _getX((float) Math.sin(Math.toRadians(rot.y)) * -1.0F * inc.z);
			deltaZ += _getZ((float) Math.cos(Math.toRadians(rot.y)) * inc.z);
		}
		if (inc.x != 0) {
			deltaX += _getX((float) Math.sin(Math.toRadians(rot.y - 90)) * -1.0F * inc.x);
			deltaZ += _getZ((float) Math.cos(Math.toRadians(rot.y - 90)) * inc.x);
		}
		if (inc.y != 0) {
			vy = inc.y;
		}
		position.add(deltaX, 0, deltaZ);
	}
	
	@Override
	public void update() {
		super.update();
		if (!flying) {
			vy -= 0.015F;
		}
		// if(flying) {
		// vy = 0;
		// position.y = 200;
		//}
		if (vy < 0) {
			Vector3i bp = new Vector3i(position.x + (int) Math.round(position.relX), (int) Math.floor(position.y), position.z + (int) Math.round(position.relZ));
			float relX = position.relX +0.5F - Math.round(position.relX);
			float relZ = position.relZ + 0.5F- Math.round(position.relZ);
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
