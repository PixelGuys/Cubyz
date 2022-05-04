package cubyz.client;

import static org.lwjgl.opengl.GL43.*;

import org.joml.Matrix4f;
import org.joml.Vector3d;
import org.joml.Vector3f;

import cubyz.rendering.Camera;
import cubyz.rendering.SSBO;
import cubyz.rendering.ShaderProgram;
import cubyz.utils.Utils;
import cubyz.utils.datastructures.IntSimpleList;
import cubyz.world.ChunkData;
import cubyz.world.Neighbors;
import cubyz.world.ReducedChunkVisibilityData;

/**
 * Used to create chunk meshes for reduced chunks.
 */

public class ReducedChunkMesh extends ChunkMesh {
	// ThreadLocal lists, to prevent (re-)allocating tons of memory.
	private static final ThreadLocal<IntSimpleList> localFaces = ThreadLocal.withInitial(() -> new IntSimpleList(30000));

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
	public static int loc_texture_sampler;
	public static int loc_emissionSampler;
	public static int loc_waterFog_activ;
	public static int loc_waterFog_color;
	public static int loc_waterFog_density;
	public static int loc_time;

	public static ShaderProgram shader;

	private final SSBO faceData = new SSBO(); // TODO: delete after usage.
	private static final int emptyVAO;


