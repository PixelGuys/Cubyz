package cubyz.client;

import static org.lwjgl.opengl.GL11.*;
import static org.lwjgl.opengl.GL15.*;
import static org.lwjgl.opengl.GL20.*;
import static org.lwjgl.opengl.GL30.*;

import java.nio.IntBuffer;
import java.util.ArrayList;

import org.joml.Matrix4f;
import org.joml.Vector3d;
import org.joml.Vector3f;
import org.lwjgl.system.MemoryUtil;

import cubyz.rendering.Camera;
import cubyz.rendering.ShaderProgram;
import cubyz.utils.Utils;
import cubyz.utils.datastructures.IntFastList;
import cubyz.world.ChunkData;
import cubyz.world.Neighbors;
import cubyz.world.NormalChunk;
import cubyz.world.ReducedChunkVisibilityData;

/**
 * Used to create chunk meshes for reduced chunks.
 */

public class ReducedChunkMesh extends ChunkMesh {
	// ThreadLocal lists, to prevent (re-)allocating tons of memory.
	public static ThreadLocal<IntFastList> localVertices = new ThreadLocal<IntFastList>() {
		@Override
		protected IntFastList initialValue() {
			return new IntFastList(20000);
		}
	};
	public static ThreadLocal<IntFastList> localFaces = new ThreadLocal<IntFastList>() {
		@Override
		protected IntFastList initialValue() {
			return new IntFastList(30000);
		}
	};
	public static ThreadLocal<IntFastList> localTexCoordsAndNormals = new ThreadLocal<IntFastList>() {
		@Override
		protected IntFastList initialValue() {
			return new IntFastList(20000);
		}
	};

	// Shader stuff:
	public static int loc_projectionMatrix;
	public static int loc_viewMatrix;
	public static int loc_modelPosition;
	public static int loc_ambientLight;
	public static int loc_directionalLight;
	public static int loc_fog_activ;
	public static int loc_fog_color;
	public static int loc_fog_density;
	public static int loc_lowerBounds;
	public static int loc_upperBounds;
	public static int loc_voxelSize;
	public static int loc_texture_sampler;
	public static int loc_waterFog_activ;
	public static int loc_waterFog_color;
	public static int loc_waterFog_density;
	public static int loc_time;

	public static ShaderProgram shader;
	
	public static void init(String shaderFolder) throws Exception {
		if (shader != null)
			shader.cleanup();
		shader = new ShaderProgram(Utils.loadResource(shaderFolder + "/chunk_vertex.vs"),
				Utils.loadResource(shaderFolder + "/chunk_fragment.fs"),
				ReducedChunkMesh.class);
	}

	public static final Matrix4f projMatrix = new Matrix4f();

	/**
	 * Also updates the uniforms.
	 * @param ambient
	 * @param directional
	 */
	public static void bindShader(Vector3f ambient, Vector3f directional, int time) {
		shader.bind();

		shader.setUniform(loc_fog_activ, Cubyz.fog.isActive());
		shader.setUniform(loc_fog_color, Cubyz.fog.getColor());
		shader.setUniform(loc_fog_density, Cubyz.fog.getDensity());

		shader.setUniform(loc_projectionMatrix, projMatrix);
		
		shader.setUniform(loc_texture_sampler, 0);
		
		shader.setUniform(loc_viewMatrix, Camera.getViewMatrix());

		shader.setUniform(loc_ambientLight, ambient);
		shader.setUniform(loc_directionalLight, directional);

		shader.setUniform(loc_time, time);
	}
	
	protected int vaoId;

	protected ArrayList<Integer> vboIdList = new ArrayList<>();

	protected int vertexCount;

	private ReducedChunkVisibilityData chunkVisibilityData;

	private boolean needsUpdate = false;

	public ReducedChunkMesh(ReducedChunkMesh replacement, int wx, int wy, int wz, int size) {
		super(replacement, wx, wy, wz, size);
	}

	public void updateChunk(ReducedChunkVisibilityData data) {
		synchronized(this) {
			chunkVisibilityData = data;
			if (!needsUpdate) {
				needsUpdate = true;
				Meshes.queueMesh(this);
			}
		}
	}
	
