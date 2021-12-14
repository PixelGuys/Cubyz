package cubyz.rendering;

import static org.lwjgl.assimp.Assimp.*;

import java.nio.IntBuffer;
import java.util.ArrayList;
import java.util.List;

import org.lwjgl.PointerBuffer;
import org.lwjgl.assimp.AIFace;
import org.lwjgl.assimp.AIMesh;
import org.lwjgl.assimp.AIScene;
import org.lwjgl.assimp.AIVector3D;

import cubyz.api.Resource;
import cubyz.client.Meshes;
import cubyz.rendering.models.Model;
import cubyz.utils.Utils;

public class ModelLoader {
	
	private static final int flags = aiProcess_JoinIdenticalVertices | aiProcess_Triangulate;
	
	public static Model loadModel(Resource id, String filePath) {
		Model model = Meshes.models.getByID(id);
		if (model != null) return model;
		model = loadUnregisteredModel(id, filePath);
		Meshes.models.register(model);
		return model;
	}
	
	public static Model loadUnregisteredModel(Resource id, String filePath) {
		AIScene aiScene = aiImportFile(filePath, flags);
		PointerBuffer aiMeshes = aiScene.mMeshes();
		AIMesh aiMesh = AIMesh.create(aiMeshes.get());
		float[] vertices = processVertices(aiMesh);
		List<Float> textures = new ArrayList<>();
		List<Float> normals = new ArrayList<>();
		List<Integer> indices = new ArrayList<>();
	
		processNormals(aiMesh, normals);
		processTextCoords(aiMesh, textures);
		processIndices(aiMesh, indices);
		return new Model(id, vertices, Utils.listToArray(textures), Utils.listToArray(normals), Utils.listIntToArray(indices));
	}

	private static float[] processVertices(AIMesh aiMesh) {
		AIVector3D.Buffer aiVertices = aiMesh.mVertices();
		float[] vertices = new float[aiVertices.limit() * 3];
		aiVertices.rewind();
		for (int i = 0; i < aiVertices.limit(); i++) {
			AIVector3D aiVertex = aiVertices.get();
			int j = i * 3;
			vertices[j] = aiVertex.x();
			vertices[j + 1] = aiVertex.y();
			vertices[j + 2] = aiVertex.z();
		}
		return vertices;
	}

	private static void processNormals(AIMesh aiMesh, List<Float> normals) {
		AIVector3D.Buffer aiNormals = aiMesh.mNormals();
		while (aiNormals != null && aiNormals.remaining() > 0) {
			AIVector3D aiNormal = aiNormals.get();
			normals.add(aiNormal.x());
			normals.add(aiNormal.y());
			normals.add(aiNormal.z());
		}
	}

	private static void processTextCoords(AIMesh aiMesh, List<Float> textures) {
		AIVector3D.Buffer textCoords = aiMesh.mTextureCoords(0);
		int numTextCoords = textCoords != null ? textCoords.remaining() : 0;
		while (numTextCoords > 0) {
			AIVector3D textCoord = textCoords.get();
			textures.add(textCoord.x());
			textures.add(1 - textCoord.y());
			numTextCoords = textCoords != null ? textCoords.remaining() : 0;
		}
	}

	private static void processIndices(AIMesh aiMesh, List<Integer> indices) {
		int numFaces = aiMesh.mNumFaces();
		AIFace.Buffer aiFaces = aiMesh.mFaces();
		for (int i = 0; i < numFaces; i++) {
			AIFace aiFace = aiFaces.get(i);
			IntBuffer buffer = aiFace.mIndices();
			buffer.rewind();
			while (buffer.remaining() > 0) {
				indices.add(buffer.get());
			}
		}
	}
}
