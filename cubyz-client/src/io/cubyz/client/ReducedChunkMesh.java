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

public class ReducedChunkMesh {
	// ThreadLocal lists, to prevent (re-)allocating tons of memory.
	public static ThreadLocal<FloatFastList> localVertices = new ThreadLocal<FloatFastList>() {
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
		IntFastList faces = localFaces.get();
		IntFastList colors = localColors.get();
		vertices.clear();
		faces.clear();
		colors.clear();
		generateModelData(chunk, vertices, faces, colors);
		FloatBuffer posBuffer = null;
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
		// Draw
		glDrawElements(GL_TRIANGLES, vertexCount, GL_UNSIGNED_INT, 0);
		// Restore state
		glDisableVertexAttribArray(0);
		glDisableVertexAttribArray(1);
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
	
	private static void generateModelData(ReducedChunk chunk, FloatFastList vertices, IntFastList faces, IntFastList colors) {
		int zMask = (chunk.width - 1) >>> chunk.resolution;
		int xMask = zMask << (chunk.widthShift - chunk.resolution);
		int yMask = (255 >>> chunk.resolution) << 2*(chunk.widthShift - chunk.resolution);
		int zDelta = 1;
		int xDelta = 1 << (chunk.widthShift - chunk.resolution);
		int yDelta = 1 << 2*(chunk.widthShift - chunk.resolution);
		int offset = 1 << chunk.resolution;
		// Go through all blocks and check their neighbors:
		for(int i = 0; i < chunk.size; i++) {
			int x = CubyzMath.shiftRight(i & xMask, chunk.widthShift - 2*chunk.resolution);
			int y = CubyzMath.shiftRight(i & yMask, 2*chunk.widthShift - 3*chunk.resolution);
			int z = (i & zMask) << chunk.resolution;
			if(chunk.blocks[i] == 0) continue;
			boolean posX = true, negX = true, posY = true, negY = true, posZ = true, negZ = true;
			if((i & xMask) != 0 && chunk.blocks[i - xDelta] != 0) negX = false;
			if((i & xMask) != xMask && chunk.blocks[i + xDelta] != 0) posX = false;
			if((i & yMask) == 0 || chunk.blocks[i - yDelta] != 0) negY = false; // Never draw the bedrock face of a chunk.
			if((i & yMask) != yMask && chunk.blocks[i + yDelta] != 0) posY = false;
			if((i & zMask) != 0 && chunk.blocks[i - zDelta] != 0) negZ = false;
			if((i & zMask) != zMask && chunk.blocks[i + zDelta] != 0) posZ = false;
			if(posX || negX || posY || negY || posZ || negZ) {
				int color = chunk.blocks[i] & 65535;
				// Determine the coordinates from index:
				x += chunk.cx << 4;
				z += chunk.cz << 4;
				// TODO: Optimize duplicate vertices where two cubes of same color touch.
				// Activate the vertices used and link their indices:
				int i000 = 0;
				if(negX | negY | negZ) {
					i000 = vertices.size/3;
					vertices.add(x - 0.5f);
					vertices.add(y - 0.5f);
					vertices.add(z - 0.5f);
					colors.add(color);
				}
				int i001 = 0;
				if(negX | negY | posZ) {
					i001 = vertices.size/3;
					vertices.add(x - 0.5f);
					vertices.add(y - 0.5f);
					vertices.add(z + offset - 0.5f);
					colors.add(color);
				}
				int i010 = 0;
				if(negX | posY | negZ) {
					i010 = vertices.size/3;
					vertices.add(x - 0.5f);
					vertices.add(y + offset - 0.5f);
					vertices.add(z - 0.5f);
					colors.add(color);
				}
				int i011 = 0;
				if(negX | posY | posZ) {
					i011 = vertices.size/3;
					vertices.add(x - 0.5f);
					vertices.add(y + offset - 0.5f);
					vertices.add(z + offset - 0.5f);
					colors.add(color);
				}
				int i100 = 0;
				if(posX | negY | negZ) {
					i100 = vertices.size/3;
					vertices.add(x + offset - 0.5f);
					vertices.add(y - 0.5f);
					vertices.add(z - 0.5f);
					colors.add(color);
				}
				int i101 = 0;
				if(posX | negY | posZ) {
					i101 = vertices.size/3;
					vertices.add(x + offset - 0.5f);
					vertices.add(y - 0.5f);
					vertices.add(z + offset - 0.5f);
					colors.add(color);
				}
				int i110 = 0;
				if(posX | posY | negZ) {
					i110 = vertices.size/3;
					vertices.add(x + offset - 0.5f);
					vertices.add(y + offset - 0.5f);
					vertices.add(z - 0.5f);
					colors.add(color);
				}
				int i111 = 0;
				if(posX | posY | posZ) {
					i111 = vertices.size/3;
					vertices.add(x + offset - 0.5f);
					vertices.add(y + offset - 0.5f);
					vertices.add(z + offset - 0.5f);
					colors.add(color);
				}
				// Add the faces:
				if(negX) {
					faces.add(i000);
					faces.add(i001);
					faces.add(i011);

					faces.add(i000);
					faces.add(i011);
					faces.add(i010);
				}
				if(posX) {
					faces.add(i100);
					faces.add(i111);
					faces.add(i101);

					faces.add(i100);
					faces.add(i110);
					faces.add(i111);
				}
				if(negY) {
					faces.add(i000);
					faces.add(i101);
					faces.add(i001);

					faces.add(i000);
					faces.add(i100);
					faces.add(i101);
				}
				if(posY) {
					faces.add(i010);
					faces.add(i011);
					faces.add(i111);

					faces.add(i010);
					faces.add(i111);
					faces.add(i110);
				}
				if(negZ) {
					faces.add(i000);
					faces.add(i110);
					faces.add(i100);

					faces.add(i000);
					faces.add(i010);
					faces.add(i110);
				}
				if(posZ) {
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
}
