package cubyz.rendering;

import java.nio.FloatBuffer;
import java.nio.IntBuffer;
import java.util.ArrayList;
import java.util.List;
import java.util.function.Consumer;

import static org.lwjgl.opengl.GL11.*;
import static org.lwjgl.opengl.GL13.*;
import static org.lwjgl.opengl.GL15.*;
import static org.lwjgl.opengl.GL20.*;
import static org.lwjgl.opengl.GL30.*;

import org.joml.Vector4f;
import org.lwjgl.system.MemoryUtil;

import cubyz.rendering.models.Model;
import cubyz.utils.datastructures.FastList;

public class Mesh implements Cloneable {

	protected final int vaoId;

	protected final List<Integer> vboIdList;

	protected final int vertexCount;

	protected Material material;

	protected boolean frustum = true;
	protected boolean cullFace = true;

	protected boolean hasNormals;
	
	public final Model model;

	public static final Vector4f DEFAULT_COLOR = new Vector4f(0.75f, 0.75f, 0.75f, 1.f);

	public boolean supportsFrustumCulling() {
		return frustum;
	}

	public void setSupportsFrustum(boolean bool) {
		frustum = bool;
	}

	public void setSupportsCullFace(boolean bool) {
		cullFace = bool;
	}
	
	public boolean isInstanced() {
		return false;
	}

	public Mesh(Model model) {
		this.model = model;
		FloatBuffer posBuffer = null;
		FloatBuffer textCoordsBuffer = null;
		FloatBuffer vecNormalsBuffer = null;
		IntBuffer indicesBuffer = null;
		hasNormals = model.normals.length > 0 || true;
		try {
			vertexCount = model.indices.length;
			vboIdList = new ArrayList<>();

			vaoId = glGenVertexArrays();
			glBindVertexArray(vaoId);
			glEnableVertexAttribArray(0);
			glEnableVertexAttribArray(1);
			if (hasNormals)
				glEnableVertexAttribArray(2);

			// Position VBO
			int vboId = glGenBuffers();
			vboIdList.add(vboId);
			posBuffer = MemoryUtil.memAllocFloat(model.positions.length);
			posBuffer.put(model.positions).flip();
			glBindBuffer(GL_ARRAY_BUFFER, vboId);
			glBufferData(GL_ARRAY_BUFFER, posBuffer, GL_STATIC_DRAW);
			glVertexAttribPointer(0, 3, GL_FLOAT, false, 0, 0);

			// Texture coordinates VBO
			vboId = glGenBuffers();
			vboIdList.add(vboId);
			textCoordsBuffer = MemoryUtil.memAllocFloat(model.textCoords.length);
			textCoordsBuffer.put(model.textCoords).flip();
			glBindBuffer(GL_ARRAY_BUFFER, vboId);
			glBufferData(GL_ARRAY_BUFFER, textCoordsBuffer, GL_STATIC_DRAW);
			glVertexAttribPointer(1, 2, GL_FLOAT, false, 0, 0);

			// Vertex normals VBO
			vboId = glGenBuffers();
			vboIdList.add(vboId);
			vecNormalsBuffer = MemoryUtil.memAllocFloat(model.normals.length);
			vecNormalsBuffer.put(model.normals).flip();
			glBindBuffer(GL_ARRAY_BUFFER, vboId);
			glBufferData(GL_ARRAY_BUFFER, vecNormalsBuffer, GL_STATIC_DRAW);
			glVertexAttribPointer(2, 3, GL_FLOAT, false, 0, 0);

			// Index VBO
			vboId = glGenBuffers();
			vboIdList.add(vboId);
			indicesBuffer = MemoryUtil.memAllocInt(model.indices.length);
			indicesBuffer.put(model.indices).flip();
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

	protected Mesh(int vao, int count, List<Integer> vboId, Model model) {
		this.model = model;
		vertexCount = count;
		vaoId = vao;
		vboIdList = vboId;
	}

	public Mesh clone() {
		Mesh clone = cloneNoMaterial();
		clone.material = material;
		return clone;
	}

	/**
	 * Very useful method for meshes with only material (mostly texture) being
	 * different
	 */
	public Mesh cloneNoMaterial() {
		Mesh clone = new Mesh(vaoId, vertexCount, vboIdList, model);
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

	protected void initRender() {
		Texture texture = material.getTexture();
		if (texture != null) {
			// Activate first texture bank
			glActiveTexture(GL_TEXTURE0);
			// Bind the texture
			glBindTexture(GL_TEXTURE_2D, texture.getId());
		}

		// Draw the mesh
		glBindVertexArray(vaoId);
	}

	protected void endRender() {
		glBindVertexArray(0);

		glBindTexture(GL_TEXTURE_2D, 0);
	}

	public void render() {
		glDrawElements(GL_TRIANGLES, vertexCount, GL_UNSIGNED_INT, 0);
	}
	
	public void renderList(FastList<Spatial> spatials, Consumer<Spatial> consumer) {
		if (spatials.isEmpty())
			return;
		initRender();
		boolean wasEnabled = false; // avoid having a GPU call (glIsEnabled) if useless later (not having
		// cull face is optional)
		if (!cullFace) {
			wasEnabled = glIsEnabled(GL_CULL_FACE);
			if (wasEnabled) {
				glDisable(GL_CULL_FACE);
			}
		}
		
		for (int i = 0; i < spatials.size; i++) {
			consumer.accept(spatials.array[i]);
			render();
		}
		
		if (wasEnabled) {
			glEnable(GL_CULL_FACE);
		}
		endRender();
	}
	
	public void renderOne(Runnable run) {
		initRender();
		boolean wasEnabled = false; // avoid having a GPU call (glIsEnabled) if useless later (not having
		// cull face is optional)
		if (!cullFace) {
			wasEnabled = glIsEnabled(GL_CULL_FACE);
			if (wasEnabled) {
				glDisable(GL_CULL_FACE);
			}
		}
		
		run.run();
		render();
		
		if (wasEnabled) {
			glEnable(GL_CULL_FACE);
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
