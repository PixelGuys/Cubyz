package cubyz.client.entity;

import cubyz.utils.interpolation.EntityInterpolation;
import org.joml.Vector3d;
import org.joml.Vector3f;

import cubyz.world.entity.EntityType;

public class ClientEntity {
	public final EntityInterpolation interpolatedValues;

	public final double height;
	
	public final EntityType type;

	public final Vector3d position;
	public final Vector3f rotation;
	
	public Vector3d getRenderPosition() { // default method for render pos
		return new Vector3d(position.x, position.y + height/2, position.z);
	}

	public final int id;

	public final String name;

	public ClientEntity(Vector3d position, Vector3f rotation, int id, EntityType type, double height, String name) {
		interpolatedValues = new EntityInterpolation(position, rotation);
		this.position = position;
		this.rotation = rotation;
		this.id = id;
		this.type = type;
		this.height = height;
		this.name = name;
	}

	public void updatePosition(Vector3d position, Vector3d velocity, Vector3f rotation, short time) {
		interpolatedValues.updatePosition(position, velocity, rotation, time);
	}

	public void update(short time, short lastTime) {
		assert this.position == interpolatedValues.position;
		assert this.rotation == interpolatedValues.rotation;
		interpolatedValues.update(time, lastTime);
	}
}
