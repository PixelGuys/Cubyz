package org.jungle.renderers;

import org.joml.Matrix4f;
import org.joml.Vector3f;
import org.jungle.Camera;
import org.jungle.Spatial;

public abstract class Transformation {
	public abstract Matrix4f getProjectionMatrix(float fov, float width, float height, float zNear, float zFar);
	public abstract Matrix4f getWorldMatrix(Vector3f offset, Vector3f rotation, float scale);
	public abstract Matrix4f getOrthoProjectionMatrix(float left, float right, float bottom, float top);
	public abstract Matrix4f getOrtoProjModelMatrix(Spatial gameItem, Matrix4f orthoMatrix);
	public abstract Matrix4f getViewMatrix(Camera camera);
	public abstract Matrix4f getModelViewMatrix(Spatial spatial, Matrix4f viewMatrix);
	public abstract Matrix4f getModelViewMatrix(Matrix4f modelMatrix, Matrix4f viewMatrix);
	public abstract Matrix4f getModelMatrix(Spatial spatial);
}