	@Override
	public void regenerateMesh() {
		cleanUp();
		ReducedChunkVisibilityData chunkVisibilityData;
		synchronized(this) {
			chunkVisibilityData = this.chunkVisibilityData;
			if (!needsUpdate)
				return;
			needsUpdate = false;
			if (chunkVisibilityData == null)
				return;
		}
		generated = true;

		IntFastList vertices = localVertices.get();
		IntFastList faces = localFaces.get();
		IntFastList texCoordsAndNormals = localTexCoordsAndNormals.get();
		vertices.clear();
		faces.clear();
		texCoordsAndNormals.clear();
		generateModelData(chunkVisibilityData, vertices, faces, texCoordsAndNormals);
		IntBuffer posBuffer = null;
		IntBuffer indexBuffer = null;
		IntBuffer colorAndNormalBuffer = null;
		try {
			vertexCount = faces.size;
			if (vertexCount == 0)
				return;
			
			vboIdList.clear();

			vaoId = glGenVertexArrays();
			glBindVertexArray(vaoId);
			// Enable vertex arrays once.
			glEnableVertexAttribArray(0);
			glEnableVertexAttribArray(1);

			// Position and normal VBO
			int vboId = glGenBuffers();
			vboIdList.add(vboId);
			posBuffer = MemoryUtil.memAllocInt(vertices.size);
			posBuffer.put(vertices.toArray()).flip();
			glBindBuffer(GL_ARRAY_BUFFER, vboId);
			glBufferData(GL_ARRAY_BUFFER, posBuffer, GL_STATIC_DRAW);
			glVertexAttribPointer(0, 1, GL_FLOAT, false, 0, 0);

			// texture and normal VBO
			vboId = glGenBuffers();
			vboIdList.add(vboId);
			colorAndNormalBuffer = MemoryUtil.memAllocInt(texCoordsAndNormals.size);
			colorAndNormalBuffer.put(texCoordsAndNormals.toArray()).flip();
			glBindBuffer(GL_ARRAY_BUFFER, vboId);
			glBufferData(GL_ARRAY_BUFFER, colorAndNormalBuffer, GL_STATIC_DRAW);
			glVertexAttribPointer(1, 1, GL_FLOAT, false, 0, 0);

			// Index VBO
			vboId = glGenBuffers();
			vboIdList.add(vboId);
			indexBuffer = MemoryUtil.memAllocInt(faces.size);
			indexBuffer.put(faces.toArray()).flip();
			glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, vboId);
			glBufferData(GL_ELEMENT_ARRAY_BUFFER, indexBuffer, GL_STATIC_DRAW);

			glBindBuffer(GL_ARRAY_BUFFER, 0);
			glBindVertexArray(0);
		} finally {
			if (posBuffer != null) {
				MemoryUtil.memFree(posBuffer);
			}
			if (indexBuffer != null) {
				MemoryUtil.memFree(indexBuffer);
			}
			if (colorAndNormalBuffer != null) {
				MemoryUtil.memFree(colorAndNormalBuffer);
			}
		}
	}

	@Override
	public ChunkData getChunk() {
		return this;
	}

	@Override
	public void render(Vector3d playerPosition) {
		if (chunkVisibilityData == null || !generated) {
			glUniform3f(ReducedChunkMesh.loc_lowerBounds, (float)(wx - playerPosition.x - 0.001), (float)(wy - playerPosition.y - 0.001), (float)(wz - playerPosition.z - 0.001));
			glUniform3f(ReducedChunkMesh.loc_upperBounds, (float)(wx + size - playerPosition.x + 0.001), (float)(wy + size - playerPosition.y + 0.001), (float)(wz + size - playerPosition.z + 0.001));
			if (replacement != null) {
				replacement.render(playerPosition);
			}
			glUniform3f(loc_lowerBounds, Float.NEGATIVE_INFINITY, Float.NEGATIVE_INFINITY, Float.NEGATIVE_INFINITY);
			glUniform3f(loc_upperBounds, Float.POSITIVE_INFINITY, Float.POSITIVE_INFINITY, Float.POSITIVE_INFINITY);
			return;
		}
		if (vaoId == -1) return;
		glUniform3f(loc_modelPosition, (float)(wx - playerPosition.x), (float)(wy - playerPosition.y), (float)(wz - playerPosition.z));
		glUniform1f(loc_voxelSize, (float)(size/NormalChunk.chunkSize));
		
		glBindVertexArray(vaoId);
		glDrawElements(GL_TRIANGLES, vertexCount, GL_UNSIGNED_INT, 0);
	}

	@Override
	public void cleanUp() {
		// Delete the VBOs
		glBindBuffer(GL_ARRAY_BUFFER, 0);
		for (int vboId : vboIdList) {
			glDeleteBuffers(vboId);
		}

		// Delete the VAO
		glBindVertexArray(0);
		glDeleteVertexArrays(vaoId);
		vaoId = -1;
	}
	
	/**
	 * Adds a vertex and color and returns the index.
	 * @param vertices
	 * @param x
	 * @param y
	 * @param z
	 * @return
	 */
	private static int addVertex(IntFastList vertices, IntFastList colorsAndNormals, int vertexValue, int colorNormal) {
		vertices.add(vertexValue);
		colorsAndNormals.add(colorNormal);
		return vertices.size - 1;
	}
	static long totalTime = 0;
	private static void generateModelData(ReducedChunkVisibilityData chunkVisibilityData, IntFastList vertices, IntFastList faces, IntFastList colorsAndNormals) {
		final int CORD00 = 0b00 << 16;
		final int CORD01 = 0b01 << 16;
		final int CORD10 = 0b10 << 16;
		final int CORD11 = 0b11 << 16;
		final int X_Add = 1;
		final int Y_Add = 1 << 6;
		final int Z_Add = 1 << 12;
		for(int i = 0; i < chunkVisibilityData.size; i++) {
			int block = chunkVisibilityData.visibleBlocks[i];
			int x = chunkVisibilityData.x[i];
			int y = chunkVisibilityData.y[i];
			int z = chunkVisibilityData.z[i];
			int voxelSize = chunkVisibilityData.voxelSize;
			byte neighbors = chunkVisibilityData.neighbors[i];
			if ((neighbors & Neighbors.BIT_MASK[Neighbors.DIR_NEG_X]) != 0) {
				int normal = 0;
				int vertexValue = x | y << 6 | z << 12 | voxelSize << 18;
				int colorNormal = BlockMeshes.textureIndices(block)[Neighbors.DIR_NEG_X] | (normal << 24);
				int i000 = addVertex(vertices, colorsAndNormals, vertexValue, colorNormal | CORD01);
				int i001 = addVertex(vertices, colorsAndNormals, vertexValue + Z_Add, colorNormal | CORD11);
				int i010 = addVertex(vertices, colorsAndNormals, vertexValue + Y_Add, colorNormal | CORD00);
				int i011 = addVertex(vertices, colorsAndNormals, vertexValue + Y_Add + Z_Add, colorNormal | CORD10);
				faces.add(i000);
				faces.add(i001);
				faces.add(i011);

				faces.add(i000);
				faces.add(i011);
				faces.add(i010);
			}
			if ((neighbors & Neighbors.BIT_MASK[Neighbors.DIR_POS_X]) != 0) {
				int normal = 1;
				int vertexValue = x + 1 | y << 6 | z << 12 | voxelSize << 18;
				int colorNormal = BlockMeshes.textureIndices(block)[Neighbors.DIR_POS_X] | (normal << 24);
				int i100 = addVertex(vertices, colorsAndNormals, vertexValue, colorNormal | CORD11);
				int i101 = addVertex(vertices, colorsAndNormals, vertexValue + Z_Add, colorNormal | CORD01);
				int i110 = addVertex(vertices, colorsAndNormals, vertexValue + Y_Add, colorNormal | CORD10);
				int i111 = addVertex(vertices, colorsAndNormals, vertexValue + Y_Add + Z_Add, colorNormal | CORD00);
				faces.add(i100);
				faces.add(i111);
				faces.add(i101);

				faces.add(i100);
				faces.add(i110);
				faces.add(i111);
			}
			if ((neighbors & Neighbors.BIT_MASK[Neighbors.DIR_DOWN]) != 0) {
				int normal = 4;
				int vertexValue = x | y << 6 | z << 12 | voxelSize << 18;
				int colorNormal = BlockMeshes.textureIndices(block)[Neighbors.DIR_DOWN] | (normal << 24);
				int i000 = addVertex(vertices, colorsAndNormals, vertexValue, colorNormal | CORD11);
				int i001 = addVertex(vertices, colorsAndNormals, vertexValue + Z_Add, colorNormal | CORD10);
				int i100 = addVertex(vertices, colorsAndNormals, vertexValue + X_Add, colorNormal | CORD01);
				int i101 = addVertex(vertices, colorsAndNormals, vertexValue + X_Add + Z_Add, colorNormal | CORD00);
				faces.add(i000);
				faces.add(i101);
				faces.add(i001);

				faces.add(i000);
				faces.add(i100);
				faces.add(i101);
			}
			if ((neighbors & Neighbors.BIT_MASK[Neighbors.DIR_UP]) != 0) {
				int normal = 5;
				int vertexValue = x | (y + 1) << 6 | z << 12 | voxelSize << 18;
				int colorNormal = BlockMeshes.textureIndices(block)[Neighbors.DIR_UP] | (normal << 24);
				int i010 = addVertex(vertices, colorsAndNormals, vertexValue, colorNormal | CORD01);
				int i011 = addVertex(vertices, colorsAndNormals, vertexValue + Z_Add, colorNormal | CORD00);
				int i110 = addVertex(vertices, colorsAndNormals, vertexValue + X_Add, colorNormal | CORD11);
				int i111 = addVertex(vertices, colorsAndNormals, vertexValue + X_Add + Z_Add, colorNormal | CORD10);
				faces.add(i010);
				faces.add(i011);
				faces.add(i111);

				faces.add(i010);
				faces.add(i111);
				faces.add(i110);
			}
			if ((neighbors & Neighbors.BIT_MASK[Neighbors.DIR_NEG_Z]) != 0) {
				int normal = 2;
				int vertexValue = x | y << 6 | z << 12 | voxelSize << 18;
				int colorNormal = BlockMeshes.textureIndices(block)[Neighbors.DIR_NEG_Z] | (normal << 24);
				int i000 = addVertex(vertices, colorsAndNormals, vertexValue, colorNormal | CORD11);
				int i010 = addVertex(vertices, colorsAndNormals, vertexValue + Y_Add, colorNormal | CORD10);
				int i100 = addVertex(vertices, colorsAndNormals, vertexValue + X_Add, colorNormal | CORD01);
				int i110 = addVertex(vertices, colorsAndNormals, vertexValue + Y_Add + X_Add, colorNormal | CORD00);
				faces.add(i000);
				faces.add(i110);
				faces.add(i100);

				faces.add(i000);
				faces.add(i010);
				faces.add(i110);
			}
			if ((neighbors & Neighbors.BIT_MASK[Neighbors.DIR_POS_Z]) != 0) {
				int normal = 3;
				int vertexValue = x | y << 6 | (z + 1) << 12 | voxelSize << 18;
				int colorNormal = BlockMeshes.textureIndices(block)[Neighbors.DIR_POS_Z] | (normal << 24);
				int i001 = addVertex(vertices, colorsAndNormals, vertexValue, colorNormal | CORD01);
				int i011 = addVertex(vertices, colorsAndNormals, vertexValue + Y_Add, colorNormal | CORD00);
				int i101 = addVertex(vertices, colorsAndNormals, vertexValue + X_Add, colorNormal | CORD11);
				int i111 = addVertex(vertices, colorsAndNormals, vertexValue + Y_Add + X_Add, colorNormal | CORD10);
				faces.add(i001);
				faces.add(i101);
				faces.add(i111);

				faces.add(i001);
				faces.add(i111);
				faces.add(i011);
			}
		}
	}
}
