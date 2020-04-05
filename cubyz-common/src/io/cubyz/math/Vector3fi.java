package io.cubyz.math;

import org.joml.Vector3f;

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
	
	public Vector3fi(float x, float y, float z) {
		this.x = (int)Math.floor(x);
		this.y = y;
		this.z = (int)Math.floor(z);
		relX = x-this.x;
		relZ = z-this.z;
	}
	
	public Vector3fi(FloatingInteger x, float y, FloatingInteger z) {
		this.x = x.getInteger();
		relX = x.getDecimal();
		this.y = y;
		this.z = z.getInteger();
		relZ = z.getDecimal();
	}
	
	public float x() {
		return x + relX;
	}
	
	public float y() {
		return y;
	}
	
	public float z() {
		return z + relZ;
	}
	
	public Vector3f toVector3f() {
		return new Vector3f(x+relX, y, z+relZ);
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
}
