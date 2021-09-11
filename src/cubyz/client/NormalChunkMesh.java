package cubyz.client;

import static org.lwjgl.opengl.GL11.*;
import static org.lwjgl.opengl.GL15.*;
import static org.lwjgl.opengl.GL20.*;
import static org.lwjgl.opengl.GL30.*;

import java.nio.FloatBuffer;
import java.nio.IntBuffer;
import java.util.ArrayList;

import org.joml.Vector3f;
import org.lwjgl.system.MemoryUtil;

import cubyz.rendering.ShaderProgram;
import cubyz.rendering.Window;
import cubyz.utils.Utils;
import cubyz.utils.datastructures.FastList;
import cubyz.utils.datastructures.FloatFastList;
import cubyz.utils.datastructures.IntFastList;
import cubyz.world.Chunk;
import cubyz.world.NormalChunk;
import cubyz.world.blocks.BlockInstance;

/**
 * Used to create chunk meshes for normal chunks.
 */

public class NormalChunkMesh extends ChunkMesh implements Runnable {
	// ThreadLocal lists, to prevent (re-)allocating tons of memory.
	public static ThreadLocal<FloatFastList> localVertices = new ThreadLocal<FloatFastList>() {
		@Override
		protected FloatFastList initialValue() {
			return new FloatFastList(50000);
		}
	};
	public static ThreadLocal<FloatFastList> localNormals = new ThreadLocal<FloatFastList>() {
		@Override
		protected FloatFastList initialValue() {
			return new FloatFastList(50000);
		}
	};
	public static ThreadLocal<IntFastList> localFaces = new ThreadLocal<IntFastList>() {
		@Override
		protected IntFastList initialValue() {
			return new IntFastList(30000);
		}
	};
	public static ThreadLocal<IntFastList> localLighting = new ThreadLocal<IntFastList>() {
		@Override
		protected IntFastList initialValue() {
			return new IntFastList(20000);
		}
	};
	public static ThreadLocal<IntFastList> localRenderIndices = new ThreadLocal<IntFastList>() {
		@Override
		protected IntFastList initialValue() {
			return new IntFastList(20000);
		}
	};
	public static ThreadLocal<FloatFastList> localTexture = new ThreadLocal<FloatFastList>() {
		@Override
		protected FloatFastList initialValue() {
			return new FloatFastList(40000);
		}
	};

	// Shader stuff:
	public static int loc_projectionMatrix;
	public static int loc_viewMatrix;
	public static int loc_texture_sampler;
	public static int loc_break_sampler;
	public static int loc_ambientLight;
	public static int loc_directionalLight;
	public static int loc_modelPosition;
	public static int loc_selectedIndex;
	public static int loc_atlasSize;
	public static int loc_fog_activ;
	public static int loc_fog_color;
	public static int loc_fog_density;

	public static ShaderProgram shader;

	public static void init(String shaderFolder) throws Exception {
		shader = new ShaderProgram(Utils.loadResource(shaderFolder + "/block_vertex.vs"),
				Utils.loadResource(shaderFolder + "/block_fragment.fs"),
				NormalChunkMesh.class);
	}

	public static void bindShader(Vector3f ambient, Vector3f directional) {
		shader.bind();

		shader.setUniform(loc_fog_activ, Cubyz.fog.isActive());
		shader.setUniform(loc_fog_color, Cubyz.fog.getColor());
		shader.setUniform(loc_fog_density, Cubyz.fog.getDensity());
		shader.setUniform(loc_projectionMatrix, Window.getProjectionMatrix());
		shader.setUniform(loc_texture_sampler, 0);
		shader.setUniform(loc_break_sampler, 2);
		shader.setUniform(loc_viewMatrix, Cubyz.camera.getViewMatrix());

		shader.setUniform(loc_ambientLight, ambient);
		shader.setUniform(loc_directionalLight, directional);
		
		shader.setUniform(loc_atlasSize, Meshes.atlasSize);
	}
	
	protected int vaoId;

	protected ArrayList<Integer> vboIdList = new ArrayList<>();
	
	protected int transparentVaoId;

	protected ArrayList<Integer> transparentVboIdList = new ArrayList<>();

	protected int vertexCount;

	protected int transparentVertexCount;

	private NormalChunk chunk;
	
	private boolean needsUpdate = false;

	public NormalChunkMesh(ReducedChunkMesh replacement, int wx, int wy, int wz, int size) {
		super(replacement, wx, wy, wz, size);
	}

	@Override
	public void run() {
		synchronized(this) {
			if(!needsUpdate) {
				needsUpdate = true;
				Meshes.queueMesh(this);
			}
		}
	}
	
