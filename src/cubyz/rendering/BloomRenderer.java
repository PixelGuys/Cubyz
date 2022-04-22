package cubyz.rendering;

import cubyz.utils.Utils;

import java.io.IOException;

import static org.lwjgl.opengl.GL30.*;

public final class BloomRenderer {
	private static final FrameBuffer buffer1, buffer2, extractedBuffer;
	private static Texture texture1, texture2, extractedTexture;
	public static int loc_color;
	private static int width = -1;
	private static int height = -1;
	private static ShaderProgram firstPassShader;
	private static ShaderProgram secondPassShader;
	private static ShaderProgram colorExtractShader;
	private static ShaderProgram scaleShader;

	static {
		buffer1 = new FrameBuffer();
		buffer2 = new FrameBuffer();
		extractedBuffer = new FrameBuffer();
	}

	public static void init(String shaders) throws IOException {
		if (colorExtractShader != null) {
			colorExtractShader.cleanup();
		}
		colorExtractShader = new ShaderProgram(
				Utils.loadResource(shaders + "/bloom/color_extractor.vs"),
				Utils.loadResource(shaders + "/bloom/color_extractor.fs"),
				BloomRenderer.class
		);
		if (scaleShader != null) {
			scaleShader.cleanup();
		}
		scaleShader = new ShaderProgram(
				Utils.loadResource(shaders + "/bloom/scale.vs"),
				Utils.loadResource(shaders + "/bloom/scale.fs"),
				BloomRenderer.class
		);
		if (firstPassShader != null) {
			firstPassShader.cleanup();
		}
		firstPassShader = new ShaderProgram(
				Utils.loadResource(shaders + "/bloom/first_pass.vs"),
				Utils.loadResource(shaders + "/bloom/first_pass.fs"),
				BloomRenderer.class
		);
		if (secondPassShader != null) {
			secondPassShader.cleanup();
		}
		secondPassShader = new ShaderProgram(
				Utils.loadResource(shaders + "/bloom/second_pass.vs"),
				Utils.loadResource(shaders + "/bloom/second_pass.fs"),
				BloomRenderer.class
		);
	}

	private static void extractImageData(BufferManager buffer) {
		colorExtractShader.bind();
		buffer.bindTextures();
		extractedBuffer.bind();
		glBindVertexArray(Graphics.rectVAO);
		glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
	}

	private static void downscale() {
		scaleShader.bind();
		glActiveTexture(GL_TEXTURE3);
		extractedTexture.bind();
		buffer1.bind();
		glBindVertexArray(Graphics.rectVAO);
		glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
	}

	private static void firstPass() {
		firstPassShader.bind();
		glActiveTexture(GL_TEXTURE3);
		texture1.bind();
		buffer2.bind();
		glBindVertexArray(Graphics.rectVAO);
		glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
	}

	private static void secondPass() {
		secondPassShader.bind();
		glActiveTexture(GL_TEXTURE3);
		texture2.bind();
		buffer1.bind();
		glBindVertexArray(Graphics.rectVAO);
		glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
	}

	private static void upscale(BufferManager buffer) {
		scaleShader.bind();
		glActiveTexture(GL_TEXTURE3);
		texture1.bind();
		buffer.bind();
		glBindVertexArray(Graphics.rectVAO);
		glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
	}

	public static void render(BufferManager buffer, int width, int height) {
		if(width != BloomRenderer.width || height != BloomRenderer.height) {
			buffer1.genColorTexture(width/2, height/2, GL_LINEAR, GL_CLAMP_TO_EDGE);
			buffer2.genColorTexture(width/2, height/2, GL_LINEAR, GL_CLAMP_TO_EDGE);
			extractedBuffer.genColorTexture(width, height, GL_LINEAR, GL_CLAMP_TO_EDGE);
			texture1 = buffer1.texture;
			texture2 = buffer2.texture;
			extractedTexture = extractedBuffer.texture;
			BloomRenderer.width = width;
			BloomRenderer.height = height;
		}
		glDisable(GL_DEPTH_TEST);
		glDisable(GL_CULL_FACE);

		extractImageData(buffer);
		glViewport(0, 0, width/2, height/2);
		downscale();
		firstPass();
		secondPass();
		glViewport(0, 0, width, height);
		glBlendFunc(GL_ONE, GL_ONE);
		upscale(buffer);

		glEnable(GL_DEPTH_TEST);
		glEnable(GL_CULL_FACE);
		glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
	}
}
