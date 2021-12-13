package cubyz.rendering;

import java.nio.FloatBuffer;
import java.util.List;

import static org.lwjgl.opengl.GL11.*;
import static org.lwjgl.opengl.GL15.*;
import static org.lwjgl.opengl.GL20.*;
import static org.lwjgl.opengl.GL30.*;
import static org.lwjgl.opengl.GL31.*;
import static org.lwjgl.opengl.GL33.*;
import org.lwjgl.system.MemoryUtil;

import cubyz.rendering.models.Model;
import cubyz.utils.datastructures.FastList;

/**
 * Unused for now, but might be reactivated for entities one day.
 */

public class InstancedMesh extends Mesh {

	private static final int FLOAT_SIZE_BYTES = 4;

	private static final int VECTOR4F_SIZE_BYTES = 4 * FLOAT_SIZE_BYTES;

	private static final int REDUCED_MATRIX_SIZE_FLOATS = 3 * 4;
	private static final int REDUCED_MATRIX_SIZE_BYTES = REDUCED_MATRIX_SIZE_FLOATS * FLOAT_SIZE_BYTES;

	private static final int INSTANCE_SIZE_BYTES = REDUCED_MATRIX_SIZE_BYTES + FLOAT_SIZE_BYTES + 8*FLOAT_SIZE_BYTES;

	private static final int INSTANCE_SIZE_FLOATS = REDUCED_MATRIX_SIZE_FLOATS + 1 + 8;

	private int numInstances;

	private final int modelViewVBO;

	private FloatBuffer instanceDataBuffer;

	public boolean isInstanced() {
		return true;
	}
	
	public InstancedMesh(int vao, int count, List<Integer> vaoIds, Model model, int numInstances) {
		super(vao, count, vaoIds, model);
		glBindVertexArray(vaoId);
		modelViewVBO = glGenBuffers();
		initInstances(numInstances);
	}
	
	protected void initInstances(int numInstances) {
		this.numInstances = numInstances;
		vboIdList.add(modelViewVBO);
		instanceDataBuffer = MemoryUtil.memAllocFloat(numInstances * INSTANCE_SIZE_FLOATS);
		glBindBuffer(GL_ARRAY_BUFFER, modelViewVBO);
		int start = 3;
		int strideStart = 0;
		// Model matrix:
		for (int i = 0; i < 4; i++) {
			glVertexAttribPointer(start, 4, GL_FLOAT, false, INSTANCE_SIZE_BYTES, strideStart);
			glVertexAttribDivisor(start, 1);
			start++;
			strideStart += VECTOR4F_SIZE_BYTES;
		}
		// Light Color:
		for(int i = 0; i < 8; i++) {
			glVertexAttribPointer(start, 1, GL_FLOAT, false, INSTANCE_SIZE_BYTES, strideStart);
			glVertexAttribDivisor(start, 1);
			start++;
			strideStart += FLOAT_SIZE_BYTES;
		}
		// Selection/Breaking: 0 = not selected
		glVertexAttribPointer(start, 1, GL_FLOAT, false, INSTANCE_SIZE_BYTES, strideStart);
		glVertexAttribDivisor(start, 1);
		start++;
		strideStart += FLOAT_SIZE_BYTES;

		// Light view matrix
		
		for (int i = 0; i < 4; i++) {
			glVertexAttribPointer(start, 4, GL_FLOAT, false, INSTANCE_SIZE_BYTES, strideStart);
			glVertexAttribDivisor(start, 1);
			start++;
			strideStart += VECTOR4F_SIZE_BYTES;
		}

		glBindBuffer(GL_ARRAY_BUFFER, 0);
		glBindVertexArray(0);
	}
	
	public InstancedMesh(Model model, int numInstances) {
		super(model);
		glBindVertexArray(vaoId);
		modelViewVBO = glGenBuffers();
		initInstances(numInstances);
	}
	
	public void setInstances(int numInst) {
		this.numInstances = numInst;
		glBindVertexArray(vaoId);
		instanceDataBuffer = MemoryUtil.memRealloc(instanceDataBuffer, numInstances * INSTANCE_SIZE_FLOATS);
		glBindBuffer(GL_ARRAY_BUFFER, modelViewVBO);
		int start = 3;
		int strideStart = 0;
		// Model matrix:
		for (int i = 0; i < 3; i++) {
			glVertexAttribPointer(start, 4, GL_FLOAT, false, INSTANCE_SIZE_BYTES, strideStart);
			glVertexAttribDivisor(start, 1);
			start++;
			strideStart += VECTOR4F_SIZE_BYTES;
		}
		// Light Color:
		for(int i = 0; i < 8; i++) {
			glVertexAttribPointer(start, 1, GL_FLOAT, false, INSTANCE_SIZE_BYTES, strideStart);
			glVertexAttribDivisor(start, 1);
			start++;
			strideStart += FLOAT_SIZE_BYTES;
		}
		// Selection:
		glVertexAttribPointer(start, 1, GL_FLOAT, false, INSTANCE_SIZE_BYTES, strideStart);
		glVertexAttribDivisor(start, 1);
		start++;
		strideStart += FLOAT_SIZE_BYTES;

		glBindBuffer(GL_ARRAY_BUFFER, 0);
		glBindVertexArray(0);
	}

