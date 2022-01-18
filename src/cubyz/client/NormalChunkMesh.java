package cubyz.client;

import static org.lwjgl.opengl.GL11.*;
import static org.lwjgl.opengl.GL15.*;
import static org.lwjgl.opengl.GL20.*;
import static org.lwjgl.opengl.GL30.*;

import java.nio.IntBuffer;
import java.util.ArrayList;

import org.joml.Vector3d;
import org.joml.Vector3f;
import org.lwjgl.system.MemoryUtil;

import cubyz.rendering.Camera;
import cubyz.rendering.ShaderProgram;
import cubyz.rendering.Window;
import cubyz.utils.Utils;
import cubyz.utils.VertexAttribList;
import cubyz.utils.datastructures.FastList;
import cubyz.utils.datastructures.IntFastList;
import cubyz.world.ChunkData;
import cubyz.world.NormalChunk;
import cubyz.world.blocks.BlockInstance;
import cubyz.world.blocks.Blocks;

/**
 * Used to create chunk meshes for normal chunks.
 */

public class NormalChunkMesh extends ChunkMesh {
	// ThreadLocal lists, to prevent (re-)allocating tons of memory.
	private static final ThreadLocal<VertexAttribList> localVertices = new ThreadLocal<VertexAttribList>() {
		@Override
		protected VertexAttribList initialValue() {
			return new VertexAttribList(SIZEOF_VERTEX);
		}
	};
	private static final ThreadLocal<IntFastList> localFaces = new ThreadLocal<IntFastList>() {
		@Override
		protected IntFastList initialValue() {
			return new IntFastList(30000);
		}
	};
	
	public static final int POSITION_X = 0;
	public static final int POSITION_Y = 1;
	public static final int POSITION_Z = 2;
	public static final int TEXTURE_X = 3;
	public static final int TEXTURE_Y = 4;
	public static final int TEXTURE_Z = 5;
	public static final int NORMAL_X = 6;
	public static final int NORMAL_Y = 7;
	public static final int NORMAL_Z = 8;
	public static final int LIGHTING = 9;
	private static final int SIZEOF_VERTEX = 10;

	// Shader stuff:
	public static int loc_projectionMatrix;
	public static int loc_viewMatrix;
	public static int loc_texture_sampler;
	public static int loc_ambientLight;
	public static int loc_directionalLight;
	public static int loc_modelPosition;
	public static int loc_fog_activ;
	public static int loc_fog_color;
	public static int loc_fog_density;
	public static int loc_time;

	public static abstract class TransparentUniforms {
		public static int loc_projectionMatrix;
		public static int loc_viewMatrix;
		public static int loc_texture_sampler;
		public static int loc_ambientLight;
		public static int loc_directionalLight;
		public static int loc_modelPosition;
		public static int loc_fog_activ;
		public static int loc_fog_color;
		public static int loc_fog_density;
		public static int loc_waterFog_activ;
		public static int loc_waterFog_color;
		public static int loc_waterFog_density;
		public static int loc_positionBuffer;
		public static int loc_colorBuffer;
		public static int loc_windowSize;
		public static int loc_drawFrontFace;
		public static int loc_time;
	}

	public static ShaderProgram shader;
	public static ShaderProgram transparentShader;

	public static void init(String shaderFolder) throws Exception {
		if (shader != null)
			shader.cleanup();
		shader = new ShaderProgram(Utils.loadResource(shaderFolder + "/block_vertex.vs"),
				Utils.loadResource(shaderFolder + "/block_fragment.fs"),
				NormalChunkMesh.class);
		if (transparentShader != null)
			transparentShader.cleanup();
		transparentShader = new ShaderProgram(Utils.loadResource(shaderFolder + "/transparent_vertex.vs"),
				Utils.loadResource(shaderFolder + "/transparent_fragment.fs"),
				TransparentUniforms.class);
	}

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
		shader.setUniform(loc_projectionMatrix, Window.getProjectionMatrix());
		shader.setUniform(loc_texture_sampler, 0);
		shader.setUniform(loc_viewMatrix, Camera.getViewMatrix());

		shader.setUniform(loc_ambientLight, ambient);
		shader.setUniform(loc_directionalLight, directional);

