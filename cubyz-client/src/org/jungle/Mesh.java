package org.jungle;

import java.nio.FloatBuffer;
import java.nio.IntBuffer;
import java.util.ArrayList;
import java.util.List;
import java.util.function.Function;

import static org.lwjgl.opengl.GL11.*;
import static org.lwjgl.opengl.GL13.*;
import static org.lwjgl.opengl.GL15.*;
import static org.lwjgl.opengl.GL20.*;
import static org.lwjgl.opengl.GL30.*;

import org.joml.Vector4f;
import org.jungle.util.Material;
import org.lwjgl.system.MemoryUtil;

public class Mesh implements Cloneable {

	private final int vaoId;

	private final List<Integer> vboIdList;

	private final int vertexCount;

	private Material material;

	private float boundingRadius = 1.25f;

	private boolean frustum = true;
	private boolean cullFace = true;

	private boolean hasNormals;

	public static final Vector4f DEFAULT_COLOR = new Vector4f(0.75f, 0.75f, 0.75f, 1.f);

	public float getBoundingRadius() {
		return boundingRadius;
	}

	public boolean supportsFrustumCulling() {
		return frustum;
	}

	public void setSupportsFrustum(boolean bool) {
		frustum = bool;
	}

	public boolean supportsCullFace() {
		return cullFace;
	}

	public void setSupportsCullFace(boolean bool) {
		cullFace = bool;
	}

	public void setBoundingRadius(float boundingRadius) {
		this.boundingRadius = boundingRadius;
	}

