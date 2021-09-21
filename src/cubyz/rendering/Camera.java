package cubyz.rendering;

import org.joml.Matrix4f;
import org.joml.Vector3f;

public abstract class Camera {
	private static final float PI_HALF = (float)(Math.PI/2);

	private static final Vector3f position = new Vector3f();

	private static final Vector3f rotation = new Vector3f();
	
	private static Matrix4f viewMatrix = new Matrix4f().identity();

	public static Matrix4f getViewMatrix() {
		return viewMatrix;
	}

	public static void setViewMatrix(Matrix4f viewMatrix) {
		Camera.viewMatrix = viewMatrix;
	}

	public static Vector3f getPosition() {
		return position;
	}

	public static void setPosition(float x, float y, float z) {
		position.x = x;
		position.y = y;
		position.z = z;
	}

	public static void movePosition(float offsetX, float offsetY, float offsetZ) {
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

	public static Vector3f getRotation() {
		return rotation;
	}

	public static void setRotation(float x, float y, float z) {
		if (x > PI_HALF) {
			x = PI_HALF;
		} else if (x < -PI_HALF) {
			x = -PI_HALF;
		}
		rotation.x = x;
		rotation.y = y;
		rotation.z = z;
	}

	public static void moveRotation(float mouseX, float mouseY) {
		// Mouse movement along the x-axis rotates the image along the y-axis.
		rotation.x += mouseY;
		if (rotation.x > PI_HALF) {
			rotation.x = PI_HALF;
		} else if (rotation.x < -PI_HALF) {
			rotation.x = -PI_HALF;
		}
		// Mouse movement along the y-axis rotates the image along the x-axis.
		rotation.y += mouseX;
	}

}
