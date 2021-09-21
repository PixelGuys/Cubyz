package cubyz.rendering;

import org.joml.Matrix4f;
import org.joml.Vector3f;

public class Transformation {

	private final Matrix4f worldMatrix;

	private final Matrix4f viewMatrix;
	private final Matrix4f lightViewMatrix;

	private static final Matrix4f modelViewMatrix = new Matrix4f();

	private final Matrix4f orthoMatrix;

	private static final Vector3f xVec = new Vector3f(1, 0, 0); // There is no need to create a new object every time
																// this is needed.
	private static final Vector3f yVec = new Vector3f(0, 1, 0);

	public Transformation() {
		worldMatrix = new Matrix4f();
		viewMatrix = new Matrix4f();
		orthoMatrix = new Matrix4f();
		lightViewMatrix = new Matrix4f();
	}

	public static void updateProjectionMatrix(Matrix4f projectionMatrix, float fov, float width, float height, float zNear, float zFar) {
		float aspectRatio = width / height;
		projectionMatrix.identity();
		projectionMatrix.perspective(fov, aspectRatio, zNear, zFar);
	}

	public Matrix4f getWorldMatrix(Vector3f offset, Vector3f rotation, float scale) {
		worldMatrix.identity().translate(offset).rotateX(rotation.x).rotateY(rotation.y)
				.rotateZ(rotation.z).scale(scale);
		return worldMatrix;
	}

	public final Matrix4f getOrthoProjectionMatrix(float left, float right, float bottom, float top, float zNear, float zFar) {
		orthoMatrix.identity();
		orthoMatrix.setOrtho(left, right, bottom, top, zNear, zFar);
		return orthoMatrix;
	}

	public Matrix4f getOrtoProjModelMatrix(Spatial gameItem, Matrix4f orthoMatrix) {
		Vector3f rotation = gameItem.getRotation();
		Matrix4f modelMatrix = new Matrix4f();
		modelMatrix.identity()
			.translate(gameItem.getPosition())
			.rotateX(-rotation.x)
			.rotateY(-rotation.y)
			.rotateZ(-rotation.z)
			.scale(gameItem.getScale());
		Matrix4f orthoMatrixCurr = new Matrix4f(orthoMatrix);
		orthoMatrixCurr.mul(modelMatrix);
		return orthoMatrixCurr;
	}
	
	public Matrix4f getOrtoProjModelMatrix(Spatial gameItem) {
		return getOrtoProjModelMatrix(gameItem, orthoMatrix);
	}
	
	public static Matrix4f getModelMatrix(Vector3f position, Vector3f rotation, Vector3f scale) {
		modelViewMatrix.identity()
			.translate(position)
			.rotateX(-rotation.x)
			.rotateY(-rotation.y)
			.rotateZ(-rotation.z)
			.scale(scale);
		return modelViewMatrix;
	}
	
	public static Matrix4f getModelMatrix(Vector3f position, Vector3f rotation, float scale) {
		modelViewMatrix.identity()
			.translate(position)
			.rotateX(-rotation.x)
			.rotateY(-rotation.y)
			.rotateZ(-rotation.z)
			.scale(scale);
		return modelViewMatrix;
	}
	
	public Matrix4f getViewMatrix(Vector3f position, Vector3f rotation) {
		viewMatrix.identity();
		// First do the rotation so camera rotates over its position
		viewMatrix.rotate(rotation.x, xVec).rotate(rotation.y, yVec);
		// Then do the translation
		viewMatrix.translate(-position.x, -position.y, -position.z);
		return viewMatrix;
	}
	
	public Matrix4f getLightViewMatrix(Vector3f position, Vector3f rotation) {
		lightViewMatrix.identity();
		// First do the rotation so camera rotates over its position
		lightViewMatrix.rotate(rotation.x, xVec).rotate(rotation.y, yVec);
		// Then do the translation
		lightViewMatrix.translate(-position.x, -position.y, -position.z);
		return lightViewMatrix;
	}

	public static Matrix4f getModelViewMatrix(Spatial spatial, Matrix4f viewMatrix) {
		return getModelViewMatrix(spatial.modelViewMatrix, viewMatrix);
	}
	
	public static Matrix4f getModelViewMatrix(Matrix4f modelMatrix, Matrix4f viewMatrix) {
		//Matrix4f viewCurr = new Matrix4f(viewMatrix);
		//return viewCurr.mul(modelMatrix);
		return modelMatrix.mulLocal(viewMatrix); // seems to work, and doesn't allocate a new Matrix4f
	}
}
