package cubyz.rendering;

import java.util.ArrayList;
import java.util.List;
import java.util.function.Consumer;

import static org.lwjgl.opengl.GL43.*;

import cubyz.rendering.models.Model;
import cubyz.utils.datastructures.SimpleList;

public class Mesh implements Cloneable {

	protected final int vaoId;

	protected final List<Integer> vboIdList;

	protected final int vertexCount;

	protected Texture texture;
	
	public final Model model;

	public Mesh(Model model) {
		this.model = model;

		vertexCount = model.indices.length;
		vboIdList = new ArrayList<>();

		vaoId = glGenVertexArrays();
		glBindVertexArray(vaoId);
		glEnableVertexAttribArray(0);
		glEnableVertexAttribArray(1);
		glEnableVertexAttribArray(2);

		// Position VBO
		int vboId = glGenBuffers();
		vboIdList.add(vboId);
		glBindBuffer(GL_ARRAY_BUFFER, vboId);
		glBufferData(GL_ARRAY_BUFFER, model.positions, GL_STATIC_DRAW);
		glVertexAttribPointer(0, 3, GL_FLOAT, false, 0, 0);

		// Texture coordinates VBO
		vboId = glGenBuffers();
		vboIdList.add(vboId);
		glBindBuffer(GL_ARRAY_BUFFER, vboId);
		glBufferData(GL_ARRAY_BUFFER, model.textCoords, GL_STATIC_DRAW);
		glVertexAttribPointer(1, 2, GL_FLOAT, false, 0, 0);

		// Vertex normals VBO
		vboId = glGenBuffers();
		vboIdList.add(vboId);
		glBindBuffer(GL_ARRAY_BUFFER, vboId);
		glBufferData(GL_ARRAY_BUFFER, model.normals, GL_STATIC_DRAW);
		glVertexAttribPointer(2, 3, GL_FLOAT, false, 0, 0);

		// Index VBO
		vboId = glGenBuffers();
		vboIdList.add(vboId);
		glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, vboId);
		glBufferData(GL_ELEMENT_ARRAY_BUFFER, model.indices, GL_STATIC_DRAW);

		glBindBuffer(GL_ARRAY_BUFFER, 0);
		glBindVertexArray(0);
	}

	protected Mesh(int vao, int count, List<Integer> vboId, Model model) {
		this.model = model;
		vertexCount = count;
		vaoId = vao;
		vboIdList = vboId;
	}

	public Mesh clone() {
		Mesh clone = cloneNoTexture();
		clone.texture = texture;
		return clone;
	}

	/**
	 * Very useful method for meshes with only material (mostly texture) being
	 * different
	 */
	public Mesh cloneNoTexture() {
		return new Mesh(vaoId, vertexCount, vboIdList, model);
	}

	public Texture getTexture() {
		return texture;
	}

	public void setTexture(Texture texture) {
		this.texture = texture;
	}

	protected void initRender() {
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
	
	public void renderList(SimpleList<Spatial> spatials, Consumer<Spatial> consumer) {
		if (spatials.isEmpty())
			return;
		initRender();
		
		for (int i = 0; i < spatials.size; i++) {
			consumer.accept(spatials.array[i]);
			render();
		}

		endRender();
	}
	
	public void renderOne(Runnable run) {
		initRender();
		
		run.run();
		render();

		endRender();
	}

	public void cleanUp() {
		deleteBuffers();

		// Delete the texture
		if (texture != null) {
			texture.delete();
		}
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
