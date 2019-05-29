package org.jungle.util;

import java.io.BufferedInputStream;
import java.io.FileInputStream;
import java.util.ArrayList;
import java.util.List;
import java.util.Scanner;

import org.joml.Vector2f;
import org.joml.Vector3f;
import org.jungle.Mesh;

public class OBJLoader {

	public OBJLoader() {
		// TODO Auto-generated constructor stub
	}

	public static Mesh loadMesh(String fileName) throws Exception {

		List<Vector3f> vertices = new ArrayList<>();
		List<Vector2f> textures = new ArrayList<>();
		List<Vector3f> normals = new ArrayList<>();
		List<Face> faces = new ArrayList<>();
		
		Scanner sc  = new Scanner(new BufferedInputStream(new FileInputStream(fileName)));

		while (sc.hasNext()) {
			String line = sc.nextLine();
			String[] tokens = line.split("\\s+");
			try {
				switch (tokens[0]) {

				case "v":
					// Geometric vertex
					Vector3f vec3f = new Vector3f(Float.parseFloat(tokens[1]), Float.parseFloat(tokens[2]),
							Float.parseFloat(tokens[3]));
					vertices.add(vec3f);
					break;
				case "vt":
					// Texture coordinate
					Vector2f vec2f = new Vector2f(Float.parseFloat(tokens[1]), Float.parseFloat(tokens[2]));
					textures.add(vec2f);
					break;
				case "vn":
					// Vertex normal
					Vector3f vec3fNorm = new Vector3f(Float.parseFloat(tokens[1]), Float.parseFloat(tokens[2]),
							Float.parseFloat(tokens[3]));
					normals.add(vec3fNorm);
					break;
				case "f":
					Face face = null;
					if (tokens.length > 4) {
						//face = new Face(tokens[1], tokens[2], tokens[3], tokens[4]);
						Face f1 = new Face(tokens[1], tokens[2], tokens[3], null);
						Face f2 = new Face(tokens[3], tokens[1], tokens[4], null);
						faces.add(f1);
						faces.add(f2);
					}
					else if (tokens.length > 3) {
						face = new Face(tokens[1], tokens[2], tokens[3], null);
					}
					if (face != null)
						faces.add(face);
					break;
				default:
					// Ignore other lines
					break;
				}
			} catch (ArrayIndexOutOfBoundsException e) {

			}
		}
		
		sc.close();
		return reorderLists(vertices, textures, normals, faces);
	}

	private static Mesh reorderLists(List<Vector3f> posList, List<Vector2f> textCoordList, List<Vector3f> normList,
			List<Face> facesList) {

		List<Integer> indices = new ArrayList<>();
		// Create position array in the order it has been declared
		float[] posArr = new float[posList.size() * 3];
		int i = 0;
		for (Vector3f pos : posList) {
			posArr[i * 3] = pos.x;
			posArr[(i * 3) + 1] = pos.y;
			posArr[(i * 3) + 2] = pos.z;
			i++;
		}
		float[] textCoordArr = new float[posList.size() * 2];
		float[] normArr = new float[posList.size() * 3];

		for (Face face : facesList) {
			IdxGroup[] faceVertexIndices = face.getFaceVertexIndices();
			for (IdxGroup indValue : faceVertexIndices) {
				processFaceVertex(indValue, textCoordList, normList, indices, textCoordArr, normArr);
			}
		}
		int[] indicesArr = new int[indices.size()];
		indicesArr = indices.stream().mapToInt((Integer v) -> v).toArray();
		Mesh mesh = new Mesh(posArr, textCoordArr, normArr, indicesArr);
		return mesh;
	}

	private static void processFaceVertex(IdxGroup indices, List<Vector2f> textCoordList, List<Vector3f> normList,
			List<Integer> indicesList, float[] texCoordArr, float[] normArr) {

		// Set index for vertex coordinates
		int posIndex = indices.idxPos;
		indicesList.add(posIndex);

		// Reorder texture coordinates
		if (indices.idxTextCoord >= 0) {
			Vector2f textCoord = textCoordList.get(indices.idxTextCoord);
			texCoordArr[posIndex * 2] = textCoord.x;
			texCoordArr[posIndex * 2 + 1] = 1 - textCoord.y;
		}
		if (indices.idxVecNormal >= 0) {
			// Reorder vectornormals
			Vector3f vecNorm = normList.get(indices.idxVecNormal);
			normArr[posIndex * 3] = vecNorm.x;
			normArr[posIndex * 3 + 1] = vecNorm.y;
			normArr[posIndex * 3 + 2] = vecNorm.z;
		}
	}

	protected static class IdxGroup {

		public static final int NO_VALUE = -1;

		public int idxPos;

		public int idxTextCoord;

		public int idxVecNormal;

		public IdxGroup() {
			idxPos = NO_VALUE;
			idxTextCoord = NO_VALUE;
			idxVecNormal = NO_VALUE;
		}
	}

	protected static class Face {

		/**
		 * List of idxGroup groups for a face triangle (3 vertices per face).
		 */
		private IdxGroup[] idxGroups;

		public Face(String v1, String v2, String v3, String v4) {
			if (v4 == null) {
				idxGroups = new IdxGroup[3];
			} else {
				idxGroups = new IdxGroup[4];
			}
			// Parse the lines
			idxGroups[0] = parseLine(v1);
			idxGroups[1] = parseLine(v2);
			idxGroups[2] = parseLine(v3);
			if (v4 != null) {
				idxGroups[3] = parseLine(v4);
			}
		}

		private IdxGroup parseLine(String line) {
			IdxGroup idxGroup = new IdxGroup();

			String[] lineTokens = line.split("/");
			int length = lineTokens.length;
			idxGroup.idxPos = Integer.parseInt(lineTokens[0].trim()) - 1;
			if (length > 1) {
				// It can be empty if the obj does not define text coords
				String textCoord = lineTokens[1].trim();
				idxGroup.idxTextCoord = textCoord.length() > 0 ? Integer.parseInt(textCoord) - 1 : IdxGroup.NO_VALUE;
				if (length > 2) {
					idxGroup.idxVecNormal = Integer.parseInt(lineTokens[2].trim()) - 1;
				}
			}

			return idxGroup;
		}

		public IdxGroup[] getFaceVertexIndices() {
			return idxGroups;
		}
	}

}