	@Override
	public void regenerateMesh() {
		cleanUp();
		NormalChunk chunk;
		synchronized(this) {
			chunk = this.chunk;
			if(!needsUpdate)
				return;
			needsUpdate = false;
			if(chunk == null)
				return;
		}
		FloatFastList vertices = localVertices.get();
		FloatFastList normals = localNormals.get();
		IntFastList faces = localFaces.get();
		IntFastList lighting = localLighting.get();
		FloatFastList texture = localTexture.get();
		IntFastList renderIndices = localRenderIndices.get();
		normals.clear();
		vertices.clear();
		faces.clear();
		lighting.clear();
		texture.clear();
		renderIndices.clear();
		generateModelData(chunk, vertices, normals, faces, lighting, texture, renderIndices);
		vertexCount = faces.size;
		vboIdList.clear();
		vaoId = bufferData(vertices, normals, faces, lighting, texture, renderIndices, vboIdList);
		normals.clear();
		vertices.clear();
		faces.clear();
		lighting.clear();
		texture.clear();
		renderIndices.clear();
		generateTransparentModelData(chunk, vertices, normals, faces, lighting, texture, renderIndices);
		transparentVertexCount = faces.size;
		transparentVboIdList.clear();
		transparentVaoId = bufferData(vertices, normals, faces, lighting, texture, renderIndices, transparentVboIdList);
	}
	
	public int bufferData(FloatFastList vertices, FloatFastList normals, IntFastList faces, IntFastList lighting, FloatFastList texture, IntFastList renderIndices, ArrayList<Integer> vboIdList) {
		if(faces.size == 0) {
			return -1;
		}
		generated = true;
		
		FloatBuffer posBuffer = null;
		FloatBuffer textureBuffer = null;
		FloatBuffer normalBuffer = null;
		IntBuffer indexBuffer = null;
		IntBuffer lightingBuffer = null;
		IntBuffer renderIndexBuffer = null;
		try {
			int vaoId = glGenVertexArrays();
			glBindVertexArray(vaoId);

			// Position VBO
			int vboId = glGenBuffers();
			vboIdList.add(vboId);
			posBuffer = MemoryUtil.memAllocFloat(vertices.size);
			posBuffer.put(vertices.toArray()).flip();
			glBindBuffer(GL_ARRAY_BUFFER, vboId);
			glBufferData(GL_ARRAY_BUFFER, posBuffer, GL_STATIC_DRAW);
			glVertexAttribPointer(0, 3, GL_FLOAT, false, 0, 0);

			// Texture VBO
			vboId = glGenBuffers();
			vboIdList.add(vboId);
			textureBuffer = MemoryUtil.memAllocFloat(texture.size);
			textureBuffer.put(texture.toArray()).flip();
			glBindBuffer(GL_ARRAY_BUFFER, vboId);
			glBufferData(GL_ARRAY_BUFFER, textureBuffer, GL_STATIC_DRAW);
			glVertexAttribPointer(1, 2, GL_FLOAT, false, 0, 0);


			// Normal VBO
			vboId = glGenBuffers();
			vboIdList.add(vboId);
			normalBuffer = MemoryUtil.memAllocFloat(normals.size);
			normalBuffer.put(normals.toArray()).flip();
			glBindBuffer(GL_ARRAY_BUFFER, vboId);
			glBufferData(GL_ARRAY_BUFFER, normalBuffer, GL_STATIC_DRAW);
			glVertexAttribPointer(2, 3, GL_FLOAT, false, 0, 0);

			// lighting VBO
			vboId = glGenBuffers();
			vboIdList.add(vboId);
			lightingBuffer = MemoryUtil.memAllocInt(lighting.size);
			lightingBuffer.put(lighting.toArray()).flip();
			glBindBuffer(GL_ARRAY_BUFFER, vboId);
			glBufferData(GL_ARRAY_BUFFER, lightingBuffer, GL_STATIC_DRAW);
			glVertexAttribPointer(3, 1, GL_FLOAT, false, 0, 0);

			// render index VBO
			vboId = glGenBuffers();
			vboIdList.add(vboId);
			renderIndexBuffer = MemoryUtil.memAllocInt(renderIndices.size);
			renderIndexBuffer.put(renderIndices.toArray()).flip();
			glBindBuffer(GL_ARRAY_BUFFER, vboId);
			glBufferData(GL_ARRAY_BUFFER, renderIndexBuffer, GL_STATIC_DRAW);
			glVertexAttribPointer(4, 1, GL_FLOAT, false, 0, 0);

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
			if (posBuffer != null) {
				MemoryUtil.memFree(posBuffer);
			}
			if (indexBuffer != null) {
				MemoryUtil.memFree(indexBuffer);
			}
			if (normalBuffer != null) {
				MemoryUtil.memFree(normalBuffer);
			}
			if (textureBuffer != null) {
				MemoryUtil.memFree(textureBuffer);
			}
			if (lightingBuffer != null) {
				MemoryUtil.memFree(lightingBuffer);
			}
			if (renderIndexBuffer != null) {
				MemoryUtil.memFree(renderIndexBuffer);
			}
		}
	}

