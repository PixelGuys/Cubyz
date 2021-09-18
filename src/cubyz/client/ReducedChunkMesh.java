package cubyz.client;

import static org.lwjgl.opengl.GL11.*;
import static org.lwjgl.opengl.GL15.*;
import static org.lwjgl.opengl.GL20.*;
import static org.lwjgl.opengl.GL30.*;

import java.nio.IntBuffer;
import java.util.ArrayList;

import org.joml.Vector3f;
import org.lwjgl.system.MemoryUtil;

import cubyz.rendering.Camera;
import cubyz.rendering.ShaderProgram;
import cubyz.rendering.Window;
import cubyz.utils.Utils;
import cubyz.utils.datastructures.IntFastList;
import cubyz.utils.math.CubyzMath;
import cubyz.world.Chunk;
import cubyz.world.Neighbors;
import cubyz.world.NormalChunk;
import cubyz.world.ReducedChunk;
import cubyz.world.blocks.Block;

/**
 * Used to create chunk meshes for reduced chunks.
 */

public class ReducedChunkMesh extends ChunkMesh implements Runnable {
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

	public static ShaderProgram shader;
	
	public static void init(String shaderFolder) throws Exception {
		shader = new ShaderProgram(Utils.loadResource(shaderFolder + "/chunk_vertex.vs"),
				Utils.loadResource(shaderFolder + "/chunk_fragment.fs"),
				ReducedChunkMesh.class);
	}

	/**
	 * Also updates the uniforms.
	 * @param ambient
	 * @param directional
	 */
	public static void bindShader(Vector3f ambient, Vector3f directional) {
		shader.bind();

		shader.setUniform(loc_fog_activ, Cubyz.fog.isActive());
		shader.setUniform(loc_fog_color, Cubyz.fog.getColor());
		shader.setUniform(loc_fog_density, Cubyz.fog.getDensity());
		shader.setUniform(loc_projectionMatrix, Window.getProjectionMatrix());
		
		shader.setUniform(loc_texture_sampler, 0);
		
		shader.setUniform(loc_viewMatrix, Camera.getViewMatrix());

		shader.setUniform(loc_ambientLight, ambient);
		shader.setUniform(loc_directionalLight, directional);
	}
	
	protected int vaoId;

	protected ArrayList<Integer> vboIdList = new ArrayList<>();

	protected int vertexCount;

	private ReducedChunk chunk;

	private boolean needsUpdate = false;

	public ReducedChunkMesh(ReducedChunkMesh replacement, int wx, int wy, int wz, int size) {
		super(replacement, wx, wy, wz, size);
	}

	@Override
	public void run() {
		synchronized(this) {
			if(!needsUpdate && chunk != null && chunk.generated) {
				needsUpdate = true;
				Meshes.queueMesh(this);
			}
		}
	}
	
