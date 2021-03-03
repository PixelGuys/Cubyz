package io.cubyz.client;

import static org.lwjgl.opengl.GL11.*;
import static org.lwjgl.opengl.GL15.*;
import static org.lwjgl.opengl.GL20.*;
import static org.lwjgl.opengl.GL30.*;

import java.nio.IntBuffer;
import java.util.ArrayList;

import org.lwjgl.system.MemoryUtil;

import io.cubyz.math.CubyzMath;
import io.cubyz.util.IntFastList;
import io.cubyz.world.ReducedChunk;

/**
 * Used to create chunk meshes for reduced chunks.
 */

public class ReducedChunkMesh {
	// ThreadLocal lists, to prevent (re-)allocating tons of memory.
	public static ThreadLocal<IntFastList> localVerticesAndNormals = new ThreadLocal<IntFastList>() {
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
	public static ThreadLocal<IntFastList> localColors = new ThreadLocal<IntFastList>() {
		@Override
		protected IntFastList initialValue() {
			return new IntFastList(20000);
		}
	};
	
	protected int vaoId;

	protected ArrayList<Integer> vboIdList;

	protected int vertexCount;

	public ReducedChunkMesh(ReducedChunk chunk) {
		IntFastList verticesAndNormals = localVerticesAndNormals.get();
		IntFastList faces = localFaces.get();
		IntFastList colors = localColors.get();
		verticesAndNormals.clear();
		faces.clear();
		colors.clear();
		generateModelData(chunk, verticesAndNormals, faces, colors);
		IntBuffer posAndNormalBuffer = null;
		IntBuffer indexBuffer = null;
		IntBuffer colorBuffer = null;
		try {
			vertexCount = faces.size;
			vboIdList = new ArrayList<>();

			vaoId = glGenVertexArrays();
			glBindVertexArray(vaoId);

			// Position and normal VBO
			int vboId = glGenBuffers();
			vboIdList.add(vboId);
			posAndNormalBuffer = MemoryUtil.memAllocInt(verticesAndNormals.size);
			posAndNormalBuffer.put(verticesAndNormals.toArray()).flip();
			glBindBuffer(GL_ARRAY_BUFFER, vboId);
			glBufferData(GL_ARRAY_BUFFER, posAndNormalBuffer, GL_STATIC_DRAW);
			glVertexAttribPointer(0, 1, GL_FLOAT, false, 0, 0);

			// Color VBO
			vboId = glGenBuffers();
			vboIdList.add(vboId);
			colorBuffer = MemoryUtil.memAllocInt(colors.size);
			colorBuffer.put(colors.toArray()).flip();
			glBindBuffer(GL_ARRAY_BUFFER, vboId);
			glBufferData(GL_ARRAY_BUFFER, colorBuffer, GL_STATIC_DRAW);
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
			if (posAndNormalBuffer != null) {
				MemoryUtil.memFree(posAndNormalBuffer);
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
		// Draw
		glDrawElements(GL_TRIANGLES, vertexCount, GL_UNSIGNED_INT, 0);
		// Restore state
		glDisableVertexAttribArray(0);
		glDisableVertexAttribArray(1);
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
	
	/**
	 * Adds a vertex and color and returns the index.
	 * @param vertices
	 * @param x
	 * @param y
	 * @param z
	 * @return
	 */
	private static int addVertex(IntFastList verticesAndNormals, int x, int y, int z, int normal, IntFastList colors, int color) {
		// Normals are handled the same way neighbors are.
		int value = 0;
		value |= normal;
		value |= (x << 3) | (y << 12) | (z << 21);
		verticesAndNormals.add(value);
		colors.add(color);
		return verticesAndNormals.size - 1;
	}
	
	private static void generateModelData(ReducedChunk chunk, IntFastList verticesAndNormals, IntFastList faces, IntFastList colors) {
		int zMask = (chunk.width - 1) >>> chunk.resolutionShift;
		int xMask = zMask << (chunk.widthShift - chunk.resolutionShift);
		int yMask = xMask << (chunk.widthShift - chunk.resolutionShift);
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
			if((i & yMask) != 0 && chunk.blocks[i - yDelta] != null) negY = false;
			if((i & yMask) != yMask && chunk.blocks[i + yDelta] != null) posY = false;
			if((i & zMask) != 0 && chunk.blocks[i - zDelta] != null) negZ = false;
			if((i & zMask) != zMask && chunk.blocks[i + zDelta] != null) posZ = false;
			int x = CubyzMath.shiftRight(i & xMask, chunk.widthShift - 2*chunk.resolutionShift);
			int y = CubyzMath.shiftRight(i & yMask, 2*chunk.widthShift - 3*chunk.resolutionShift);
			int z = ((i & zMask) << chunk.resolutionShift);
			int color = chunk.blocks[i].color & 65535;
			if(negX) {
				int normal = 0;
				int i000 = addVertex(verticesAndNormals, x, y, z, normal, colors, color);
				int i001 = addVertex(verticesAndNormals, x, y, z + offset, normal, colors, color);
				int i010 = addVertex(verticesAndNormals, x, y + offset, z, normal, colors, color);
				int i011 = addVertex(verticesAndNormals, x, y + offset, z + offset, normal, colors, color);
				faces.add(i000);
				faces.add(i001);
				faces.add(i011);

				faces.add(i000);
				faces.add(i011);
				faces.add(i010);
			}
			if(posX) {
				int normal = 1;
				int i100 = addVertex(verticesAndNormals, x + offset, y, z, normal, colors, color);
				int i101 = addVertex(verticesAndNormals, x + offset, y, z + offset, normal, colors, color);
				int i110 = addVertex(verticesAndNormals, x + offset, y + offset, z, normal, colors, color);
				int i111 = addVertex(verticesAndNormals, x + offset, y + offset, z + offset, normal, colors, color);
				faces.add(i100);
				faces.add(i111);
				faces.add(i101);

				faces.add(i100);
				faces.add(i110);
				faces.add(i111);
			}
			if(negY) {
				int normal = 4;
				int i000 = addVertex(verticesAndNormals, x, y, z, normal, colors, color);
				int i001 = addVertex(verticesAndNormals, x, y, z + offset, normal, colors, color);
				int i100 = addVertex(verticesAndNormals, x + offset, y, z, normal, colors, color);
				int i101 = addVertex(verticesAndNormals, x + offset, y, z + offset, normal, colors, color);
				faces.add(i000);
				faces.add(i101);
				faces.add(i001);

				faces.add(i000);
				faces.add(i100);
				faces.add(i101);
			}
			if(posY) {
				int normal = 5;
				int i010 = addVertex(verticesAndNormals, x, y + offset, z, normal, colors, color);
				int i011 = addVertex(verticesAndNormals, x, y + offset, z + offset, normal, colors, color);
				int i110 = addVertex(verticesAndNormals, x + offset, y + offset, z, normal, colors, color);
				int i111 = addVertex(verticesAndNormals, x + offset, y + offset, z + offset, normal, colors, color);
				faces.add(i010);
				faces.add(i011);
				faces.add(i111);

				faces.add(i010);
				faces.add(i111);
				faces.add(i110);
			}
			if(negZ) {
				int normal = 2;
				int i000 = addVertex(verticesAndNormals, x, y, z, normal, colors, color);
				int i010 = addVertex(verticesAndNormals, x, y + offset, z, normal, colors, color);
				int i100 = addVertex(verticesAndNormals, x + offset, y, z, normal, colors, color);
				int i110 = addVertex(verticesAndNormals, x + offset, y + offset, z, normal, colors, color);
				faces.add(i000);
				faces.add(i110);
				faces.add(i100);

				faces.add(i000);
				faces.add(i010);
				faces.add(i110);
			}
			if(posZ) {
				int normal = 3;
				int i001 = addVertex(verticesAndNormals, x, y, z + offset, normal, colors, color);
				int i011 = addVertex(verticesAndNormals, x, y + offset, z + offset, normal, colors, color);
				int i101 = addVertex(verticesAndNormals, x + offset, y, z + offset, normal, colors, color);
				int i111 = addVertex(verticesAndNormals, x + offset, y + offset, z + offset, normal, colors, color);
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
