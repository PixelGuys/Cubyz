package io.cubyz.rendering;

import org.joml.Matrix4f;
import org.joml.Vector3f;

public class Camera {
	private static final float PI_HALF = (float)(Math.PI/2);

	private final Vector3f position;

	private final Vector3f rotation;
	
	private Matrix4f viewMatrix;

	public Camera() {
		position = new Vector3f(0, 0, 0);
		rotation = new Vector3f(0, 0, 0);
	}

	public Matrix4f getViewMatrix() {
		return viewMatrix;
	}

	public void setViewMatrix(Matrix4f viewMatrix) {
		this.viewMatrix = viewMatrix;
	}
	
	public Camera(Vector3f position, Vector3f rotation) {
		this.position = position;
		this.rotation = rotation;
	}

	public Vector3f getPosition() {
		return position;
	}

	public void setPosition(float x, float y, float z) {
		position.x = x;
		position.y = y;
		position.z = z;
	}

	public void movePosition(float offsetX, float offsetY, float offsetZ) {
		if (offsetZ != 0) {
			position.x -= (float) Math.sin(rotation.y) * offsetZ;
			position.z += (float) Math.cos(rotation.y) * offsetZ;
		}
		if (offsetX != 0) {
			position.x -= (float) Math.sin(rotation.y - PI_HALF) * offsetX;
			position.z += (float) Math.cos(rotation.y - PI_HALF) * offsetX;
		}
		position.y += offsetY;
	}

	public Vector3f getRotation() {
		return rotation;
	}

	public void setRotation(float x, float y, float z) {
		if (x > PI_HALF) {
			x = PI_HALF;
		} else if (x < -PI_HALF) {
			x = -PI_HALF;
		}
		rotation.x = x;
		rotation.y = y;
		rotation.z = z;
	}

	public void moveRotation(float offsetX, float offsetY, float offsetZ) {
		rotation.x += offsetX;
		if (rotation.x > PI_HALF) {
			rotation.x = PI_HALF;
		} else if (rotation.x < -PI_HALF) {
			rotation.x = -PI_HALF;
		}
		rotation.y += offsetY;
		rotation.z += offsetZ;
	}

}