	static {
		emptyVAO = glGenVertexArrays();
		glBindVertexArray(emptyVAO);
		int vboId = glGenBuffers();
		int[] buffer = new int[6*3 << 15]; // 6 vertices per face, maximum 3 faces/block
		int[] lut = new int[]{0, 1, 2, 2, 1, 3};
		for(int i = 0; i < buffer.length; i++) {
			buffer[i] = i/6*4 + lut[i%6];
		}
		glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, vboId);
		glBufferData(GL_ELEMENT_ARRAY_BUFFER, buffer, GL_STATIC_DRAW);
		glBindBuffer(GL_ARRAY_BUFFER, 0);
		glBindVertexArray(0);
	}
	
	public static void init(String shaderFolder) throws Exception {
		if (shader != null)
			shader.cleanup();
		shader = new ShaderProgram(
			Utils.loadResource(shaderFolder + "/chunk_vertex.vs"),
			Utils.loadResource(shaderFolder + "/chunk_fragment.fs"),
			ReducedChunkMesh.class
		);
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
		shader.setUniform(loc_emissionSampler, 1);
		
		shader.setUniform(loc_viewMatrix, Camera.getViewMatrix());

		shader.setUniform(loc_ambientLight, ambient);
		shader.setUniform(loc_directionalLight, directional);

		shader.setUniform(loc_time, time);

		glBindVertexArray(emptyVAO);
	}

	/**
	 * Does all the binding, when it's used as a replacement mesh.
	 */
	static void bindAsReplacement() {
		shader.bind();
		glBindVertexArray(emptyVAO);
	}

	protected int vertexCount;

	private ReducedChunkVisibilityData chunkVisibilityData;

	private boolean needsUpdate = false;

	private boolean wasDeleted = false;

	public ReducedChunkMesh(ReducedChunkMesh replacement, int wx, int wy, int wz, int size) {
		super(replacement, wx, wy, wz, size);
	}

	public void updateChunk(ReducedChunkVisibilityData data) {
		assert !wasDeleted : "This mesh is already deleted...";
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
		if(wasDeleted) return; // No need to regenerate a deleted mesh.
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

		IntSimpleList faces = localFaces.get();

		faces.clear();
		faces.add(chunkVisibilityData.voxelSize);
		generateSimpleModelData(chunkVisibilityData, faces);
		vertexCount = 6*(faces.size - 1)/2;
		faceData.bufferData(faces.toArray());
	}

	@Override
	public ChunkData getChunk() {
		return this;
	}

	@Override
	public void render(Vector3d playerPosition) {
		assert !wasDeleted : "This mesh is already deleted...";
		if (chunkVisibilityData == null || !generated) {
			if(replacement == null) return;
			glUniform3f(
				ReducedChunkMesh.loc_lowerBounds,
				(float)(wx - playerPosition.x - 0.001),
				(float)(wy - playerPosition.y - 0.001),
				(float)(wz - playerPosition.z - 0.001)
			);
			glUniform3f(
				ReducedChunkMesh.loc_upperBounds,
				(float)(wx + size - playerPosition.x + 0.001),
				(float)(wy + size - playerPosition.y + 0.001),
				(float)(wz + size - playerPosition.z + 0.001)
			);
			replacement.render(playerPosition);

			glUniform3f(loc_lowerBounds, Float.NEGATIVE_INFINITY, Float.NEGATIVE_INFINITY, Float.NEGATIVE_INFINITY);
			glUniform3f(loc_upperBounds, Float.POSITIVE_INFINITY, Float.POSITIVE_INFINITY, Float.POSITIVE_INFINITY);
			return;
		}
		glUniform3f(loc_modelPosition, (float)(wx - playerPosition.x), (float)(wy - playerPosition.y), (float)(wz - playerPosition.z));

		faceData.bind(3);
		glDrawElements(GL_TRIANGLES, vertexCount, GL_UNSIGNED_INT, 0);
	}

	@Override
	public void delete() {
		assert !wasDeleted : "This mesh is already deleted...";
		wasDeleted = true;
		faceData.delete();
	}

	@Override
	public void finalize() {
		assert wasDeleted : "Memory leak.";
	}

	private static void generateSimpleModelData(ReducedChunkVisibilityData chunkVisibilityData, IntSimpleList faces) {
		for(int i = 0; i < chunkVisibilityData.size; i++) {
			int block = chunkVisibilityData.visibleBlocks[i];
			int x = chunkVisibilityData.x[i];
			int y = chunkVisibilityData.y[i];
			int z = chunkVisibilityData.z[i];
			byte neighbors = chunkVisibilityData.neighbors[i];
			if ((neighbors & Neighbors.BIT_MASK[Neighbors.DIR_NEG_X]) != 0) {
				int normal = 0;
				int position = x | y << 6 | z << 12;
				int textureNormal = BlockMeshes.textureIndices(block)[Neighbors.DIR_NEG_X] | (normal << 24);
				faces.add(position);
				faces.add(textureNormal);
			}
			if ((neighbors & Neighbors.BIT_MASK[Neighbors.DIR_POS_X]) != 0) {
				int normal = 1;
				int position = x + 1 | y << 6 | z << 12;
				int textureNormal = BlockMeshes.textureIndices(block)[Neighbors.DIR_POS_X] | (normal << 24);
				faces.add(position);
				faces.add(textureNormal);
			}
			if ((neighbors & Neighbors.BIT_MASK[Neighbors.DIR_DOWN]) != 0) {
				int normal = 4;
				int position = x | y << 6 | z << 12;
				int textureNormal = BlockMeshes.textureIndices(block)[Neighbors.DIR_DOWN] | (normal << 24);
				faces.add(position);
				faces.add(textureNormal);
			}
			if ((neighbors & Neighbors.BIT_MASK[Neighbors.DIR_UP]) != 0) {
				int normal = 5;
				int position = x | (y + 1) << 6 | z << 12;
				int textureNormal = BlockMeshes.textureIndices(block)[Neighbors.DIR_UP] | (normal << 24);
				faces.add(position);
				faces.add(textureNormal);
			}
			if ((neighbors & Neighbors.BIT_MASK[Neighbors.DIR_NEG_Z]) != 0) {
				int normal = 2;
				int position = x | y << 6 | z << 12;
				int textureNormal = BlockMeshes.textureIndices(block)[Neighbors.DIR_NEG_Z] | (normal << 24);
				faces.add(position);
				faces.add(textureNormal);
			}
			if ((neighbors & Neighbors.BIT_MASK[Neighbors.DIR_POS_Z]) != 0) {
				int normal = 3;
				int position = x | y << 6 | (z + 1) << 12;
				int textureNormal = BlockMeshes.textureIndices(block)[Neighbors.DIR_POS_Z] | (normal << 24);
				faces.add(position);
				faces.add(textureNormal);
			}
		}
	}
}
