package io.cubyz.math;

public class Vector3fi implements Cloneable {
	
	public int x, z;
	public float y, relX, relZ;
	
	public Vector3fi() {
		x = 0;
		y = 0;
		z = 0;
		relX = 0;
		relZ = 0;
	}
	
	public Vector3fi(int x, float y, int z) {
		this.x = x;
		this.y = y;
		this.z = z;
		relX = 0;
		relZ = 0;
	}
	
	public Vector3fi(int x, float y, int z, float relX, float relZ) {
		this.x = x;
		this.y = y;
		this.z = z;
		this.relX = relX;
		this.relZ = relZ;
	}
	
	public Vector3fi(FloatingInteger x, float y, FloatingInteger z) {
		this.x = x.getInteger();
		relX = x.getDecimal();
		this.y = y;
		this.z = z.getInteger();
		relZ = z.getDecimal();
	}
	
	public void add(float x, float y, float z) {
		relX += x;
		this.y += y;
		relZ += z;
		int floorX = (int)Math.floor(relX);
		int floorZ = (int)Math.floor(relZ);
		if(floorX != 0) {
			this.x += floorX;
			relX -= floorX;
		}
		if(floorZ != 0) {
			this.z += floorZ;
			relZ -= floorZ;
		}
	}
	
	public Vector3fi clone() {
		return new Vector3fi(new FloatingInteger(x, relX), y, new FloatingInteger(z, relZ));
	}
	
	public float getDistance(Vector3fi other) {
		float deltaX = (x - other.x) + relX - other.relX;
		float deltaY = (y - other.y);
		float deltaZ = (z - other.z) + relZ - other.relZ;
		return (float)Math.sqrt(deltaX*deltaX + deltaY*deltaY + deltaZ*deltaZ);
	}
}
