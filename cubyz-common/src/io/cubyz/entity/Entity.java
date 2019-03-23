package io.cubyz.entity;

import java.util.function.Consumer;

import org.joml.AABBf;
import org.joml.Vector3f;

import io.cubyz.IRenderablePair;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.world.World;

public abstract class Entity {

	protected World world;
	
	protected Vector3f position = new Vector3f();
	protected Vector3f rotation = new Vector3f();
	public float vx, vy, vz;
	
	protected IRenderablePair renderPair;
	
	private EntityType type;
	
	protected int width = 1, height = 2, depth = 1;
	
	public Entity(EntityType type) {
		this.type = type;
	}
	
	public EntityType getType() {
		return type;
	}
	
	public World getWorld() {
		return world;
	}

	public void setWorld(World world) {
		this.world = world;
	}
	
	public Vector3f getPosition() {
		return position;
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
	
	public IRenderablePair getRenderablePair() {
		return renderPair;
	}
	
	// port of IntegratedQuantum's mathematical works for collision detection
	// Thanks ;)
	protected float _getX(float x) {
		float wi = (float) width;
		float he = (float) height;
		int absX = (int) Math.floor(position.x + 0.5F);
		int absY = (int) Math.floor(position.y + 0.5F);
		int absZ = (int) Math.floor(position.z + 0.5F);
		float relX = position.x + 0.5F - absX;
		float relZ = position.z + 0.5F - absZ;
		if (x < 0) {
			if (relX < 0.3F) {
				relX++;
				absX--;
			}
			
			if (relX+x > 0.3F) {
				return x;
			}
			
			float maxX = 0.301F - relX;	// This small deviation from the desired value is to prevent imprecision in float calculation to create bugs.
			if (relZ < 0.3) {
				for (int i = 0; i < 3; i++) {
					if (checkBlock(absX - 1, absY + i, absZ - 1)) {
						return maxX;
					}
				}
			}
			if (relZ > 0.7) {
				for (int i = 0; i < 3; i++) {
					if (checkBlock(absX - 1, absY + i, absZ + 1)) {
						return maxX;
					}
				}
			}
			for (int i = 0; i < 3; i++) {
				if (checkBlock(absX - 1, absY + i, absZ)) {
					return maxX;
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
			
			float maxX = 0.699F - relX;
			if (relZ < 0.3) {
				for (int i = 0; i < 3; i++) {
					if (checkBlock(absX + 1, absY + i, absZ - 1)) {
						return maxX;
					}
				}
			}
			if (relZ > 0.7) {
				for (int i = 0; i < 3; i++) {
					if( checkBlock(absX + 1, absY + i, absZ + 1)) {
						return maxX;
					}
				}
			}
			for (int i = 0; i < 3; i++) {
				if (checkBlock(absX + 1, absY + i, absZ)) {
					return maxX;
				}
			}
		}
		return x;
	}
	
	protected float _getZ(float z) {
		int absX = (int) Math.floor(position.x + 0.5F);
		int absY = (int) Math.floor(position.y + 0.5F);
		int absZ = (int) Math.floor(position.z + 0.5F);
		float relX = position.x + 0.5F - absX;
		float relZ = position.z + 0.5F - absZ;
		if(z < 0) {
			if(relZ < 0.3F) {
				relZ++;
				absZ--;
			}
			if(relZ + z > 0.3F) {
				return z;
			}
			float maxZ = 0.301F - relZ;
			if(relX < 0.3) {
				for(int i = 0; i < 3; i++) {
					if (checkBlock(absX - 1, absY + i, absZ - 1)) {
						return maxZ;
					}
				}
			}
			if(relX > 0.7) {
				for(int i = 0; i < 3; i++) {
					if(checkBlock(absX+1, absY+i, absZ-1)) {
						return maxZ;
					}
				}
			}
			for(int i = 0; i < 3; i++) {
				if(checkBlock(absX, absY+i, absZ-1)) {
					return maxZ;
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
			float maxZ = 0.699F - relZ;
			if(relX < 0.3) {
				for(int i = 0; i < 3; i++) {
					if(checkBlock(absX-width, absY+i, absZ+depth)) {
						return maxZ;
					}
				}
			}
			if(relX > 0.7) {
				for(int i = 0; i < height; i++) {
					if(checkBlock(absX+width, absY+i, absZ+depth)) {
						return maxZ;
					}
				}
			}
			for(int i = 0; i < height; i++) {
				if(checkBlock(absX, absY+i, absZ+depth)) {
					return maxZ;
				}
			}
		}
		return z;
	}
	
	public boolean checkBlock(int x, int y, int z) {
		BlockInstance bi = world.getBlock(x, y, z);
		if(bi != null && bi.getBlock().isSolid()) {
			return true;
		}
		return false;
	}
	
	public void update() {
		if (renderPair != null) {
			Consumer<Entity> upd = (Consumer<Entity>) renderPair.get("renderPairUpdate");
			upd.accept(this);
		}
	}
	
}