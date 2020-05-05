package io.cubyz.entity;

import org.joml.Vector3f;
import org.joml.Vector3i;

import io.cubyz.blocks.Block;
import io.cubyz.math.FloatingInteger;
import io.cubyz.math.Vector3fi;
import io.cubyz.ndt.NDTContainer;
import io.cubyz.world.StellarTorus;

public class Entity {

	protected StellarTorus stellarTorus;

	protected Vector3fi position = new Vector3fi();
	protected Vector3f rotation = new Vector3f();
	private EntityAI ai;
	public float vx, vy, vz;
	
	private EntityType type;
	
	public int health, hunger, maxHealth, maxHunger;
	
	protected int width = 1, height = 2, depth = 1;
	
	public Entity(EntityType type) {
		this.type = type;
	}
	
	public Entity(EntityType type, EntityAI ai) {
		this.type = type;
		this.ai = ai;
	}
	
	/**
	 * check and update vertical velocity for collision.
	 */
	protected void updateVY() {
		if (vy < 0) {
			Vector3i bp = new Vector3i(position.x + (int) Math.round(position.relX), (int) Math.floor(position.y), position.z + (int) Math.round(position.relZ));
			float relX = position.relX +0.5F - Math.round(position.relX);
			float relZ = position.relZ + 0.5F- Math.round(position.relZ);
			if(isOnGround()) {
				stopVY();
			}
			else if (relX < 0.3) {
				if (checkBlock(bp.x - 1, bp.y, bp.z)) {
					stopVY();
				}
				else if (relZ < 0.3 && checkBlock(bp.x - 1, bp.y, bp.z - 1)) {
					stopVY();
				}
				else if (relZ > 0.7 && checkBlock(bp.x - 1, bp.y, bp.z + 1)) {
					stopVY();
				}
			}
			else if (relX > 0.7) {
				if (checkBlock(bp.x + 1, bp.y, bp.z)) {
					stopVY();
				}
				else if (relZ < 0.3 && checkBlock(bp.x + 1, bp.y, bp.z - 1)) {
					stopVY();
				}
				else if (relZ > 0.7 && checkBlock(bp.x + 1, bp.y, bp.z + 1)) {
					stopVY();
				}
			}
			if (relZ < 0.3 && checkBlock(bp.x, bp.y, bp.z - 1)) {
				stopVY();
			}
			else if (relZ > 0.7 && checkBlock(bp.x, bp.y, bp.z + 1)) {
				stopVY();
			}
			
			// I'm really annoyed by falling into the void and needing ages to get back up.
			if(bp.y < -100) {
				position.y = -100;
				stopVY();
			}
		} else if (vy > 0) {
			Vector3i bp = new Vector3i(position.x + (int) Math.round(position.relX), (int) Math.floor(position.y) + height, position.z + (int) Math.round(position.relZ));
			float relX = position.relX +0.5F - Math.round(position.relX);
			float relZ = position.relZ + 0.5F- Math.round(position.relZ);
			if(checkBlock(bp.x, bp.y, bp.z)) {
				vy = 0;
			} else if (relX < 0.3) {
				if (checkBlock(bp.x - 1, bp.y, bp.z)) {
					stopVY();
				}
				else if (relZ < 0.3 && checkBlock(bp.x - 1, bp.y, bp.z - 1)) {
					stopVY();
				}
				else if (relZ > 0.7 && checkBlock(bp.x - 1, bp.y, bp.z + 1)) {
					stopVY();
				}
			}
			else if (relX > 0.7) {
				if (checkBlock(bp.x + 1, bp.y, bp.z)) {
					stopVY();
				}
				else if (relZ < 0.3 && checkBlock(bp.x + 1, bp.y, bp.z - 1)) {
					stopVY();
				}
				else if (relZ > 0.7 && checkBlock(bp.x + 1, bp.y, bp.z + 1)) {
					stopVY();
				}
			}
			if (relZ < 0.3 && checkBlock(bp.x, bp.y, bp.z - 1)) {
				stopVY();
			}
			else if (relZ > 0.7 && checkBlock(bp.x, bp.y, bp.z + 1)) {
				stopVY();
			}
		}
	}
	
