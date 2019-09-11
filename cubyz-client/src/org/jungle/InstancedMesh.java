package org.jungle;

import java.nio.FloatBuffer;
import java.util.List;
import org.joml.Matrix4f;
import org.jungle.renderers.Transformation;

import static org.lwjgl.opengl.GL11.*;
import static org.lwjgl.opengl.GL15.*;
import static org.lwjgl.opengl.GL20.*;
import static org.lwjgl.opengl.GL30.*;
import static org.lwjgl.opengl.GL31.*;
import static org.lwjgl.opengl.GL33.*;
import org.lwjgl.system.MemoryUtil;

public class InstancedMesh extends Mesh {

	private static final int FLOAT_SIZE_BYTES = 4;

	private static final int VECTOR4F_SIZE_BYTES = 4 * FLOAT_SIZE_BYTES;

	private static final int MATRIX_SIZE_FLOATS = 4 * 4;

	private static final int MATRIX_SIZE_BYTES = MATRIX_SIZE_FLOATS * FLOAT_SIZE_BYTES;

	private static final int INSTANCE_SIZE_BYTES = MATRIX_SIZE_BYTES * 2 + FLOAT_SIZE_BYTES * 2;

	private static final int INSTANCE_SIZE_FLOATS = MATRIX_SIZE_FLOATS * 2 + 2;

	private int numInstances;

	private final int modelViewVBO;

	private FloatBuffer instanceDataBuffer;

	public boolean isInstanced() {
		return true;
	}
	
	public InstancedMesh(float[] positions, float[] textCoords, float[] normals, int[] indices, int numInstances) {
		super(positions, textCoords, normals, indices);

		this.numInstances = numInstances;

		glBindVertexArray(vaoId);

		// Model View Matrix
		modelViewVBO = glGenBuffers();
		vboIdList.add(modelViewVBO);
		instanceDataBuffer = MemoryUtil.memAllocFloat(numInstances * INSTANCE_SIZE_FLOATS);
		glBindBuffer(GL_ARRAY_BUFFER, modelViewVBO);
		int start = 5;
		int strideStart = 0;
		for (int i = 0; i < 4; i++) {
			glVertexAttribPointer(start, 4, GL_FLOAT, false, INSTANCE_SIZE_BYTES, strideStart);
			glVertexAttribDivisor(start, 1);
			start++;
			strideStart += VECTOR4F_SIZE_BYTES;
		}

		// Light view matrix
		for (int i = 0; i < 4; i++) {
			glVertexAttribPointer(start, 4, GL_FLOAT, false, INSTANCE_SIZE_BYTES, strideStart);
			glVertexAttribDivisor(start, 1);
			start++;
			strideStart += VECTOR4F_SIZE_BYTES;
		}

		// Texture offsets
		glVertexAttribPointer(start, 2, GL_FLOAT, false, INSTANCE_SIZE_BYTES, strideStart);
		glVertexAttribDivisor(start, 1);

		glBindBuffer(GL_ARRAY_BUFFER, 0);
		glBindVertexArray(0);
	}
	
	public void setInstances(int numInst) {
		// XXX: maybe find a way to expand the buffer instdead of recreating it.
		// and shrink it if lowering down
		this.numInstances = numInst;
		glBindVertexArray(vaoId);
		instanceDataBuffer = MemoryUtil.memRealloc(instanceDataBuffer, numInstances * INSTANCE_SIZE_FLOATS);
		glBindBuffer(GL_ARRAY_BUFFER, modelViewVBO);
		int start = 5;
		int strideStart = 0;
		for (int i = 0; i < 4; i++) {
			glVertexAttribPointer(start, 4, GL_FLOAT, false, INSTANCE_SIZE_BYTES, strideStart);
			glVertexAttribDivisor(start, 1);
			start++;
			strideStart += VECTOR4F_SIZE_BYTES;
		}

		// Light view matrix
		for (int i = 0; i < 4; i++) {
			glVertexAttribPointer(start, 4, GL_FLOAT, false, INSTANCE_SIZE_BYTES, strideStart);
			glVertexAttribDivisor(start, 1);
			start++;
			strideStart += VECTOR4F_SIZE_BYTES;
		}

		// Texture offsets
		glVertexAttribPointer(start, 2, GL_FLOAT, false, INSTANCE_SIZE_BYTES, strideStart);
		glVertexAttribDivisor(start, 1);

		glBindBuffer(GL_ARRAY_BUFFER, 0);
		glBindVertexArray(0);
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

		int start = 5;
		int numElements = 4 * 2 + 1;
		for (int i = 0; i < numElements; i++) {
			glEnableVertexAttribArray(start + i);
		}
	}

