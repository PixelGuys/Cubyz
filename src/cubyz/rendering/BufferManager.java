package cubyz.rendering;

import static org.lwjgl.opengl.GL41.*;

import java.nio.ByteBuffer;

import org.joml.Vector4f;

/**
 * Manages the frame buffers that need to be drawn.
 */
public class BufferManager {
	private int buffer;
	private int colorTexture = -1;
	private int positionTexture = -1;
	private int depthBuffer = -1;
	public BufferManager() {
		buffer = glGenFramebuffers();

		depthBuffer = glGenRenderbuffers();

		colorTexture = glGenTextures();

		positionTexture = glGenTextures();

		updateBufferSize(Window.getWidth(), Window.getHeight());

		glBindFramebuffer(GL_FRAMEBUFFER, buffer);

		glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, colorTexture, 0);
		glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT1, GL_TEXTURE_2D, positionTexture, 0);
		
		glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, depthBuffer);
	}

	private void regenTexture(int texture, int internalFormat, int format, int width, int height) {
		glBindTexture(GL_TEXTURE_2D, texture);

		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
		
		glTexImage2D(GL_TEXTURE_2D, 0, internalFormat, width, height, 0, format, GL_UNSIGNED_BYTE, (ByteBuffer) null);

		glBindTexture(GL_TEXTURE_2D, 0);
	}

	public void updateBufferSize(int width, int height) {
		glBindFramebuffer(GL_FRAMEBUFFER, buffer);

		regenTexture(colorTexture, GL_RGBA8, GL_RGBA, width, height);
		regenTexture(positionTexture, GL_RGB16F, GL_RGB, width, height);

		glBindRenderbuffer(GL_RENDERBUFFER, depthBuffer);
		glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, width, height);
		glBindRenderbuffer(GL_RENDERBUFFER, 0);

		glDrawBuffers(new int[]{GL_COLOR_ATTACHMENT0, GL_COLOR_ATTACHMENT1});

		glBindFramebuffer(GL_FRAMEBUFFER, 0);
	}

	public void bindTextures() {
		glActiveTexture(GL_TEXTURE3);
		glBindTexture(GL_TEXTURE_2D, colorTexture);
		glActiveTexture(GL_TEXTURE4);
		glBindTexture(GL_TEXTURE_2D, positionTexture);
	}

	public void bind() {
		glBindFramebuffer(GL_FRAMEBUFFER, buffer);
	}

	public void unbind() {
		glBindFramebuffer(GL_FRAMEBUFFER, 0);
	}

	public void clearAndBind(Vector4f clearColor) {
		glBindFramebuffer(GL_FRAMEBUFFER, buffer);
		glClearColor(clearColor.x, clearColor.y, clearColor.z, 1);
		glClear(GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT | GL_COLOR_BUFFER_BIT);
		// Clears the position separately to prevent issues with default value.
		glClearBufferfv(GL_COLOR, 1, new float[] {0, 0, 6.55e4f, 1}); // z value corresponds to the highest 16-bit float value.

		glBindFramebuffer(GL_FRAMEBUFFER, buffer);
	}

	public void cleanup() {
		glDeleteTextures(colorTexture);
		glDeleteTextures(positionTexture);

		glDeleteRenderbuffers(depthBuffer);
		glDeleteFramebuffers(buffer);
	}
}
