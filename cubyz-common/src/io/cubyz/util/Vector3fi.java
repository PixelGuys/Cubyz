package io.cubyz.util;

public class Vector3fi {
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
	
	public Vector3fi(float x, float y, float z) {
		this.x = (int)Math.floor(x);
		this.y = y;
		this.z = (int)Math.floor(z);
		relX = x-this.x;
		relZ = z-this.z;
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
}
