package cubyz.rendering;

import cubyz.utils.datastructures.IntFastList;

import static org.lwjgl.opengl.GL43.*;

public class SSBO {
	private static IntFastList usedBindings = new IntFastList();
	private final int binding;
	private final int bufferID;
	public SSBO(int binding) {
		synchronized(usedBindings) {
			if(usedBindings.contains(binding))
				throw new IllegalArgumentException("Binding "+binding+" is already in use.");
			usedBindings.add(binding);
		}
		this.binding = binding;
		bufferID = glGenBuffers();
	}
	
	public void bufferData(int[] data) {
		glBindBuffer(GL_SHADER_STORAGE_BUFFER, bufferID);
		glBufferData(GL_SHADER_STORAGE_BUFFER, data, GL_STATIC_DRAW);
		glBindBufferBase(GL_SHADER_STORAGE_BUFFER, binding, bufferID);
		glBindBuffer(GL_SHADER_STORAGE_BUFFER, 0);
	}
}
