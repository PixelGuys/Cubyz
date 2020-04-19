package io.jungle;

import org.joml.Matrix4f;
import org.joml.Vector3f;

public class Camera {
	public static final float piHalf = (float)(Math.PI/2);

	private final Vector3f position;

	private final Vector3f rotation;
	
	private Matrix4f viewMatrix;
	
	private float fov;

	public Camera() {
		position = new Vector3f(0, 0, 0);
		rotation = new Vector3f(0, 0, 0);
		fov = (float) Math.toRadians(70.0f);
	}

	public Matrix4f getViewMatrix() {
		return viewMatrix;
	}

	public void setViewMatrix(Matrix4f viewMatrix) {
		this.viewMatrix = viewMatrix;
	}
	
	public float getFov() {
		return fov;
	}
	
	public void setFov(float fov) {
		this.fov = fov;
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
			position.x -= (float) Math.sin(rotation.y - piHalf) * offsetX;
			position.z += (float) Math.cos(rotation.y - piHalf) * offsetX;
		}
		position.y += offsetY;
	}

	public Vector3f getRotation() {
		return rotation;
	}

	public void setRotation(float x, float y, float z) {
		if (x > piHalf) {
			x = piHalf;
		} else if (x < -piHalf) {
			x = -piHalf;
		}
		rotation.x = x;
		rotation.y = y;
		rotation.z = z;
	}

	public void moveRotation(float offsetX, float offsetY, float offsetZ) {
		rotation.x += offsetX;
		if (rotation.x > piHalf) {
			rotation.x = piHalf;
		} else if (rotation.x < -piHalf) {
			rotation.x = -piHalf;
		}
		rotation.y += offsetY;
		rotation.z += offsetZ;
	}

}
