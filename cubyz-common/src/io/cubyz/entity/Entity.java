package io.cubyz.entity;

import org.joml.Vector3f;
import org.joml.Vector3i;

import io.cubyz.blocks.Block;
import io.cubyz.items.Inventory;
import io.cubyz.items.tools.Tool;
import io.cubyz.ndt.NDTContainer;
import io.cubyz.world.StellarTorus;
import io.cubyz.world.Surface;

public class Entity {

	protected Surface surface;

	protected Vector3f position = new Vector3f();
	protected Vector3f rotation = new Vector3f();
	private EntityAI ai;
	public float vx, vy, vz;
	public float targetVX, targetVZ; // The velocity the AI wants the entity to have.
	protected float scale = 1f;
	public float movementAnimation = 0; // Only used by mobs that actually move.
	
	private EntityType type;
	
	public float health, hunger, maxHealth, maxHunger;
	
	protected float width = 1, height = 2, depth = 1;
	
	protected float minBlock = 0.3f, maxBlock = 0.7f;
	
	public float pickupRange = 2; // Important if this entity can pickup items.
	
	public Entity(EntityType type, Surface surface) {
		this.type = type;
		this.surface = surface;
	}
	
	public float getScale() {
		return scale;
	}
	
	public Entity(EntityType type, Surface surface, EntityAI ai) {
		this.type = type;
		this.surface = surface;
		this.ai = ai;
	}
	
	/**
	 * check and update vertical velocity for collision.
	 */
	protected void updateVY() {
		int absX = Math.round(position.x);
		int absZ = Math.round(position.z);
		float relX = position.x + 0.5f - absX;
		float relZ = position.z + 0.5f - absZ;
		if (vy < 0) {
			int absY = Math.round(position.y);
			if(isOnGround()) {
				stopVY();
			}
			else if (relX < minBlock) {
				if (checkBlock(absX - 1, absY, absZ)) {
					stopVY();
				}
				else if (relZ < minBlock && checkBlock(absX - 1, absY, absZ - 1)) {
					stopVY();
				}
				else if (relZ > maxBlock && checkBlock(absX - 1, absY, absZ + 1)) {
					stopVY();
				}
			}
			else if (relX > maxBlock) {
				if (checkBlock(absX + 1, absY, absZ)) {
					stopVY();
				}
				else if (relZ < minBlock && checkBlock(absX + 1, absY, absZ - 1)) {
					stopVY();
				}
				else if (relZ > maxBlock && checkBlock(absX + 1, absY, absZ + 1)) {
					stopVY();
				}
			}
			if (relZ < minBlock && checkBlock(absX, absY, absZ - 1)) {
				stopVY();
			}
			else if (relZ > maxBlock && checkBlock(absX, absY, absZ + 1)) {
				stopVY();
			}
			
			// I'm really annoyed by falling into the void and needing ages to get back up.
			if(absY < -100) {
				position.y = -100;
				stopVY();
			}
		} else if (vy > 0) {
			int absY = (int) Math.floor(position.y + height);
			if(checkBlock(absX, absY, absZ)) {
				vy = 0;
			} else if (relX < minBlock) {
				if (checkBlock(absX - 1, absY, absZ)) {
					stopVY();
				}
				else if (relZ < minBlock && checkBlock(absX - 1, absY, absZ - 1)) {
					stopVY();
				}
				else if (relZ > maxBlock && checkBlock(absX - 1, absY, absZ + 1)) {
					stopVY();
				}
			}
			else if (relX > maxBlock) {
				if (checkBlock(absX + 1, absY, absZ)) {
					stopVY();
				}
				else if (relZ < minBlock && checkBlock(absX + 1, absY, absZ - 1)) {
					stopVY();
				}
				else if (relZ > maxBlock && checkBlock(absX + 1, absY, absZ + 1)) {
					stopVY();
				}
			}
			if (relZ < minBlock && checkBlock(absX, absY, absZ - 1)) {
				stopVY();
			}
			else if (relZ > maxBlock && checkBlock(absX, absY, absZ + 1)) {
				stopVY();
			}
		}
	}
	/**
	 * All damage taken should get channeled through this function to remove redundant checks if the entity is dead.
	 * @param amount
	 */
	public void takeDamage(float amount) {
		health -= amount;
		if(health <= 0) {
			type.die(this);
		}
	}
	
	public void stopVY() {
		takeDamage(calculateFallDamage());
		vy = 0;
	}
	
	public int calculateFallDamage() {
		if(vy < 0)
			return (int)(8*vy*vy);
		return 0;
	}
	