	public void stopVY() {
		health += calculateFallDamage();
		vy = 0;
	}
	
	public int calculateFallDamage() {
		if(vy < 0)
			return -(int)(8*vy*vy);
		return 0;
	}
	
	/**
	 * @author IntegratedQuantum
	 */
	protected float _getX(float x) {
		int absX = position.x + (int) Math.round(position.relX);
		int absY = (int) Math.floor(position.y + 0.5F);
		int absZ = position.z + (int) Math.round(position.relZ);
		float relX = position.relX + 0.5F - Math.round(position.relX);
		float relZ = position.relZ + 0.5F- Math.round(position.relZ);
		if (x < 0) {
			if (relX < 0.3F) {
				relX++;
				absX--;
			}
			
			if (relX+x > 0.3F) {
				return x;
			}
			
			if (relZ < 0.3) {
				for (int i = 0; i < height; i++) {
					if (checkBlock(absX - 1, absY + i, absZ - 1)) {
						return 0.30001F - relX;
					}
				}
			}
			if (relZ > 0.7) {
				for (int i = 0; i < height; i++) {
					if (checkBlock(absX - 1, absY + i, absZ + 1)) {
						return 0.30001F - relX;
					}
				}
			}
			for (int i = 0; i < height; i++) {
				if (checkBlock(absX - 1, absY + i, absZ)) {
					return 0.30001F - relX;
				}
			}
		}
		else {
			if (relX > 0.7F) {
				relX--;
				absX++;
			}
			
			if (relX+x < 0.7F) {
				return x;
			}
			
			if (relZ < 0.3) {
				for (int i = 0; i < height; i++) {
					if (checkBlock(absX + 1, absY + i, absZ - 1)) {
						return 0.69999F - relX;
					}
				}
			}
			if (relZ > 0.7) {
				for (int i = 0; i < height; i++) {
					if( checkBlock(absX + 1, absY + i, absZ + 1)) {
						return 0.69999F - relX;
					}
				}
			}
			for (int i = 0; i < height; i++) {
				if (checkBlock(absX + 1, absY + i, absZ)) {
					return 0.69999F - relX;
				}
			}
		}
		return x;
	}
	
	protected float _getZ(float z) {
		int absX = position.x + (int) Math.floor(position.relX + 0.5F);
		int absY = (int) Math.floor(position.y + 0.5F);
		int absZ = position.z + (int) Math.floor(position.relZ + 0.5F);
		float relX = position.relX +0.5F - Math.round(position.relX);
		float relZ = position.relZ + 0.5F- Math.round(position.relZ);
		if(z < 0) {
			if(relZ < 0.3F) {
				relZ++;
				absZ--;
			}
			if(relZ + z > 0.3F) {
				return z;
			}
			if(relX < 0.3) {
				for(int i = 0; i < height; i++) {
					if (checkBlock(absX - 1, absY + i, absZ - 1)) {
						return 0.30001F - relZ;
					}
				}
			}
			if(relX > 0.7) {
				for(int i = 0; i < height; i++) {
					if(checkBlock(absX+1, absY+i, absZ-1)) {
						return 0.30001F - relZ;
					}
				}
			}
			for(int i = 0; i < height; i++) {
				if(checkBlock(absX, absY+i, absZ-1)) {
					return 0.30001F - relZ;
				}
			}
		}
		else {
			if(relZ > 0.7F) {
				relZ--;
				absZ++;
			}
			if(relZ+z < 0.7F) {
				return z;
			}
			if(relX < 0.3) {
				for(int i = 0; i < height; i++) {
					if(checkBlock(absX-1, absY+i, absZ+1)) {
						return 0.69999F - relZ;
					}
				}
			}
			if(relX > 0.7) {
				for(int i = 0; i < height; i++) {
					if(checkBlock(absX+1, absY+i, absZ+1)) {
						return 0.69999F - relZ;
					}
				}
			}
			for(int i = 0; i < height; i++) {
				if(checkBlock(absX, absY+i, absZ+1)) {
					return 0.69999F - relZ;
				}
			}
		}
		return z;
	}
	
