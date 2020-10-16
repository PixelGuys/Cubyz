package io.cubyz.entity;

import org.joml.Matrix4f;
import org.joml.Vector3f;

import io.cubyz.api.RegistryElement;

/**
 * Used to animate the 3d model of entities.
 */

public interface EntityModel extends RegistryElement {
	public void render(Matrix4f viewMatrix, Object shaderProgram, Entity ent);
	public EntityModel createInstance(String data, EntityType source);
	public void update(Entity ent);
	/**
	 * Should return Float.MAX_VALUE if no collision happens.
	 */
	public float getCollisionDistance(Vector3f playerPosition, Vector3f direction, Entity ent);
}