	/**
	 * @author IntegratedQuantum
	 */
	protected float _getX(float x) {
		int absX = Math.round(position.x);
		int absY = Math.round(position.y + 0.5f);
		int absZ = Math.round(position.z);
		float relX = position.x + 0.5f - absX;
		float relZ = position.z + 0.5f - absZ;
		if (x < 0) {
			if (relX < minBlock) {
				relX++;
				absX--;
			}
			
			if (relX+x > minBlock) {
				return x;
			}
			
			if (relZ < minBlock) {
				for (int i = 0; i < height; i++) {
					if (checkBlock(absX - 1, absY + i, absZ - 1)) {
						return minBlock + 0.0001F - relX;
					}
				}
			}
			if (relZ > maxBlock) {
				for (int i = 0; i < height; i++) {
					if (checkBlock(absX - 1, absY + i, absZ + 1)) {
						return minBlock + 0.0001F - relX;
					}
				}
			}
			for (int i = 0; i < height; i++) {
				if (checkBlock(absX - 1, absY + i, absZ)) {
					return minBlock + 0.0001F - relX;
				}
			}
		}
		else {
			if (relX > maxBlock) {
				relX--;
				absX++;
			}
			
			if (relX+x < maxBlock) {
				return x;
			}
			
			if (relZ < minBlock) {
				for (int i = 0; i < height; i++) {
					if (checkBlock(absX + 1, absY + i, absZ - 1)) {
						return maxBlock - 0.0001f - relX;
					}
				}
			}
			if (relZ > maxBlock) {
				for (int i = 0; i < height; i++) {
					if( checkBlock(absX + 1, absY + i, absZ + 1)) {
						return maxBlock - 0.0001f - relX;
					}
				}
			}
			for (int i = 0; i < height; i++) {
				if (checkBlock(absX + 1, absY + i, absZ)) {
					return maxBlock - 0.0001f - relX;
				}
			}
		}
		return x;
	}
	
	protected float _getZ(float z) {
		int absX = Math.round(position.x);
		int absY = Math.round(position.y + 0.5f);
		int absZ = Math.round(position.z);
		float relX = position.x + 0.5f - absX;
		float relZ = position.z + 0.5f - absZ;
		if(z < 0) {
			if(relZ < minBlock) {
				relZ++;
				absZ--;
			}
			if(relZ + z > minBlock) {
				return z;
			}
			if(relX < minBlock) {
				for(int i = 0; i < height; i++) {
					if (checkBlock(absX - 1, absY + i, absZ - 1)) {
						return minBlock + 0.0001F - relZ;
					}
				}
			}
			if(relX > maxBlock) {
				for(int i = 0; i < height; i++) {
					if(checkBlock(absX + 1, absY + i, absZ - 1)) {
						return minBlock + 0.0001F - relZ;
					}
				}
			}
			for(int i = 0; i < height; i++) {
				if(checkBlock(absX, absY + i, absZ - 1)) {
					return minBlock + 0.0001F - relZ;
				}
			}
		}
		else {
			if(relZ > maxBlock) {
				relZ--;
				absZ++;
			}
			if(relZ+z < maxBlock) {
				return z;
			}
			if(relX < minBlock) {
				for(int i = 0; i < height; i++) {
					if(checkBlock(absX - 1, absY + i, absZ + 1)) {
						return maxBlock - 0.0001f - relZ;
					}
				}
			}
			if(relX > maxBlock) {
				for(int i = 0; i < height; i++) {
					if(checkBlock(absX + 1, absY + i, absZ + 1)) {
						return maxBlock - 0.0001f - relZ;
					}
				}
			}
			for(int i = 0; i < height; i++) {
				if(checkBlock(absX, absY + i, absZ + 1)) {
					return maxBlock - 0.0001f - relZ;
				}
			}
		}
		return z;
	}
	
	public boolean checkBlock(int x, int y, int z) {
		Block bi = surface.getBlock(x, y, z);
		if(bi != null && bi.isSolid()) {
			return true;
		}
		return false;
	}
	
	public boolean isOnGround() {
		return checkBlock(Math.round(position.x), Math.round(position.y), Math.round(position.z));
	}
	
	public void hit(Tool weapon, Vector3f direction) {
		if(weapon == null) {
			takeDamage(1);
			vx += direction.x*0.2;
			vy += direction.y*0.2;
			vz += direction.z*0.2;
		} else {
			takeDamage(weapon.getDamage());
			// TODO: Weapon specific knockback.
			vx += direction.x*0.2;
			vy += direction.y*0.2;
			vz += direction.z*0.2;
		}
	}
	
	public void update() {
		if(ai != null)
			ai.update(this);
		updatePosition();
		updateVelocity();
		
		// clamp health between 0 and maxHealth
		if (health < 0)
			health = 0;
		if (health > maxHealth)
			health = maxHealth;
	}
	
	protected void updatePosition() {
		updateVY();
		position.add(_getX(vx), vy, _getZ(vz));
	}
	
	protected void updateVelocity() {
		// TODO: Use the entities mass and force to calculate a realistic velocity change.
		vx += (targetVX-vx)/5;
		vz += (targetVZ-vz)/5;
	}
	
	// NDT related
	
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
		ndt.setFloat("health", health);
		return ndt;
	}
	
	public void loadFrom(NDTContainer ndt) {
		position = loadVector3f(ndt.getContainer("position"));
		rotation = loadVector3f (ndt.getContainer("rotation"));
		Vector3f velocity = loadVector3f(ndt.getContainer("velocity"));
		vx = velocity.x; vy = velocity.y; vz = velocity.z;
		health = ndt.getFloat("health");
	}
	
	public EntityType getType() {
		return type;
	}
	
	public StellarTorus getStellarTorus() {
		return surface.getStellarTorus();
	}
	
	public Vector3f getPosition() {
		return position;
	}
	
	public Vector3f getRenderPosition() { // default method for render pos
		return new Vector3f(position.x, position.y + height/2, position.z);
	}
	
	public void setPosition(Vector3i position) {
		this.position.x = position.x;
		this.position.y = position.y;
		this.position.z = position.z;
	}
	
	public void setPosition(Vector3f position) {
		this.position = position;
	}
	
	public Vector3f getRotation() {
		return rotation;
	}
	
	public void setRotation(Vector3f rotation) {
		this.rotation = rotation;
	}
	
	public Inventory getInventory() {
		return null;
	}
	
}