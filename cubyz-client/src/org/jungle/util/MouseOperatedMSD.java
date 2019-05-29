package org.jungle.util;

import org.joml.Matrix4f;
import org.joml.Vector2d;
import org.joml.Vector3f;
import org.joml.Vector4f;
import org.jungle.Camera;
import org.jungle.Spatial;
import org.jungle.Window;
import org.jungle.renderers.IRenderer;

public class MouseOperatedMSD extends MeshSelectionDetector {

	private Matrix4f invProjectionMatrix;
	private Vector4f tmpVec;
	private Matrix4f invViewMatrix;
	private Vector3f mouseDir;
	
	public MouseOperatedMSD(IRenderer render) {
		super(render);
		invProjectionMatrix = new Matrix4f();
		invViewMatrix = new Matrix4f();
		tmpVec = new Vector4f();
		mouseDir = new Vector3f();
	}
	
	public void selectSpatial(Spatial[] spatials, Window window, Vector2d mousePos, Camera camera) {
		selectedSpatial = null;
        // Transform mouse coordinates into normalized spaze [-1, 1]
        int wdwWitdh = window.getWidth();
        int wdwHeight = window.getHeight();
        
        float x = (float)(2 * mousePos.x) / (float)wdwWitdh - 1.0f;
        float y = 1.0f - (float)(2 * mousePos.y) / (float)wdwHeight;
        float z = -1.0f;

        invProjectionMatrix.set(window.getProjectionMatrix());
        invProjectionMatrix.invert();
        
        tmpVec.set(x, y, z, 1.0f);
        tmpVec.mul(invProjectionMatrix);
        tmpVec.z = -1.0f;
        tmpVec.w = 0.0f;
        
        Matrix4f viewMatrix = camera.getViewMatrix();
        invViewMatrix.set(viewMatrix);
        invViewMatrix.invert();
        tmpVec.mul(invViewMatrix);
        
        mouseDir.set(tmpVec.x, tmpVec.y, tmpVec.z);

        selectSpatial(spatials, camera.getPosition(), mouseDir);
	}

}
