package io.jungle.util;

import java.nio.IntBuffer;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.joml.Vector4f;
import org.lwjgl.PointerBuffer;
import org.lwjgl.assimp.AIColor4D;
import org.lwjgl.assimp.AIFace;
import org.lwjgl.assimp.AIMaterial;
import org.lwjgl.assimp.AIMesh;
import org.lwjgl.assimp.AIScene;
import org.lwjgl.assimp.AIString;
import org.lwjgl.assimp.AIVector3D;
import org.lwjgl.assimp.Assimp;

import io.jungle.InstancedMesh;
import io.jungle.Mesh;
import io.jungle.Texture;

import static org.lwjgl.assimp.Assimp.*;

public class StaticMeshesLoader {

	public static Mesh[] load(String resourcePath, String texturesDir) throws Exception {
		return load(resourcePath, texturesDir,
				aiProcess_JoinIdenticalVertices | aiProcess_Triangulate | aiProcess_FixInfacingNormals);
	}

	public static Mesh[] load(String resourcePath, String texturesDir, int flags) throws Exception {
		AIScene aiScene = aiImportFile(resourcePath, flags);
		if (aiScene == null) {
			throw new Exception("Error loading model");
		}

		int numMaterials = aiScene.mNumMaterials();
		PointerBuffer aiMaterials = aiScene.mMaterials();
		List<Material> materials = new ArrayList<>();
		for (int i = 0; i < numMaterials; i++) {
			AIMaterial aiMaterial = AIMaterial.create(aiMaterials.get(i));
			processMaterial(aiMaterial, materials, texturesDir);
		}

		int numMeshes = aiScene.mNumMeshes();
		PointerBuffer aiMeshes = aiScene.mMeshes();
		Mesh[] meshes = new Mesh[numMeshes];
		for (int i = 0; i < numMeshes; i++) {
			AIMesh aiMesh = AIMesh.create(aiMeshes.get(i));
			Mesh mesh = processMesh(aiMesh, materials);
			meshes[i] = mesh;
		}

		return meshes;
	}
	
	public static InstancedMesh[] loadInstanced(String resourcePath, String texturesDir) throws Exception {
		return loadInstanced(resourcePath, texturesDir,
				aiProcess_JoinIdenticalVertices | aiProcess_Triangulate | aiProcess_FixInfacingNormals);
	}

	public static InstancedMesh[] loadInstanced(String resourcePath, String texturesDir, int flags) throws Exception {
		AIScene aiScene = aiImportFile(resourcePath, flags);
		if (aiScene == null) {
			throw new Exception("Error loading model");
		}

		int numMaterials = aiScene.mNumMaterials();
		PointerBuffer aiMaterials = aiScene.mMaterials();
		List<Material> materials = new ArrayList<>();
		for (int i = 0; i < numMaterials; i++) {
			AIMaterial aiMaterial = AIMaterial.create(aiMaterials.get(i));
			processMaterial(aiMaterial, materials, texturesDir);
		}

		int numMeshes = aiScene.mNumMeshes();
		PointerBuffer aiMeshes = aiScene.mMeshes();
		InstancedMesh[] meshes = new InstancedMesh[numMeshes];
		for (int i = 0; i < numMeshes; i++) {
			AIMesh aiMesh = AIMesh.create(aiMeshes.get(i));
			InstancedMesh mesh = processInstancedMesh(aiMesh, materials);
			meshes[i] = mesh;
		}

		return meshes;
	}

	private static void processMaterial(AIMaterial aiMaterial, List<Material> materials, String texturesDir)
			throws Exception {
		AIColor4D colour = AIColor4D.create();

		AIString path = AIString.calloc();
		Assimp.aiGetMaterialTexture(aiMaterial, aiTextureType_DIFFUSE, 0, path, (IntBuffer) null, null, null, null,
				null, null);
		String textPath = path.dataString();
		Texture texture = null;
		if (textPath != null && textPath.length() > 0) {
			TextureCache textCache = TextureCache.getInstance();
			texture = textCache.getTexture(texturesDir + "/" + textPath);
		}

		Vector4f ambient = Material.DEFAULT_COLOUR;
		int result = aiGetMaterialColor(aiMaterial, AI_MATKEY_COLOR_AMBIENT, aiTextureType_NONE, 0, colour);
		if (result == 0) {
			ambient = new Vector4f(colour.r(), colour.g(), colour.b(), colour.a());
		}

		Vector4f diffuse = Material.DEFAULT_COLOUR;
		result = aiGetMaterialColor(aiMaterial, AI_MATKEY_COLOR_DIFFUSE, aiTextureType_NONE, 0, colour);
		if (result == 0) {
			diffuse = new Vector4f(colour.r(), colour.g(), colour.b(), colour.a());
		}

		Vector4f specular = Material.DEFAULT_COLOUR;
		result = aiGetMaterialColor(aiMaterial, AI_MATKEY_COLOR_SPECULAR, aiTextureType_NONE, 0, colour);
		if (result == 0) {
			specular = new Vector4f(colour.r(), colour.g(), colour.b(), colour.a());
		}

		Material material = new Material(ambient, diffuse, specular, 1.0f);
		material.setTexture(texture);
		materials.add(material);
	}

	private static Mesh processMesh(AIMesh aiMesh, List<Material> materials) {
		float[] vertices = processVertices(aiMesh);
		List<Float> textures = new ArrayList<>();
		List<Float> normals = new ArrayList<>();
		List<Integer> indices = new ArrayList<>();

		processNormals(aiMesh, normals);
		processTextCoords(aiMesh, textures);
		processIndices(aiMesh, indices);

		Mesh mesh = new Mesh(vertices, Utils.listToArray(textures), Utils.listToArray(normals),
				Utils.listIntToArray(indices));
		Material material;
		int materialIdx = aiMesh.mMaterialIndex();
		if (materialIdx >= 0 && materialIdx < materials.size()) {
			material = materials.get(materialIdx);
		} else {
			material = new Material();
		}
		mesh.setMaterial(material);

		return mesh;
	}
	
	private static InstancedMesh processInstancedMesh(AIMesh aiMesh, List<Material> materials) {
		float[] vertices = processVertices(aiMesh);
		List<Float> textures = new ArrayList<>();
		List<Float> normals = new ArrayList<>();
		List<Integer> indices = new ArrayList<>();

		processNormals(aiMesh, normals);
		processTextCoords(aiMesh, textures);
		processIndices(aiMesh, indices);

		InstancedMesh mesh = new InstancedMesh(vertices, Utils.listToArray(textures), Utils.listToArray(normals),
				Utils.listIntToArray(indices), 0);
		Material material;
		int materialIdx = aiMesh.mMaterialIndex();
		if (materialIdx >= 0 && materialIdx < materials.size()) {
			material = materials.get(materialIdx);
		} else {
			material = new Material();
		}
		mesh.setMaterial(material);

		return mesh;
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

	public static class TextureCache {
		private static TextureCache INSTANCE;

		private Map<String, Texture> texturesMap;

		private TextureCache() {
			texturesMap = new HashMap<>();
		}

		public static synchronized TextureCache getInstance() {
			if (INSTANCE == null) {
				INSTANCE = new TextureCache();
			}
			return INSTANCE;
		}

		public Texture getTexture(String path) throws Exception {
			Texture texture = texturesMap.get(path);
			if (texture == null) {
				texture = new Texture(path);
				texturesMap.put(path, texture);
			}
			return texture;
		}
	}
}