		shader.setUniform(loc_time, time);
	}

	/**
	 * Also updates the uniforms.
	 * @param ambient
	 * @param directional
	 */
	public static void bindTransparentShader(Vector3f ambient, Vector3f directional, int time) {
		transparentShader.bind();

		transparentShader.setUniform(TransparentUniforms.loc_fog_activ, Cubyz.fog.isActive());
		transparentShader.setUniform(TransparentUniforms.loc_fog_color, Cubyz.fog.getColor());
		transparentShader.setUniform(TransparentUniforms.loc_fog_density, Cubyz.fog.getDensity());
		transparentShader.setUniform(TransparentUniforms.loc_projectionMatrix, Window.getProjectionMatrix());
		transparentShader.setUniform(TransparentUniforms.loc_texture_sampler, 0);
		transparentShader.setUniform(TransparentUniforms.loc_viewMatrix, Camera.getViewMatrix());

		transparentShader.setUniform(TransparentUniforms.loc_ambientLight, ambient);
		transparentShader.setUniform(TransparentUniforms.loc_directionalLight, directional);

		glUniform2f(TransparentUniforms.loc_windowSize, Window.getWidth(), Window.getHeight());

		transparentShader.setUniform(TransparentUniforms.loc_colorBuffer, 3);
		transparentShader.setUniform(TransparentUniforms.loc_positionBuffer, 4);

		transparentShader.setUniform(TransparentUniforms.loc_time, time);
	}
	
	protected int vaoId = -1;

	protected ArrayList<Integer> vboIdList = new ArrayList<>();
	
	protected int transparentVaoId = -1;

	protected ArrayList<Integer> transparentVboIdList = new ArrayList<>();

	protected int vertexCount;

	protected int transparentVertexCount;

	private NormalChunk chunk;
	
	private boolean needsUpdate = false;

	public NormalChunkMesh(ReducedChunkMesh replacement, int wx, int wy, int wz, int size) {
		super(replacement, wx, wy, wz, size);
	}
	
	@Override
	public void regenerateMesh() {
		cleanUp();
		NormalChunk chunk;
		synchronized(this) {
			chunk = this.chunk;
			if (!needsUpdate)
				return;
			needsUpdate = false;
			if (chunk == null || !chunk.isLoaded())
				return;
		}
		VertexAttribList vertices = localVertices.get();
		IntFastList faces = localFaces.get();
		vertices.clear();
		faces.clear();
		generateModelData(chunk, vertices, faces);
		vertexCount = faces.size;
		vboIdList.clear();
		vaoId = bufferData(vertices, faces, vboIdList);
		vertices.clear();
		faces.clear();
		generateTransparentModelData(chunk, vertices, faces);
		transparentVertexCount = faces.size;
		transparentVboIdList.clear();
		transparentVaoId = bufferData(vertices, faces, transparentVboIdList);
	}
	
	public int bufferData(VertexAttribList vertices, IntFastList faces, ArrayList<Integer> vboIdList) {
		
		generated = true;
		if (faces.size == 0) {
			return -1;
		}

		IntBuffer vertexBuffer = null;
		IntBuffer indexBuffer = null;
		try {
			int vaoId = glGenVertexArrays();
			glBindVertexArray(vaoId);
			// Enable vertex arrays once.
			glEnableVertexAttribArray(0);
			glEnableVertexAttribArray(1);
			glEnableVertexAttribArray(2);
			glEnableVertexAttribArray(3);

			// Position VBO
			int vboId = glGenBuffers();
			vboIdList.add(vboId);
			vertexBuffer = MemoryUtil.memAllocInt(vertices.size());
			vertexBuffer.put(vertices.toArray()).flip();
			glBindBuffer(GL_ARRAY_BUFFER, vboId);
			glBufferData(GL_ARRAY_BUFFER, vertexBuffer, GL_STATIC_DRAW);
			glVertexAttribPointer(0, 3, GL_FLOAT, false, SIZEOF_VERTEX*4, POSITION_X*4);
			glVertexAttribPointer(1, 3, GL_FLOAT, false, SIZEOF_VERTEX*4, TEXTURE_X*4);
			glVertexAttribPointer(2, 3, GL_FLOAT, false, SIZEOF_VERTEX*4, NORMAL_X*4);
			glVertexAttribPointer(3, 1, GL_FLOAT, false, SIZEOF_VERTEX*4, LIGHTING*4);

			// Index VBO
			vboId = glGenBuffers();
			vboIdList.add(vboId);
			indexBuffer = MemoryUtil.memAllocInt(faces.size);
			indexBuffer.put(faces.toArray()).flip();
			glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, vboId);
			glBufferData(GL_ELEMENT_ARRAY_BUFFER, indexBuffer, GL_STATIC_DRAW);

			glBindBuffer(GL_ARRAY_BUFFER, 0);
			glBindVertexArray(0);
			return vaoId;
		} finally {
			if (vertexBuffer != null) {
				MemoryUtil.memFree(vertexBuffer);
			}
		}
	}

	public void updateChunk(NormalChunk chunk) {
		synchronized(this) {
			this.chunk = chunk;
			if (chunk == null)
				generated = false;
			if (!needsUpdate) {
				needsUpdate = true;
				Meshes.queueMesh(this);
			}
		}
	}

	@Override
	public ChunkData getChunk() {
		return chunk;
	}

	@Override
	public void render(Vector3d playerPosition) {
		if (chunk == null || !generated) {
			ReducedChunkMesh.shader.bind();
			glUniform3f(ReducedChunkMesh.loc_lowerBounds, (float)(wx - playerPosition.x - 0.001), (float)(wy - playerPosition.y - 0.001), (float)(wz - playerPosition.z - 0.001));
			glUniform3f(ReducedChunkMesh.loc_upperBounds, (float)(wx + size - playerPosition.x + 0.001), (float)(wy + size - playerPosition.y + 0.001), (float)(wz + size - playerPosition.z + 0.001));
			if (replacement != null) {
				replacement.render(playerPosition);
			}
			glUniform3f(ReducedChunkMesh.loc_lowerBounds, Float.NEGATIVE_INFINITY, Float.NEGATIVE_INFINITY, Float.NEGATIVE_INFINITY);
			glUniform3f(ReducedChunkMesh.loc_upperBounds, Float.POSITIVE_INFINITY, Float.POSITIVE_INFINITY, Float.POSITIVE_INFINITY);
			shader.bind();
			return;
		}
		if (vaoId == -1) return;
		glUniform3f(loc_modelPosition, (float)(wx - playerPosition.x), (float)(wy - playerPosition.y), (float)(wz - playerPosition.z));

		glBindVertexArray(vaoId);

		glDrawElements(GL_TRIANGLES, vertexCount, GL_UNSIGNED_INT, 0);
	}

	public void renderTransparent(Vector3d playerPosition) {
		if (transparentVaoId == -1) return;

		glUniform3f(TransparentUniforms.loc_modelPosition, (float)(wx - playerPosition.x), (float)(wy - playerPosition.y), (float)(wz - playerPosition.z));

		glBindVertexArray(transparentVaoId);
		glDrawElements(GL_TRIANGLES, transparentVertexCount, GL_UNSIGNED_INT, 0);
	}

	@Override
	public void cleanUp() {
		// Delete the VBOs
		glBindBuffer(GL_ARRAY_BUFFER, 0);
		for (int vboId : vboIdList) {
			glDeleteBuffers(vboId);
		}
		for (int vboId : transparentVboIdList) {
			glDeleteBuffers(vboId);
		}

		// Delete the VAO
		glBindVertexArray(0);
		glDeleteVertexArrays(vaoId);
		glDeleteVertexArrays(transparentVaoId);
		vaoId = transparentVaoId = -1;
	}
	
	private static void generateModelData(NormalChunk chunk, VertexAttribList vertices, IntFastList faces) {
		// Go through all blocks and check their neighbors:
		FastList<BlockInstance> visibles = chunk.getVisibles();
		for(int i = 0; i < visibles.size; i++) {
			BlockInstance bi = visibles.array[i];
			if (!Blocks.transparent(bi.getBlock())) {
				bi.updateLighting(chunk.wx, chunk.wz, chunk);
				Blocks.mode(bi.getBlock()).generateChunkMesh(bi, vertices, faces);
			}
		}
	}
	
	private static void generateTransparentModelData(NormalChunk chunk, VertexAttribList vertices, IntFastList faces) {
		// Go through all blocks and check their neighbors:
		FastList<BlockInstance> visibles = chunk.getVisibles();
		for(int i = 0; i < visibles.size; i++) {
			BlockInstance bi = visibles.array[i];
			if (Blocks.transparent(bi.getBlock())) {
				bi.updateLighting(chunk.wx, chunk.wz, chunk);
				Blocks.mode(bi.getBlock()).generateChunkMesh(bi, vertices, faces);
			}
		}
	}
}
