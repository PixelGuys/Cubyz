package io.cubyz.client;

import static org.lwjgl.opengl.GL11.*;
import static org.lwjgl.opengl.GL15.*;
import static org.lwjgl.opengl.GL20.*;
import static org.lwjgl.opengl.GL30.*;

import java.nio.FloatBuffer;
import java.nio.IntBuffer;
import java.util.ArrayList;

import org.lwjgl.system.MemoryUtil;

import io.cubyz.blocks.BlockInstance;
import io.cubyz.entity.Player;
import io.cubyz.math.CubyzMath;
import io.cubyz.util.FastList;
import io.cubyz.util.FloatFastList;
import io.cubyz.util.IntFastList;
import io.cubyz.world.NormalChunk;
import io.cubyz.world.ReducedChunk;

/**
 * Used to create chunk meshes for reduced chunks.
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
	public static ThreadLocal<FloatFastList> localTexture = new ThreadLocal<FloatFastList>() {
		@Override
		protected FloatFastList initialValue() {
			return new FloatFastList(40000);
		}
	};
	
	protected int vaoId;

	protected ArrayList<Integer> vboIdList;

	protected int vertexCount;

	public NormalChunkMesh(NormalChunk chunk, Player player) {
		FloatFastList vertices = localVertices.get();
		FloatFastList normals = localNormals.get();
		IntFastList faces = localFaces.get();
		IntFastList lighting = localLighting.get();
		FloatFastList texture = localTexture.get();
		normals.clear();
		vertices.clear();
		faces.clear();
		lighting.clear();
		texture.clear();
		generateModelData(chunk, player, vertices, normals, faces, lighting, texture);
		FloatBuffer posBuffer = null;
		FloatBuffer textureBuffer = null;
		FloatBuffer normalBuffer = null;
		IntBuffer indexBuffer = null;
		IntBuffer lightingBuffer = null;
		try {
			vertexCount = faces.size;
			vboIdList = new ArrayList<>();

			vaoId = glGenVertexArrays();
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
			if (normalBuffer != null) {
				MemoryUtil.memFree(normalBuffer);
			}
			if (textureBuffer != null) {
				MemoryUtil.memFree(textureBuffer);
			}
			if (lightingBuffer != null) {
				MemoryUtil.memFree(lightingBuffer);
			}
		}
	}

	public void render() {
		// Init
		glBindVertexArray(vaoId);
		glEnableVertexAttribArray(0);
		glEnableVertexAttribArray(1);
		glEnableVertexAttribArray(2);
		glEnableVertexAttribArray(3);
		// Draw
		glDrawElements(GL_TRIANGLES, vertexCount, GL_UNSIGNED_INT, 0);
		// Restore state
		glDisableVertexAttribArray(0);
		glDisableVertexAttribArray(1);
		glDisableVertexAttribArray(2);
		glDisableVertexAttribArray(3);
		glBindVertexArray(0);
	}

	public void cleanUp() {
		glDisableVertexAttribArray(0);

		// Delete the VBOs
		glBindBuffer(GL_ARRAY_BUFFER, 0);
		for (int vboId : vboIdList) {
			glDeleteBuffers(vboId);
		}

		// Delete the VAO
		glBindVertexArray(0);
		glDeleteVertexArrays(vaoId);
	}
	
	private static void generateModelData(NormalChunk chunk, Player player, FloatFastList vertices, FloatFastList normals, IntFastList faces, IntFastList lighting, FloatFastList texture) {
		// Go through all blocks and check their neighbors:
		FastList<BlockInstance> visibles = chunk.getVisibles();
		for(int i = 0; i < visibles.size; i++) {
			BlockInstance bi = visibles.array[i];
			bi.getSpatials(player, chunk.getWorldX(), chunk.getWorldZ(), chunk);
			bi.getBlock().mode.generateChunkMesh(bi, vertices, normals, faces, lighting, texture);
		}
	}
}
