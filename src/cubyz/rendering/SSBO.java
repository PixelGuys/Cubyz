package cubyz.rendering;

import static org.lwjgl.opengl.GL43.*;

public class SSBO {
	private final int bufferID;
	private boolean wasDeleted = false;
	public SSBO() {
		bufferID = glGenBuffers();
	}

	public void bind(int binding) {
		assert(!wasDeleted) : "The buffer of this SSBO was already deleted.";
		glBindBufferBase(GL_SHADER_STORAGE_BUFFER, binding, bufferID);
	}
	
	public void bufferData(int[] data) {
		assert(!wasDeleted) : "The buffer of this SSBO was already deleted.";
		glBindBuffer(GL_SHADER_STORAGE_BUFFER, bufferID);
		glBufferData(GL_SHADER_STORAGE_BUFFER, data, GL_STATIC_DRAW);
		glBindBuffer(GL_SHADER_STORAGE_BUFFER, 0);
	}

	public void delete() {
		glDeleteBuffers(bufferID);
		wasDeleted = true;
	}

	@Override
	public void finalize() { // TODO: Don't use finalize for that. There is an alternative in modern java.
		assert(wasDeleted) : "Resource leak in ssbo.";
	}
}
