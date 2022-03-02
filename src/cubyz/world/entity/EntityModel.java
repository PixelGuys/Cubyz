package cubyz.world.entity;

import org.joml.Matrix4f;
import org.joml.Vector3d;
import org.joml.Vector3f;

import cubyz.api.RegistryElement;
import cubyz.client.entity.ClientEntity;

/**
 * Used to animate the 3d model of entities.
 */

public interface EntityModel extends RegistryElement {
	void render(Matrix4f viewMatrix, Object shaderProgram, ClientEntity ent);
	EntityModel createInstance(String data, EntityType source);
	void update(ClientEntity ent, float deltaTime);
	/**
	 * Should return Double.MAX_VALUE if no collision happens.
	 */
	double getCollisionDistance(Vector3d playerPosition, Vector3f direction, Entity ent);
}