	public Mesh cloneNoMaterial() {
		Mesh clone = new InstancedMesh(super.model, 0);
		clone.cullFace = cullFace;
		clone.frustum = frustum;
		return clone;
	}
	
	@Override
	public void cleanUp() {
		super.cleanUp();
		if (this.instanceDataBuffer != null) {
			MemoryUtil.memFree(this.instanceDataBuffer);
			this.instanceDataBuffer = null;
		}
	}

	@Override
	protected void initRender() {
		super.initRender();
		int start = 3;
		int numElements = 4 + 8 + 1;
		for (int i = 0; i < numElements; i++) {
			glEnableVertexAttribArray(start + i);
		}
		glBindBuffer(GL_ARRAY_BUFFER, modelViewVBO);
	}

	@Override
	protected void endRender() {
		int start = 3;
		int numElements = 4 + 8 + 1;
		for (int i = 0; i < numElements; i++) {
			glDisableVertexAttribArray(start + i);
		}
		glBindBuffer(GL_ARRAY_BUFFER, 0);
		super.endRender();
	}

	int oldSize = 0;
	
	/**
	 * Render list instanced in a non-chunked way
	 * @param spatials
	 * @param transformation
	 * @param viewMatrix
	 * @param useTextureAtlas
	 */
	@Deprecated
	public boolean renderListInstancedNC(FastList<Spatial> spatials, Transformation transformation, boolean useTextureAtlas) {
		if (numInstances == 0)
			return false;
		initRender();
		boolean bool = false;
		int curSize = spatials.size;
		if (curSize != oldSize) {
			oldSize = curSize;
			if (numInstances < curSize) {
				setInstances(curSize);
			}
			uploadData(spatials.array, 0, spatials.size, transformation, useTextureAtlas);
			bool = true;
		}
		renderChunkInstanced(spatials.size, transformation);
		
		endRender();
		return bool;
	}

	@Deprecated
	public void renderListInstanced(FastList<Spatial> spatials, Transformation transformation, boolean useTextureAtlas) {
		if (numInstances == 0)
			return;
		initRender();

		int chunkSize = numInstances;
		int length = spatials.size;
		for (int i = 0; i < length; i += chunkSize) {
			int end = Math.min(length, i + chunkSize);
			uploadData(spatials.array, i, end, transformation, useTextureAtlas);
			renderChunkInstanced(end-i, transformation);
		}

		endRender();
	}
	
	@Deprecated
	public void uploadData(Spatial[] spatials, int startIndex, int endIndex, Transformation transformation, boolean useTextureAtlas) {
		/*this.instanceDataBuffer.clear();
		
		int size = endIndex-startIndex;
		for (int i = 0; i < size; i++) {
			Spatial spatial = spatials[i+startIndex];
			Matrix4f modelMatrix = spatial.modelViewMatrix;
			modelMatrix.get4x3Transposed(INSTANCE_SIZE_FLOATS * i, instanceDataBuffer);
			if (modelMatrix.m03() != 0 || modelMatrix.m13() != 0 || modelMatrix.m23() != 0 || modelMatrix.m33() != 1)
			System.out.println(modelMatrix);
			BlockInstance bi = ((BlockSpatial) spatial).getBlockInstance();
			if (bi.getBreakingAnim() == 0f) {
				int breakAnimInfo = (int)(spatial.isSelected() ? 1 : 0) << 24;
				if (useTextureAtlas) {
					breakAnimInfo |= ((BlockSpatial)spatial).getBlockInstance().getBlock().atlasX << 8 | ((BlockSpatial)spatial).getBlockInstance().getBlock().atlasY;
				}
				instanceDataBuffer.put(INSTANCE_SIZE_FLOATS * i + 20, Float.intBitsToFloat(breakAnimInfo));
			} else {
				int breakAnimInfo = (int)(bi.getBreakingAnim()*255) << 24;
				if (useTextureAtlas) {
					breakAnimInfo |= (((BlockSpatial)spatial).getBlockInstance().getBlock().atlasX & 255) << 8 | (((BlockSpatial)spatial).getBlockInstance().getBlock().atlasY & 255);
				}
				instanceDataBuffer.put(INSTANCE_SIZE_FLOATS * i + 20, Float.intBitsToFloat(breakAnimInfo));
			}
			if (ClientSettings.easyLighting) {
				for(int j = 0; j < 8; j++) {
					instanceDataBuffer.put(INSTANCE_SIZE_FLOATS * i + 12 + j, Float.intBitsToFloat(spatial.light[j]));
				}
			} else {
				for(int j = 0; j < 8; j++) {
					instanceDataBuffer.put(INSTANCE_SIZE_FLOATS * i + 12 + j, Float.intBitsToFloat(0x00ffffff));
				}
			}
		}

		glBufferData(GL_ARRAY_BUFFER, instanceDataBuffer, GL_DYNAMIC_DRAW);*/
	}
	
	private void renderChunkInstanced(int size, Transformation transformation) {
		glDrawElementsInstanced(GL_TRIANGLES, vertexCount, GL_UNSIGNED_INT, 0, size);
	}
}
