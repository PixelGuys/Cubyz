package io.cubyz.client;

import static org.lwjgl.opengl.GL11.*;
import static org.lwjgl.opengl.GL15.*;
import static org.lwjgl.opengl.GL20.*;
import static org.lwjgl.opengl.GL30.*;

import java.nio.FloatBuffer;
import java.nio.IntBuffer;
import java.util.ArrayList;

import org.lwjgl.system.MemoryUtil;

import io.cubyz.math.CubyzMath;
import io.cubyz.util.FloatFastList;
import io.cubyz.util.IntFastList;
import io.cubyz.world.ReducedChunk;

/**
 * Used to create chunk meshes for reduced chunks.
 */

public class ReducedChunkMesh {
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
	public static ThreadLocal<IntFastList> localColors = new ThreadLocal<IntFastList>() {
		@Override
		protected IntFastList initialValue() {
			return new IntFastList(20000);
		}
	};
	
	protected int vaoId;

	protected ArrayList<Integer> vboIdList;

	protected int vertexCount;
	
	private boolean inited = false;

	public ReducedChunkMesh(ReducedChunk chunk) {
		FloatFastList vertices = localVertices.get();
		FloatFastList normals = localNormals.get();
		IntFastList faces = localFaces.get();
		IntFastList colors = localColors.get();
		normals.clear();
		vertices.clear();
		faces.clear();
		colors.clear();
		generateModelData(chunk, vertices, normals, faces, colors);
		FloatBuffer posBuffer = null;
		FloatBuffer normalBuffer = null;
		IntBuffer indexBuffer = null;
		IntBuffer colorBuffer = null;
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


			// Normal VBO
			vboId = glGenBuffers();
			vboIdList.add(vboId);
			normalBuffer = MemoryUtil.memAllocFloat(normals.size);
			normalBuffer.put(normals.toArray()).flip();
			glBindBuffer(GL_ARRAY_BUFFER, vboId);
			glBufferData(GL_ARRAY_BUFFER, normalBuffer, GL_STATIC_DRAW);
			glVertexAttribPointer(1, 3, GL_FLOAT, false, 0, 0);

			// Color VBO
			vboId = glGenBuffers();
			vboIdList.add(vboId);
			colorBuffer = MemoryUtil.memAllocInt(colors.size);
			colorBuffer.put(colors.toArray()).flip();
			glBindBuffer(GL_ARRAY_BUFFER, vboId);
			glBufferData(GL_ARRAY_BUFFER, colorBuffer, GL_STATIC_DRAW);
			glVertexAttribPointer(2, 1, GL_FLOAT, false, 0, 0);

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
			if (colorBuffer != null) {
				MemoryUtil.memFree(colorBuffer);
			}
		}
	}

	public void render() {
		// Init
		glBindVertexArray(vaoId);
		glEnableVertexAttribArray(0);
		glEnableVertexAttribArray(1);
		glEnableVertexAttribArray(2);
		// Draw
		glDrawElements(GL_TRIANGLES, vertexCount, GL_UNSIGNED_INT, 0);
		// Restore state
		glDisableVertexAttribArray(0);
		glDisableVertexAttribArray(1);
		glDisableVertexAttribArray(2);
		glBindVertexArray(0);
	}

	public void cleanUp() {
		if(!inited) return;
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
	
	/**
	 * Adds a vertex and color and returns the index.
	 * @param vertices
	 * @param x
	 * @param y
	 * @param z
	 * @return
	 */
	private static int addVertex(FloatFastList vertices, float x, float y, float z, IntFastList colors, int color) {
		int index = vertices.size/3;
		vertices.add(x);
		vertices.add(y);
		vertices.add(z);
		colors.add(color);
		return index;
	}
	
	private static void addNormals(FloatFastList normals, float x, float y, float z, int amount) {
		for(int i = 0; i < amount; i++) {
			normals.add(x);
			normals.add(y);
			normals.add(z);
		}
	}
	
	private static void generateModelData(ReducedChunk chunk, FloatFastList vertices, FloatFastList normals, IntFastList faces, IntFastList colors) {
		int zMask = (chunk.width - 1) >>> chunk.resolutionShift;
		int xMask = zMask << (chunk.widthShift - chunk.resolutionShift);
		int yMask = (255 >>> chunk.resolutionShift) << 2*(chunk.widthShift - chunk.resolutionShift);
		int zDelta = 1;
		int xDelta = 1 << (chunk.widthShift - chunk.resolutionShift);
		int yDelta = 1 << 2*(chunk.widthShift - chunk.resolutionShift);
		int offset = 1 << chunk.resolutionShift;
		// Go through all blocks and check their neighbors:
		for(int i = 0; i < chunk.size; i++) {
			if(chunk.blocks[i] == null) continue;
			boolean posX = true, negX = true, posY = true, negY = true, posZ = true, negZ = true;
			if((i & xMask) != 0 && chunk.blocks[i - xDelta] != null) negX = false;
			if((i & xMask) != xMask && chunk.blocks[i + xDelta] != null) posX = false;
			if((i & yMask) == 0 || chunk.blocks[i - yDelta] != null) negY = false; // Never draw the bedrock face of a chunk.
			if((i & yMask) != yMask && chunk.blocks[i + yDelta] != null) posY = false;
			if((i & zMask) != 0 && chunk.blocks[i - zDelta] != null) negZ = false;
			if((i & zMask) != zMask && chunk.blocks[i + zDelta] != null) posZ = false;
			float x = CubyzMath.shiftRight(i & xMask, chunk.widthShift - 2*chunk.resolutionShift) - 0.5f;
			float y = CubyzMath.shiftRight(i & yMask, 2*chunk.widthShift - 3*chunk.resolutionShift) - 0.5f;
			float z = ((i & zMask) << chunk.resolutionShift) - 0.5f;
			int color = chunk.blocks[i].color & 65535;
			if(negX) {
				int i000 = addVertex(vertices, x, y, z, colors, color);
				int i001 = addVertex(vertices, x, y, z + offset, colors, color);
				int i010 = addVertex(vertices, x, y + offset, z, colors, color);
				int i011 = addVertex(vertices, x, y + offset, z + offset, colors, color);
				addNormals(normals, -1, 0, 0, 4);
				faces.add(i000);
				faces.add(i001);
				faces.add(i011);

				faces.add(i000);
				faces.add(i011);
				faces.add(i010);
			}
			if(posX) {
				int i100 = addVertex(vertices, x + offset, y, z, colors, color);
				int i101 = addVertex(vertices, x + offset, y, z + offset, colors, color);
				int i110 = addVertex(vertices, x + offset, y + offset, z, colors, color);
				int i111 = addVertex(vertices, x + offset, y + offset, z + offset, colors, color);
				addNormals(normals, 1, 0, 0, 4);
				faces.add(i100);
				faces.add(i111);
				faces.add(i101);

				faces.add(i100);
				faces.add(i110);
				faces.add(i111);
			}
			if(negY) {
				int i000 = addVertex(vertices, x, y, z, colors, color);
				int i001 = addVertex(vertices, x, y, z + offset, colors, color);
				int i100 = addVertex(vertices, x + offset, y, z, colors, color);
				int i101 = addVertex(vertices, x + offset, y, z + offset, colors, color);
				addNormals(normals, 0, -1, 0, 4);
				faces.add(i000);
				faces.add(i101);
				faces.add(i001);

				faces.add(i000);
				faces.add(i100);
				faces.add(i101);
			}
			if(posY) {
				int i010 = addVertex(vertices, x, y + offset, z, colors, color);
				int i011 = addVertex(vertices, x, y + offset, z + offset, colors, color);
				int i110 = addVertex(vertices, x + offset, y + offset, z, colors, color);
				int i111 = addVertex(vertices, x + offset, y + offset, z + offset, colors, color);
				addNormals(normals, 0, 1, 0, 4);
				faces.add(i010);
				faces.add(i011);
				faces.add(i111);

				faces.add(i010);
				faces.add(i111);
				faces.add(i110);
			}
			if(negZ) {
				int i000 = addVertex(vertices, x, y, z, colors, color);
				int i010 = addVertex(vertices, x, y + offset, z, colors, color);
				int i100 = addVertex(vertices, x + offset, y, z, colors, color);
				int i110 = addVertex(vertices, x + offset, y + offset, z, colors, color);
				addNormals(normals, 0, 0, -1, 4);
				faces.add(i000);
				faces.add(i110);
				faces.add(i100);

				faces.add(i000);
				faces.add(i010);
				faces.add(i110);
			}
			if(posZ) {
				int i001 = addVertex(vertices, x, y, z + offset, colors, color);
				int i011 = addVertex(vertices, x, y + offset, z + offset, colors, color);
				int i101 = addVertex(vertices, x + offset, y, z + offset, colors, color);
				int i111 = addVertex(vertices, x + offset, y + offset, z + offset, colors, color);
				addNormals(normals, 0, 0, 1, 4);
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
