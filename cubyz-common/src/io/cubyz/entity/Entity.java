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
	public float vx, vy, vz;
	public float targetVX, targetVZ; // The velocity the AI wants the entity to have.
	protected float scale = 1f;
	public float movementAnimation = 0; // Only used by mobs that actually move.
	
	private final EntityType type;
	
	public float health, hunger;
	public final float maxHealth, maxHunger;
	
	/**
	 * Used as hitbox.
	 */
	protected float width = 0.25f, height = 1.8f;
	
	public float pickupRange = 2; // Important if this entity can pickup items.
	
	public Entity(EntityType type, Surface surface, float maxHealth, float maxHunger) {
		this.type = type;
		this.surface = surface;
		this.maxHealth = health = maxHealth;
		this.maxHunger = hunger = maxHunger;
	}
	
	public float getScale() {
		return scale;
	}
	
	/**
	 * Checks collision against all blocks within the hitbox and updates positions.
	 */
	protected void collisionDetection() {
		// Simulate movement in all directions and prevent movement in a direction that would get the player into a block:
		int minX = Math.round(position.x - width);
		int maxX = Math.round(position.x + width);
		int minY = Math.round(position.y);
		int maxY = Math.round(position.y + height);
		int minZ = Math.round(position.z - width);
		int maxZ = Math.round(position.z + width);
		if(vx < 0) {
			int minX2 = Math.round(position.x - width + vx);
			if(minX2 != minX) {
				outer:
				for(int y = minY; y <= maxY; y++) {
					for(int z = minZ; z <= maxZ; z++) {
						if(checkBlock(minX2, y, z)) {
							vx = 0;
							position.x = minX2 + 0.51f + width;
							break outer;
						}
					}
				}
			}
		} else if(vx > 0) {
			int maxX2 = Math.round(position.x + width + vx);
			if(maxX2 != maxX) {
				outer:
				for(int y = minY; y <= maxY; y++) {
					for(int z = minZ; z <= maxZ; z++) {
						if(checkBlock(maxX2, y, z)) {
							vx = 0;
							position.x = maxX2 - 0.51f - width;
							break outer;
						}
					}
				}
			}
		}
		position.x += vx;
		minX = Math.round(position.x - width);
		maxX = Math.round(position.x + width);
		if(vy < 0) {
			int minY2 = Math.round(position.y + vy);
			if(minY2 != minY) {
				outer:
				for(int x = minX; x <= maxX; x++) {
					for(int z = minZ; z <= maxZ; z++) {
						if(checkBlock(x, minY2, z)) {
							vy = 0;
							position.y = minY2 + 0.51f;
							break outer;
						}
					}
				}
			}
		} else if(vy > 0) {
			int maxY2 = Math.round(position.y + height + vy);
			if(maxY2 != maxY) {
				outer:
				for(int x = minX; x <= maxX; x++) {
					for(int z = minZ; z <= maxZ; z++) {
						if(checkBlock(x, maxY2, z)) {
							vy = 0;
							position.y = maxY2 - 0.51f - height;
							break outer;
						}
					}
				}
			}
		}
		position.y += vy;
		minY = Math.round(position.y);
		maxY = Math.round(position.y + height);
		if(vz < 0) {
			int minZ2 = Math.round(position.z - width + vz);
			if(minZ2 != minZ) {
				outer:
				for(int x = minX; x <= maxX; x++) {
					for(int y = minY; y <= maxY; y++) {
						if(checkBlock(x, y, minZ2)) {
							vz = 0;
							position.z = minZ2 + 0.51f + width;
							break outer;
						}
					}
				}
			}
		} else if(vz > 0) {
			int maxZ2 = Math.round(position.z + width + vz);
			if(maxZ2 != maxZ) {
				outer:
				for(int x = minX; x <= maxX; x++) {
					for(int y = minY; y <= maxY; y++) {
						if(checkBlock(x, y, maxZ2)) {
							vz = 0;
							position.z = maxZ2 - 0.51f - width;
							break outer;
						}
					}
				}
			}
		}
		position.z += vz;
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
	
	public boolean checkBlock(int x, int y, int z) {
		Block bi = surface.getBlock(x, y, z);
		if(bi != null && bi.isSolid()) {
			Vector3f distance = new Vector3f(position);
			distance.sub(x, y, z);
			if(bi.mode.changesHitbox()) {
				
			}
			return true;
		}
		return false;
	}
	
	public boolean isOnGround() {
		return checkBlock(Math.round(position.x), Math.round(position.y), Math.round(position.z)) || ((position.y + 0.5f) % 1 < 0.1f && checkBlock(Math.round(position.x), Math.round(position.y) - 1, Math.round(position.z)));
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
		collisionDetection();
		type.update(this);
		updateVelocity();

		// clamp health between 0 and maxHealth
		if (health < 0)
			health = 0;
		if (health > maxHealth)
			health = maxHealth;
		
		if(maxHunger > 0) {
			hungerMechanics();
		}
	}
	
	float oldVY = 0;
	/**
	 * Simulates the hunger system. TODO: Make dependent on mass
	 */
	protected void hungerMechanics() {
		// Passive energy consumption:
		hunger -= 0.0004; // Will deplete hunger after 22 minutes of standing still.
		// Energy consumption due to movement:
		hunger -= (vx*vx + vz*vz)/16;
		
		// Jumping:
		if(oldVY < vy) { // Only care about positive changes.
			// Determine the difference in "signed" kinetic energy.
			float deltaE = vy*vy*Math.signum(vy) - oldVY*oldVY*Math.signum(oldVY);
			hunger -= deltaE;
		}
		oldVY = vy;
		
		// Examples:
		// At 3 blocks/second(player base speed) the cost of movement is about twice as high as the passive consumption.
		// So when walking on a flat ground in one direction without sprinting the hunger bar will be empty after 22/3≈7 minutes.
		// When sprinting however the speed is twice as high, so the energy consumption is 4 times higher, meaning the hunger will be empty after only 2 minutes.
		// Jumping takes 0.05 hunger on jump and on land.

		// Heal if hunger is more than half full:
		if(hunger > maxHunger/2 && health < maxHealth) {
			// Maximum healing effect is 1% maxHealth per second:
			float healing = Math.min(maxHealth*0.01f/30, maxHealth-health);
			health += healing;
			hunger -= healing;
		}
		// Eat into health when the hunger bar is empty:
		if(hunger < 0) {
			health += hunger;
			hunger = 0;
		}
	}
	
	protected void updateVelocity() {
		// TODO: Use the entities mass, force and ground structure to calculate a realistic velocity change.
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
		ndt.setFloat("hunger", hunger);
		return ndt;
	}
	
	public void loadFrom(NDTContainer ndt) {
		position = loadVector3f(ndt.getContainer("position"));
		rotation = loadVector3f (ndt.getContainer("rotation"));
		Vector3f velocity = loadVector3f(ndt.getContainer("velocity"));
		vx = velocity.x; vy = velocity.y; vz = velocity.z;
		health = ndt.getFloat("health");
		hunger = ndt.getFloat("hunger");
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