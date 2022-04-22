package cubyz.rendering;

import static org.lwjgl.opengl.GL30.*;

import cubyz.utils.Logger;
import org.lwjgl.system.MemoryUtil;

public class FrameBuffer {
	
	protected final int id;
	private boolean wasDeleted = false;
	private boolean responsibleOfColorTexture = true;
	protected Texture texture;
	protected int renderBuffer = -1;
	
	public FrameBuffer() {
		id = glGenFramebuffers();
	}
	
	public void genRenderBuffer(int width, int height) {
		assert !wasDeleted : "Frame buffer was already deleted!";
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
	
	public void genColorTexture(int width, int height, int filter, int wrap) {
		assert !wasDeleted : "Frame buffer was already deleted!";
		glBindFramebuffer(GL_FRAMEBUFFER, id);
		if (texture != null) {
			texture.delete();
		}
		texture = new Texture();
		int tId = texture.getId();
		glBindTexture(GL_TEXTURE_2D, tId);
		glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, width, height, 0,
				GL_RGBA, GL_UNSIGNED_BYTE, MemoryUtil.NULL);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, filter);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, filter);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, wrap);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, wrap);
		glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tId, 0);
		texture.width = width;
		texture.height = height;
	}
	
	public Texture getColorTextureAndTakeResponsibilityToDeleteIt() {
		responsibleOfColorTexture = false;
		return texture;
	}
	
	public boolean validate() {
		assert !wasDeleted : "Frame buffer was already deleted!";
		glBindFramebuffer(GL_FRAMEBUFFER, id);
		if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
			Logger.error("Frame Buffer Object error: " + glCheckFramebufferStatus(GL_FRAMEBUFFER));
			glBindFramebuffer(GL_FRAMEBUFFER, 0);
			return false;
		}
		glBindFramebuffer(GL_FRAMEBUFFER, 0);
		return true;
	}
	
	public void bind() {
		assert !wasDeleted : "Frame buffer was already deleted!";
		glBindFramebuffer(GL_FRAMEBUFFER, id);
	}
	
	public void unbind() {
		glBindFramebuffer(GL_FRAMEBUFFER, 0);
	}
	
	public void delete() {
		if(!wasDeleted) {
			glDeleteFramebuffers(id);
			glDeleteRenderbuffers(renderBuffer);
			if(responsibleOfColorTexture) {
				texture.delete();
			}
			wasDeleted = true;
		}
	}

	@Override
	protected void finalize() {
		if(!wasDeleted) {
			Logger.error("Frame Buffer leaked!");
		}
	}
}
