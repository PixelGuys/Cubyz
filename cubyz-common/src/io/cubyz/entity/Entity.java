package io.cubyz.entity;

import org.joml.Vector3f;
import org.joml.Vector3i;

import io.cubyz.IRenderablePair;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.math.FloatingInteger;
import io.cubyz.math.Vector3fi;
import io.cubyz.ndt.NDTContainer;
import io.cubyz.world.World;

public abstract class Entity {

	protected World world;

	protected Vector3fi position = new Vector3fi();
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
	
	public Vector3fi getPosition() {
		return position;
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
	
	public IRenderablePair getRenderablePair() {
		return renderPair;
	}
	
	// port of IntegratedQuantum's mathematical works for collision detection
	// Thanks ;)
	protected float _getX(float x) {
		int absX = position.x + (int) Math.round(position.relX);
		int absY = (int) Math.floor(position.y + 0.5F);
		int absZ = position.z + (int) Math.round(position.relZ);
		float relX = position.relX +0.5F - Math.round(position.relX);
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
		BlockInstance bi = world.getBlock(x, y, z);
		if(bi != null && bi.getBlock().isSolid()) {
			return true;
		}
		return false;
	}
	
	//@SuppressWarnings("unchecked")
	public void update() {
		if (renderPair != null) {
			//Consumer<Entity> upd = (Consumer<Entity>) renderPair.get("renderPairUpdate");
			//upd.accept(this);
		}
	}
	
	// NDT related
	
	private NDTContainer saveVector(Vector3fi vec) {
		NDTContainer ndt = new NDTContainer();
		ndt.setFloatingInteger("x", new FloatingInteger(vec.x, vec.relX));
		ndt.setFloat("y", vec.y);
		ndt.setFloatingInteger("z", new FloatingInteger(vec.z, vec.relZ));
		return ndt;
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
		ndt.setFloat("x", vec.y);
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
	
}