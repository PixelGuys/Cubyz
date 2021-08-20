package cubyz.rendering;

import static org.lwjgl.opengl.GL30.*;

import org.lwjgl.system.MemoryUtil;

public class FrameBuffer {
	
	protected int id;
	protected Texture texture;
	protected Texture depthTexture;
	protected int renderBuffer = -1;
	
	public FrameBuffer() {
		create();
	}
	
	public void genRenderbuffer(int width, int height) {
		glBindFramebuffer(GL_FRAMEBUFFER, id);
		if (renderBuffer != -1) {
			glDeleteRenderbuffers(renderBuffer);
		}
		renderBuffer = glGenRenderbuffers();
		glBindRenderbuffer(GL_RENDERBUFFER, renderBuffer);
		glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, width, height);
		glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT,
				GL_RENDERBUFFER, renderBuffer);
	}
	
	public void genDepthTexture(int width, int height) {
		glBindFramebuffer(GL_FRAMEBUFFER, id);
		if (depthTexture != null) {
			depthTexture.cleanup();
		}
		depthTexture = new Texture(width, height, GL_DEPTH_COMPONENT);
		
		// disable color buffer
		glDrawBuffer(GL_NONE);
		glReadBuffer(GL_NONE);
		glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, depthTexture.getId(), 0);
	}
	
	public void genColorTexture(int width, int height) {
		glBindFramebuffer(GL_FRAMEBUFFER, id);
		if (texture != null) {
			texture.cleanup();
		}
		int tId = glGenTextures();
		glBindTexture(GL_TEXTURE_2D, tId);
		glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0,
				GL_RGBA, GL_UNSIGNED_BYTE, MemoryUtil.NULL);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
		glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tId, 0);
		texture = new Texture(tId);
		texture.width = width; texture.height = height;
	}
	
	public Texture getColorTexture() {
		return texture;
	}
	
	public Texture getDepthTexture() {
		return depthTexture;
	}
	
	public void create() {
		id = glGenFramebuffers();
		glBindFramebuffer(GL_FRAMEBUFFER, id);
	}
	
	public void validate() throws FrameBufferException {
		glBindFramebuffer(GL_FRAMEBUFFER, id);
		if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
			glBindFramebuffer(GL_FRAMEBUFFER, 0);
			throw new FrameBufferException("Frame Buffer Object error: " + glCheckFramebufferStatus(GL_FRAMEBUFFER));
		}
		glBindFramebuffer(GL_FRAMEBUFFER, 0);
	}
	
	public void bind() {
		glBindFramebuffer(GL_FRAMEBUFFER, id);
	}
	
	public void unbind() {
		glBindFramebuffer(GL_FRAMEBUFFER, 0);
	}
	
	public void cleanup() {
		glDeleteFramebuffers(id);
		id = -1;
	}

	public static class FrameBufferException extends Exception {
		private static final long serialVersionUID = 1L;

		public FrameBufferException(String s) { super(s); }
		
	}
	
}