	public boolean checkBlock(int x, int y, int z) {
		Block bi = stellarTorus.getWorld().getCurrentTorus().getBlock(x, y, z);
		if(bi != null && bi.isSolid()) {
			return true;
		}
		return false;
	}
	
	public boolean isOnGround() {
		Vector3i bp = new Vector3i(position.x + (int) Math.round(position.relX), (int) Math.floor(position.y), position.z + (int) Math.round(position.relZ));
		return checkBlock(bp.x, bp.y, bp.z);
	}
	
	public void update() {
		if(ai != null)
			ai.update(this);
		updatePosition();
	}
	
	protected void updatePosition() {
		updateVY();
		position.add(_getX(vx), vy, _getZ(vz));
	}
	
	// NDT related
	
	private NDTContainer saveVector(Vector3fi vec) {
		NDTContainer ndt = new NDTContainer();
		ndt.setFloatingInteger("x", new FloatingInteger(vec.x, vec.relX));
		ndt.setFloat("y", vec.y);
		ndt.setFloatingInteger("z", new FloatingInteger(vec.z, vec.relZ));
		return ndt;
	}
	
	private NDTContainer runtimeNDT;
	
	/**
	 * NDT tag to store runtime data that will not persist through world save or loading.
	 */
	public NDTContainer getRuntimeNDT() {
		if (runtimeNDT == null) {
			runtimeNDT = new NDTContainer();
			runtimeNDT.setContainer("ai", new NDTContainer());
		}
		return runtimeNDT;
	}
	
	/**
	 * NDT tag reserved for AI use, it is stored in runtime using the runtime NDT.
	 * @see #getRuntimeNDT()
	 */
	public NDTContainer getAINDT() {
		return getRuntimeNDT().getContainer("ai");
	}
	
	private Vector3fi loadVector3fi(NDTContainer ndt) {
		FloatingInteger x = ndt.getFloatingInteger("x");
		float y = ndt.getFloat("y");
		FloatingInteger z = ndt.getFloatingInteger("z");
		return new Vector3fi(x, y, z);
	}
	
	private Vector3f loadVector3f(NDTContainer ndt) {
		float x = ndt.getFloat("x");
		float y = ndt.getFloat("y");
		float z = ndt.getFloat("z");
		return new Vector3f(x, y, z);
	}
	
	private NDTContainer saveVector(Vector3f vec) {
		NDTContainer ndt = new NDTContainer();
		ndt.setFloat("x", vec.x);
		ndt.setFloat("y", vec.y);
		ndt.setFloat("z", vec.y);
		return ndt;
	}
	
	public NDTContainer saveTo(NDTContainer ndt) {
		ndt.setContainer("position", saveVector(position));
		ndt.setContainer("rotation", saveVector(rotation));
		ndt.setContainer("velocity", saveVector(new Vector3f(vx, vy, vz)));
		return ndt;
	}
	
	public void loadFrom(NDTContainer ndt) {
		position = loadVector3fi(ndt.getContainer("position"));
		rotation = loadVector3f (ndt.getContainer("rotation"));
		Vector3f velocity = loadVector3f(ndt.getContainer("velocity"));
		vx = velocity.x; vy = velocity.y; vz = velocity.z;
	}
	
	public EntityType getType() {
		return type;
	}
	
	public StellarTorus getStellarTorus() {
		return stellarTorus;
	}

	public void setStellarTorus(StellarTorus world) {
		this.stellarTorus = world;
	}
	
	public Vector3fi getPosition() {
		return position;
	}
	
	public Vector3f getRenderPosition(Vector3fi playerPos) { // default method for render pos
		return new Vector3f((position.x-playerPos.x)+position.relX-playerPos.relX, position.y-playerPos.y, (position.z-playerPos.z)+position.relZ-playerPos.relZ);
	}
	
	public void setPosition(Vector3i position) {
		this.position.x = position.x;
		this.position.y = position.y;
		this.position.z = position.z;
	}
	
	public void setPosition(Vector3fi position) {
		this.position = position;
	}
	
	public Vector3f getRotation() {
		return rotation;
	}
	
	public void setRotation(Vector3f rotation) {
		this.rotation = rotation;
	}
	
}