package io.cubyz.entity;

import java.util.function.Consumer;

import org.joml.AABBf;
import org.joml.Vector3f;

import io.cubyz.IRenderablePair;
import io.cubyz.world.World;

public abstract class Entity {

	protected String registryName;
	protected float entitySpeed;
	protected World world;
	
	protected AABBf aabb = new AABBf();
	protected Vector3f position = new Vector3f();
	protected Vector3f rotation = new Vector3f();
	public float vx, vy, vz;
	
	protected IRenderablePair renderPair;
	
	protected int width = 1, height = 2;
	
	public float getSpeed() {
		return entitySpeed;
	}
	
	public World getWorld() {
		return world;
	}

	public void setWorld(World world) {
		this.world = world;
	}

	public String getRegistryName() {
		return registryName;
	}
	
	public void setRegistryName(String registryName) {
		this.registryName = registryName;
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
	
	public void update() {
		aabb.minX = position.x();
		aabb.maxX = position.x() + width;
		aabb.minY = position.y();
		aabb.maxY = position.y() + height;
		aabb.minZ = position.z();
		aabb.maxZ = position.z() + width;
		//spatial.setPosition(position.x(), position.y(), position.z());
		//spatial.setRotation(rotation.x(), rotation.y(), rotation.z());
		
		if (renderPair != null) {
			Consumer<Entity> upd = (Consumer<Entity>) renderPair.get("renderPairUpdate");
			upd.accept(this);
		}
	}
	
}