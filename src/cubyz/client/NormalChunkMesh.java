package cubyz.client;

import static org.lwjgl.opengl.GL11.GL_FLOAT;
import static org.lwjgl.opengl.GL11.GL_TRIANGLES;
import static org.lwjgl.opengl.GL11.GL_UNSIGNED_INT;
import static org.lwjgl.opengl.GL11.glDrawElements;
import static org.lwjgl.opengl.GL15.GL_ARRAY_BUFFER;
import static org.lwjgl.opengl.GL15.GL_ELEMENT_ARRAY_BUFFER;
import static org.lwjgl.opengl.GL15.GL_STATIC_DRAW;
import static org.lwjgl.opengl.GL15.glBindBuffer;
import static org.lwjgl.opengl.GL15.glBufferData;
import static org.lwjgl.opengl.GL15.glDeleteBuffers;
import static org.lwjgl.opengl.GL15.glGenBuffers;
import static org.lwjgl.opengl.GL20.glDisableVertexAttribArray;
import static org.lwjgl.opengl.GL20.glEnableVertexAttribArray;
import static org.lwjgl.opengl.GL20.glVertexAttribPointer;
import static org.lwjgl.opengl.GL30.glBindVertexArray;
import static org.lwjgl.opengl.GL30.glDeleteVertexArrays;
import static org.lwjgl.opengl.GL30.glGenVertexArrays;

import java.nio.FloatBuffer;
import java.nio.IntBuffer;
import java.util.ArrayList;

import org.lwjgl.system.MemoryUtil;

import cubyz.utils.datastructures.FastList;
import cubyz.utils.datastructures.FloatFastList;
import cubyz.utils.datastructures.IntFastList;
import cubyz.world.NormalChunk;
import cubyz.world.blocks.BlockInstance;

/**
 * Used to create chunk meshes for normal chunks.
 */

public class NormalChunkMesh {
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
	
	protected int vaoId;

	protected ArrayList<Integer> vboIdList;
	
	protected int transparentVaoId;

	protected ArrayList<Integer> transparentVboIdList;

	protected int vertexCount;

	protected int transparentVertexCount;

	public NormalChunkMesh(NormalChunk chunk) {
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
		vboIdList = new ArrayList<>();
		vaoId = bufferData(vertices, normals, faces, lighting, texture, renderIndices, vboIdList);
		normals.clear();
		vertices.clear();
		faces.clear();
		lighting.clear();
		texture.clear();
		renderIndices.clear();
		generateTransparentModelData(chunk, vertices, normals, faces, lighting, texture, renderIndices);
		transparentVertexCount = faces.size;
		transparentVboIdList = new ArrayList<>();
		transparentVaoId = bufferData(vertices, normals, faces, lighting, texture, renderIndices, transparentVboIdList);
	}
	
	public int bufferData(FloatFastList vertices, FloatFastList normals, IntFastList faces, IntFastList lighting, FloatFastList texture, IntFastList renderIndices, ArrayList<Integer> vboIdList) {
		if(faces.size == 0) return -1;
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

	public void render() {
		if(vaoId == -1) return;
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