	public Mesh(float[] positions, float[] textCoords, float[] normals, int[] indices) {
		FloatBuffer posBuffer = null;
		FloatBuffer textCoordsBuffer = null;
		FloatBuffer vecNormalsBuffer = null;
		IntBuffer indicesBuffer = null;
		hasNormals = normals.length > 0 || true;
		try {
			vertexCount = indices.length;
			vboIdList = new ArrayList<>();

			vaoId = glGenVertexArrays();
			glBindVertexArray(vaoId);

			// Position VBO
			int vboId = glGenBuffers();
			vboIdList.add(vboId);
			posBuffer = MemoryUtil.memAllocFloat(positions.length);
			posBuffer.put(positions).flip();
			glBindBuffer(GL_ARRAY_BUFFER, vboId);
			glBufferData(GL_ARRAY_BUFFER, posBuffer, GL_STATIC_DRAW);
			glVertexAttribPointer(0, 3, GL_FLOAT, false, 0, 0);

			// Texture coordinates VBO
			vboId = glGenBuffers();
			vboIdList.add(vboId);
			textCoordsBuffer = MemoryUtil.memAllocFloat(textCoords.length);
			textCoordsBuffer.put(textCoords).flip();
			glBindBuffer(GL_ARRAY_BUFFER, vboId);
			glBufferData(GL_ARRAY_BUFFER, textCoordsBuffer, GL_STATIC_DRAW);
			glVertexAttribPointer(1, 2, GL_FLOAT, false, 0, 0);

			// Vertex normals VBO
			vboId = glGenBuffers();
			vboIdList.add(vboId);
			vecNormalsBuffer = MemoryUtil.memAllocFloat(normals.length);
			vecNormalsBuffer.put(normals).flip();
			glBindBuffer(GL_ARRAY_BUFFER, vboId);
			glBufferData(GL_ARRAY_BUFFER, vecNormalsBuffer, GL_STATIC_DRAW);
			glVertexAttribPointer(2, 3, GL_FLOAT, false, 0, 0);

			// Index VBO
			vboId = glGenBuffers();
			vboIdList.add(vboId);
			indicesBuffer = MemoryUtil.memAllocInt(indices.length);
			indicesBuffer.put(indices).flip();
			glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, vboId);
			glBufferData(GL_ELEMENT_ARRAY_BUFFER, indicesBuffer, GL_STATIC_DRAW);

			glBindBuffer(GL_ARRAY_BUFFER, 0);
			glBindVertexArray(0);
		} finally {
			if (posBuffer != null) {
				MemoryUtil.memFree(posBuffer);
			}
			if (textCoordsBuffer != null) {
				MemoryUtil.memFree(textCoordsBuffer);
			}
			if (vecNormalsBuffer != null) {
				MemoryUtil.memFree(vecNormalsBuffer);
			}
			if (indicesBuffer != null) {
				MemoryUtil.memFree(indicesBuffer);
			}
		}
	}

	private Mesh(int vao, int count, List<Integer> vboId) {
		vertexCount = count;
		vaoId = vao;
		vboIdList = vboId;
	}

	public Mesh clone() {
		Mesh clone = new Mesh(vaoId, vertexCount, vboIdList);
		clone.boundingRadius = boundingRadius;
		clone.cullFace = cullFace;
		clone.frustum = frustum;
		clone.material = material;
		return clone;
	}

	/**
	 * Very useful method for meshes with only material (mostly texture) being
	 * different
	 */
	public Mesh cloneNoMaterial() {
		Mesh clone = new Mesh(vaoId, vertexCount, vboIdList);
		clone.boundingRadius = boundingRadius;
		clone.cullFace = cullFace;
		clone.frustum = frustum;
		return clone;
	}

	public Material getMaterial() {
		return material;
	}

	public void setMaterial(Material material) {
		this.material = material;
	}

	public int getVaoId() {
		return vaoId;
	}

	public int getVertexCount() {
		return vertexCount;
	}

	private void initRender() {
		Texture texture = material.getTexture();
		if (texture != null) {
			// Activate first texture bank
			glActiveTexture(GL_TEXTURE0);
			// Bind the texture
			glBindTexture(GL_TEXTURE_2D, texture.getId());
		}

		// Draw the mesh
		glBindVertexArray(getVaoId());
		glEnableVertexAttribArray(0);
		glEnableVertexAttribArray(1);
		if (hasNormals)
			glEnableVertexAttribArray(2);
	}

	private void endRender() {
		// Restore state
		glDisableVertexAttribArray(0);
		glDisableVertexAttribArray(1);
		if (hasNormals)
			glDisableVertexAttribArray(2);
		glBindVertexArray(0);

		glBindTexture(GL_TEXTURE_2D, 0);
	}

	public void render() {
		boolean wasEnabled = true; // avoid having a GPU call (glIsEnabled) if useless later (not having
		// cull face is optional)
		if (!cullFace) {
			wasEnabled = glIsEnabled(GL_CULL_FACE);
			if (wasEnabled) {
				glDisable(GL_CULL_FACE);
			}
		}

		glDrawElements(GL_TRIANGLES, getVertexCount(), GL_UNSIGNED_INT, 0);

		if (!cullFace && wasEnabled) {
			glEnable(GL_CULL_FACE);
		}
	}
	public void renderList(List<Spatial> spatials, Function<Spatial, Boolean> consumer) {
		if (spatials.isEmpty())
			return;
		initRender();

		//Spatial[] spatialArray = spatials.toArray(new Spatial[spatials.size()]);
		for (int i = 0; i < spatials.size(); i++) {
			boolean render = consumer.apply(spatials.get(i));
			if (render) {
				render();
			}
		}
		
		endRender();
	}

	public void cleanUp() {
		glDisableVertexAttribArray(0);

		// Delete the VBOs
		glBindBuffer(GL_ARRAY_BUFFER, 0);
		for (int vboId : vboIdList) {
			glDeleteBuffers(vboId);
		}

		// Delete the texture
		Texture texture = material.getTexture();
		if (texture != null) {
			texture.cleanup();
		}

		// Delete the VAO
		glBindVertexArray(0);
		glDeleteVertexArrays(vaoId);
	}

	public void deleteBuffers() {
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
}