	@Override
	protected void endRender() {
		int start = 5;
		int numElements = 4 * 2 + 1;
		for (int i = 0; i < numElements; i++) {
			glDisableVertexAttribArray(start + i);
		}

		super.endRender();
	}

	public void renderListInstanced(List<Spatial> gameItems, Transformation transformation, Matrix4f viewMatrix,
			Matrix4f lightViewMatrix) {
		renderListInstanced(gameItems, false, transformation, viewMatrix, lightViewMatrix);
	}

	public void renderListInstanced(List<Spatial> gameItems, boolean billBoard, Transformation transformation,
			Matrix4f viewMatrix, Matrix4f lightViewMatrix) {
		initRender();

		int chunkSize = numInstances;
		int length = gameItems.size();
		for (int i = 0; i < length; i += chunkSize) {
			int end = Math.min(length, i + chunkSize);
			List<Spatial> subList = gameItems.subList(i, end);
			renderChunkInstanced(subList, billBoard, transformation, viewMatrix, lightViewMatrix);
		}

		endRender();
	}

	private void renderChunkInstanced(List<Spatial> gameItems, boolean billBoard, Transformation transformation,
			Matrix4f viewMatrix, Matrix4f lightViewMatrix) {
		this.instanceDataBuffer.clear();

		int i = 0;

		Texture text = getMaterial().getTexture();
		for (Spatial gameItem : gameItems) {
			Matrix4f modelMatrix = transformation.getModelMatrix(gameItem);
			if (viewMatrix != null) {
				if (billBoard) {
					viewMatrix.transpose3x3(modelMatrix);
				}
				Matrix4f modelViewMatrix = transformation.getModelViewMatrix(modelMatrix, viewMatrix);
				if (billBoard) {
					modelViewMatrix.scale(gameItem.getScale());
				}
				modelViewMatrix.get(INSTANCE_SIZE_FLOATS * i, instanceDataBuffer);
			}
			if (lightViewMatrix != null) {
				// Matrix4f modelLightViewMatrix =
				// transformation.buildModelLightViewMatrix(modelMatrix, lightViewMatrix);
				// modelLightViewMatrix.get(INSTANCE_SIZE_FLOATS * i + MATRIX_SIZE_FLOATS,
				// this.instanceDataBuffer);
			}
			if (text != null) {
				/*
				 * int col = gameItem.getTextPos() % text.getNumCols(); int row =
				 * gameItem.getTextPos() / text.getNumCols(); float textXOffset = (float) col /
				 * text.getNumCols(); float textYOffset = (float) row / text.getNumRows(); int
				 * buffPos = INSTANCE_SIZE_FLOATS * i + MATRIX_SIZE_FLOATS * 2;
				 * this.instanceDataBuffer.put(buffPos, textXOffset);
				 * this.instanceDataBuffer.put(buffPos + 1, textYOffset);
				 */
			}

			i++;
		}

		glBindBuffer(GL_ARRAY_BUFFER, modelViewVBO);
		glBufferData(GL_ARRAY_BUFFER, instanceDataBuffer, GL_DYNAMIC_DRAW);

		glDrawElementsInstanced(GL_TRIANGLES, getVertexCount(), GL_UNSIGNED_INT, 0, gameItems.size());

		glBindBuffer(GL_ARRAY_BUFFER, 0);
	}
}
