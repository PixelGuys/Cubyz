package org.jungle.renderers;

import java.util.List;
import java.util.Map;

import org.joml.FrustumIntersection;
import org.joml.Matrix4f;
import org.joml.Vector3f;
import org.jungle.Mesh;
import org.jungle.Spatial;

public class FrustumCullingFilter {

    private final Matrix4f prjViewMatrix;
    
    private FrustumIntersection frustumInt;

    public FrustumCullingFilter() {
        prjViewMatrix = new Matrix4f();
        frustumInt = new FrustumIntersection();
    }

    public void updateFrustum(Matrix4f projMatrix, Matrix4f viewMatrix) {
        // Calculate projection view matrix
        prjViewMatrix.set(projMatrix);
        prjViewMatrix.mul(viewMatrix);
        // Get frustum planes
        frustumInt.set(prjViewMatrix);
    }
    
    public void filter(List<Spatial> gameItems, float meshBoundingRadius) {
        float boundingRadius;
        Vector3f pos;
        for (Spatial gameItem : gameItems) {
            boundingRadius = gameItem.getScale() * meshBoundingRadius;
            pos = gameItem.getPosition();
            gameItem.setInFrustum(frustumInt.testSphere(pos.x, pos.y, pos.z, boundingRadius));
        }
    }
    
    public void filter(Map<? extends Mesh, List<Spatial>> mapMesh) {
        for (Map.Entry<? extends Mesh, List<Spatial>> entry : mapMesh.entrySet()) {
            List<Spatial> gameItems = entry.getValue();
            filter(gameItems, entry.getKey().getBoundingRadius());
        }
    }
    
    
}