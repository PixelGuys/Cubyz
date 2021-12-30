package cubyz.rendering;

import org.joml.Matrix4f;
import org.joml.Vector3f;

public abstract class Camera {
	private static final float PI_HALF = (float)(Math.PI/2);

	private static final Vector3f rotation = new Vector3f();
	
	private static Matrix4f viewMatrix = new Matrix4f().identity();

	public static Matrix4f getViewMatrix() {
		return viewMatrix;
	}

	public static void setViewMatrix(Matrix4f viewMatrix) {
		Camera.viewMatrix = viewMatrix;
	}

	/**
	 * The direction the camera is facing in.
	 * @return
	 */
	public static Vector3f getDirection() {
		return new Vector3f(0, 0, -1).rotateX(rotation.x).rotateY(rotation.y);
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