	public void updateChunk(NormalChunk chunk) {
		if(chunk != this.chunk) {
			synchronized(this) {
				if(this.chunk != null)
					this.chunk.setMeshListener(null);
				this.chunk = chunk;
				if(chunk != null)
					chunk.setMeshListener(this);
				run();
			}
		}
	}

	@Override
	public Chunk getChunk() {
		return chunk;
	}

	@Override
	public void render() {
		if(chunk == null || !generated) {
			ReducedChunkMesh.shader.bind();
			glUniform3f(ReducedChunkMesh.loc_lowerBounds, wx, wy, wz);
			glUniform3f(ReducedChunkMesh.loc_upperBounds, wx+size, wy+size, wz+size);
			if(replacement != null) {
				replacement.renderReplacement();
			}
			glUniform3f(ReducedChunkMesh.loc_lowerBounds, Float.NEGATIVE_INFINITY, Float.NEGATIVE_INFINITY, Float.NEGATIVE_INFINITY);
			glUniform3f(ReducedChunkMesh.loc_upperBounds, Float.POSITIVE_INFINITY, Float.POSITIVE_INFINITY, Float.POSITIVE_INFINITY);
			shader.bind();
			return;
		}
		if(vaoId == -1) return;
		glUniform3f(loc_modelPosition, wx, wy, wz);
		// Init
		glBindVertexArray(vaoId);
		glEnableVertexAttribArray(0);
		glEnableVertexAttribArray(1);
		glEnableVertexAttribArray(2);
		glEnableVertexAttribArray(3);
		glEnableVertexAttribArray(4);
		// Draw
		glDrawElements(GL_TRIANGLES, vertexCount, GL_UNSIGNED_INT, 0);
		// Restore state
		glDisableVertexAttribArray(0);
		glDisableVertexAttribArray(1);
		glDisableVertexAttribArray(2);
		glDisableVertexAttribArray(3);
		glDisableVertexAttribArray(4);
		glBindVertexArray(0);
	}

	public void renderTransparent() {
		if(transparentVaoId == -1) return;
		glUniform3f(loc_modelPosition, wx, wy, wz);
		// Init
		glBindVertexArray(transparentVaoId);
		glEnableVertexAttribArray(0);
		glEnableVertexAttribArray(1);
		glEnableVertexAttribArray(2);
		glEnableVertexAttribArray(3);
		glEnableVertexAttribArray(4);
		// Draw
		glDrawElements(GL_TRIANGLES, transparentVertexCount, GL_UNSIGNED_INT, 0);
		// Restore state
		glDisableVertexAttribArray(0);
		glDisableVertexAttribArray(1);
		glDisableVertexAttribArray(2);
		glDisableVertexAttribArray(3);
		glDisableVertexAttribArray(4);
		glBindVertexArray(0);
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
	
	private static void generateModelData(NormalChunk chunk, FloatFastList vertices, FloatFastList normals, IntFastList faces, IntFastList lighting, FloatFastList texture, IntFastList renderIndices) {
		// Go through all blocks and check their neighbors:
		FastList<BlockInstance> visibles = chunk.getVisibles();
		int index = 0;
		for(int i = 0; i < visibles.size; i++) {
			BlockInstance bi = visibles.array[i];
			if(!bi.getBlock().isTransparent()) {
				bi.updateLighting(chunk.getWorldX(), chunk.getWorldZ(), chunk);
				bi.renderIndex = index;
				index = bi.getBlock().mode.generateChunkMesh(bi, vertices, normals, faces, lighting, texture, renderIndices, index);
			}
		}
	}
	
	private static void generateTransparentModelData(NormalChunk chunk, FloatFastList vertices, FloatFastList normals, IntFastList faces, IntFastList lighting, FloatFastList texture, IntFastList renderIndices) {
		// Go through all blocks and check their neighbors:
		FastList<BlockInstance> visibles = chunk.getVisibles();
		int index = 0;
		for(int i = 0; i < visibles.size; i++) {
			BlockInstance bi = visibles.array[i];
			if(bi.getBlock().isTransparent()) {
				bi.updateLighting(chunk.getWorldX(), chunk.getWorldZ(), chunk);
				bi.renderIndex = index;
				index = bi.getBlock().mode.generateChunkMesh(bi, vertices, normals, faces, lighting, texture, renderIndices, index);
			}
		}
	}
}
