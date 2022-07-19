package cubyz.client.entity;

import cubyz.utils.interpolation.GenericInterpolation;
import org.joml.Vector3d;
import org.joml.Vector3f;

import cubyz.world.entity.EntityType;

public class ClientEntity {
	public final GenericInterpolation interpolatedValues;

	public final double height;
	
	public final EntityType type;

	public final Vector3d position = new Vector3d();
	public final Vector3f rotation = new Vector3f();
	
	public Vector3d getRenderPosition() { // default method for render pos
		return new Vector3d(position.x, position.y + height/2, position.z);
	}

	public final int id;

	public final String name;

	public ClientEntity(int id, EntityType type, double height, String name) {
		interpolatedValues = new GenericInterpolation(new double[6]);
		this.id = id;
		this.type = type;
		this.height = height;
		this.name = name;
	}

	public void updatePosition(double[] position, double[] velocity, short time) {
		this.rotation.set(rotation);
		interpolatedValues.updatePosition(position, velocity, time);
	}

	public void update(short time, short lastTime) {
		interpolatedValues.update(time, lastTime);
		this.position.x = interpolatedValues.outPosition[0];
		this.position.y = interpolatedValues.outPosition[1];
		this.position.z = interpolatedValues.outPosition[2];
		this.rotation.x = (float)interpolatedValues.outPosition[3];
		this.rotation.y = (float)interpolatedValues.outPosition[4];
		this.rotation.z = (float)interpolatedValues.outPosition[5];
	}
}