	@Override
	public void regenerateMesh() {
		cleanUp();
		ReducedChunk chunk;
		synchronized(this) {
			chunk = this.chunk;
			if(!needsUpdate)
				return;
			needsUpdate = false;
			if(chunk == null)
				return;
		}
		generated = true;

		IntFastList vertices = localVertices.get();
		IntFastList faces = localFaces.get();
		IntFastList texCoordsAndNormals = localTexCoordsAndNormals.get();
		vertices.clear();
		faces.clear();
		texCoordsAndNormals.clear();
		generateModelData(chunk, vertices, faces, texCoordsAndNormals);
		IntBuffer posBuffer = null;
		IntBuffer indexBuffer = null;
		IntBuffer colorAndNormalBuffer = null;
		try {
			vertexCount = faces.size;
			if(vertexCount == 0)
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

	public void updateChunk(ReducedChunk chunk) {
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
			glUniform3f(loc_lowerBounds, wx, wy, wz);
			glUniform3f(loc_upperBounds, wx+size, wy+size, wz+size);
			if(replacement != null) {
				replacement.render();
			}
			glUniform3f(loc_lowerBounds, Float.NEGATIVE_INFINITY, Float.NEGATIVE_INFINITY, Float.NEGATIVE_INFINITY);
			glUniform3f(loc_upperBounds, Float.POSITIVE_INFINITY, Float.POSITIVE_INFINITY, Float.POSITIVE_INFINITY);
			return;
		}
		if(vaoId == -1) return;
		glUniform3f(loc_modelPosition, wx, wy, wz);
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
	private static int addVertex(IntFastList vertices, int x, int y, int z, int normal, IntFastList colorsAndNormals, int textureIndex, int coordinate) {
		// Normals are handled the same way neighbors are.
		int vertexValue = x | (y << 10) | (z << 20);
		vertices.add(vertexValue);
		int texCoords = textureIndex | coordinate << 16;
		colorsAndNormals.add(texCoords | (normal << 24));
		return vertices.size - 1;
	}

	private static void generateModelData(ReducedChunk chunk, IntFastList vertices, IntFastList faces, IntFastList colorsAndNormals) {
		int zMask = (chunk.width - 1) >>> chunk.resolutionShift;
		int xMask = zMask << (chunk.widthShift - chunk.resolutionShift);
		int yMask = xMask << (chunk.widthShift - chunk.resolutionShift);
		// Position of the center blocks:
		int zHalfLower = zMask >>> 1;
		int zHalfUpper = zHalfLower + 1;
		int xHalfLower = zHalfLower << (chunk.widthShift - chunk.resolutionShift);
		int xHalfUpper = zHalfUpper << (chunk.widthShift - chunk.resolutionShift);
		int yHalfLower = xHalfLower << (chunk.widthShift - chunk.resolutionShift);
		int yHalfUpper = xHalfUpper << (chunk.widthShift - chunk.resolutionShift);

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
			// Check a second neighbor if the chunk is close to a potential border.
			// This prevents cracks in the terrain at lod borders.
			if((i & xMask) == xHalfUpper) {
				negX |= chunk.blocks[i - 2*xDelta] == null
				|| (i & yMask) != yMask && chunk.blocks[i - xDelta + yDelta] == null
				|| (i & yMask) != 0 && chunk.blocks[i - xDelta - yDelta] == null
				|| (i & zMask) != zMask && chunk.blocks[i - xDelta + zDelta] == null
				|| (i & zMask) != 0 && chunk.blocks[i - xDelta - zDelta] == null;
			}
			if((i & xMask) == xHalfLower) {
				posX |= chunk.blocks[i + 2*xDelta] == null
				|| (i & yMask) != yMask && chunk.blocks[i + xDelta + yDelta] == null
				|| (i & yMask) != 0 && chunk.blocks[i + xDelta - yDelta] == null
				|| (i & zMask) != zMask && chunk.blocks[i + xDelta + zDelta] == null
				|| (i & zMask) != 0 && chunk.blocks[i + xDelta - zDelta] == null;
			}
			if((i & yMask) == yHalfUpper) {
				negY |= chunk.blocks[i - 2*yDelta] == null
				|| (i & xMask) != xMask && chunk.blocks[i - yDelta + xDelta] == null
				|| (i & xMask) != 0 && chunk.blocks[i - yDelta - xDelta] == null
				|| (i & zMask) != zMask && chunk.blocks[i - yDelta + zDelta] == null
				|| (i & zMask) != 0 && chunk.blocks[i - yDelta - zDelta] == null;
			}
			if((i & yMask) == yHalfLower) {
				posY |= chunk.blocks[i + 2*yDelta] == null
				|| (i & xMask) != xMask && chunk.blocks[i + yDelta + xDelta] == null
				|| (i & xMask) != 0 && chunk.blocks[i + yDelta - xDelta] == null
				|| (i & zMask) != zMask && chunk.blocks[i + yDelta + zDelta] == null
				|| (i & zMask) != 0 && chunk.blocks[i + yDelta - zDelta] == null;
			}
			if((i & zMask) == zHalfUpper) {
				negZ |= chunk.blocks[i - 2*zDelta] == null
				|| (i & yMask) != yMask && chunk.blocks[i - zDelta + yDelta] == null
				|| (i & yMask) != 0 && chunk.blocks[i - zDelta - yDelta] == null
				|| (i & xMask) != xMask && chunk.blocks[i - zDelta + xDelta] == null
				|| (i & xMask) != 0 && chunk.blocks[i - zDelta - xDelta] == null;
			}
			if((i & zMask) == zHalfLower) {
				posZ |= chunk.blocks[i + 2*zDelta] == null
				|| (i & yMask) != yMask && chunk.blocks[i + zDelta + yDelta] == null
				|| (i & yMask) != 0 && chunk.blocks[i + zDelta - yDelta] == null
				|| (i & xMask) != xMask && chunk.blocks[i + zDelta + xDelta] == null
				|| (i & xMask) != 0 && chunk.blocks[i + zDelta - xDelta] == null;
			}
			int x = CubyzMath.shiftRight(i & xMask, chunk.widthShift - 2*chunk.resolutionShift);
			int y = CubyzMath.shiftRight(i & yMask, 2*chunk.widthShift - 3*chunk.resolutionShift);
			int z = ((i & zMask) << chunk.resolutionShift);
			Block block = chunk.blocks[i];
			if(negX) {
				int normal = 0;
				int i000 = addVertex(vertices, x, y, z, normal, colorsAndNormals, block.textureIndices[Neighbors.DIR_NEG_X], 0b01);
				int i001 = addVertex(vertices, x, y, z + offset, normal, colorsAndNormals, block.textureIndices[Neighbors.DIR_NEG_X], 0b11);
				int i010 = addVertex(vertices, x, y + offset, z, normal, colorsAndNormals, block.textureIndices[Neighbors.DIR_NEG_X], 0b00);
				int i011 = addVertex(vertices, x, y + offset, z + offset, normal, colorsAndNormals, block.textureIndices[Neighbors.DIR_NEG_X], 0b10);
				faces.add(i000);
				faces.add(i001);
				faces.add(i011);

				faces.add(i000);
				faces.add(i011);
				faces.add(i010);
			}
			if(posX) {
				int normal = 1;
				int i100 = addVertex(vertices, x + offset, y, z, normal, colorsAndNormals, block.textureIndices[Neighbors.DIR_POS_X], 0b11);
				int i101 = addVertex(vertices, x + offset, y, z + offset, normal, colorsAndNormals, block.textureIndices[Neighbors.DIR_POS_X], 0b01);
				int i110 = addVertex(vertices, x + offset, y + offset, z, normal, colorsAndNormals, block.textureIndices[Neighbors.DIR_POS_X], 0b10);
				int i111 = addVertex(vertices, x + offset, y + offset, z + offset, normal, colorsAndNormals, block.textureIndices[Neighbors.DIR_POS_X], 0b00);
				faces.add(i100);
				faces.add(i111);
				faces.add(i101);

				faces.add(i100);
				faces.add(i110);
				faces.add(i111);
			}
			if(negY) {
				int normal = 4;
				int i000 = addVertex(vertices, x, y, z, normal, colorsAndNormals, block.textureIndices[Neighbors.DIR_DOWN], 0b11);
				int i001 = addVertex(vertices, x, y, z + offset, normal, colorsAndNormals, block.textureIndices[Neighbors.DIR_DOWN], 0b10);
				int i100 = addVertex(vertices, x + offset, y, z, normal, colorsAndNormals, block.textureIndices[Neighbors.DIR_DOWN], 0b01);
				int i101 = addVertex(vertices, x + offset, y, z + offset, normal, colorsAndNormals, block.textureIndices[Neighbors.DIR_DOWN], 0b00);
				faces.add(i000);
				faces.add(i101);
				faces.add(i001);

				faces.add(i000);
				faces.add(i100);
				faces.add(i101);
			}
			if(posY) {
				int normal = 5;
				int i010 = addVertex(vertices, x, y + offset, z, normal, colorsAndNormals, block.textureIndices[Neighbors.DIR_UP], 0b01);
				int i011 = addVertex(vertices, x, y + offset, z + offset, normal, colorsAndNormals, block.textureIndices[Neighbors.DIR_UP], 0b00);
				int i110 = addVertex(vertices, x + offset, y + offset, z, normal, colorsAndNormals, block.textureIndices[Neighbors.DIR_UP], 0b11);
				int i111 = addVertex(vertices, x + offset, y + offset, z + offset, normal, colorsAndNormals, block.textureIndices[Neighbors.DIR_UP], 0b10);
				faces.add(i010);
				faces.add(i011);
				faces.add(i111);

				faces.add(i010);
				faces.add(i111);
				faces.add(i110);
			}
			if(negZ) {
				int normal = 2;
				int i000 = addVertex(vertices, x, y, z, normal, colorsAndNormals, block.textureIndices[Neighbors.DIR_NEG_Z], 0b11);
				int i010 = addVertex(vertices, x, y + offset, z, normal, colorsAndNormals, block.textureIndices[Neighbors.DIR_NEG_Z], 0b10);
				int i100 = addVertex(vertices, x + offset, y, z, normal, colorsAndNormals, block.textureIndices[Neighbors.DIR_NEG_Z], 0b01);
				int i110 = addVertex(vertices, x + offset, y + offset, z, normal, colorsAndNormals, block.textureIndices[Neighbors.DIR_NEG_Z], 0b00);
				faces.add(i000);
				faces.add(i110);
				faces.add(i100);

				faces.add(i000);
				faces.add(i010);
				faces.add(i110);
			}
			if(posZ) {
				int normal = 3;
				int i001 = addVertex(vertices, x, y, z + offset, normal, colorsAndNormals, block.textureIndices[Neighbors.DIR_POS_Z], 0b01);
				int i011 = addVertex(vertices, x, y + offset, z + offset, normal, colorsAndNormals, block.textureIndices[Neighbors.DIR_POS_Z], 0b00);
				int i101 = addVertex(vertices, x + offset, y, z + offset, normal, colorsAndNormals, block.textureIndices[Neighbors.DIR_POS_Z], 0b11);
				int i111 = addVertex(vertices, x + offset, y + offset, z + offset, normal, colorsAndNormals, block.textureIndices[Neighbors.DIR_POS_Z], 0b10);
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
