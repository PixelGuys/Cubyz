package cubyz.rendering;

import static org.lwjgl.opengl.GL11.GL_FLOAT;
import static org.lwjgl.opengl.GL11.GL_LINE_LOOP;
import static org.lwjgl.opengl.GL11.GL_LINE_STRIP;
import static org.lwjgl.opengl.GL11.GL_TRIANGLE_STRIP;
import static org.lwjgl.opengl.GL11.glDrawArrays;
import static org.lwjgl.opengl.GL13.GL_TEXTURE0;
import static org.lwjgl.opengl.GL13.glActiveTexture;
import static org.lwjgl.opengl.GL15.GL_ARRAY_BUFFER;
import static org.lwjgl.opengl.GL15.GL_STATIC_DRAW;
import static org.lwjgl.opengl.GL15.glBindBuffer;
import static org.lwjgl.opengl.GL15.glBufferData;
import static org.lwjgl.opengl.GL15.glGenBuffers;
import static org.lwjgl.opengl.GL20.glEnableVertexAttribArray;
import static org.lwjgl.opengl.GL20.glUniform1f;
import static org.lwjgl.opengl.GL20.glUniform1i;
import static org.lwjgl.opengl.GL20.glUniform2f;
import static org.lwjgl.opengl.GL20.glVertexAttribPointer;
import static org.lwjgl.opengl.GL30.glBindVertexArray;
import static org.lwjgl.opengl.GL30.glGenVertexArrays;

import java.io.IOException;

import cubyz.utils.Utils;

//INFO: This class is structured differently than usual: Variables and functions are structured by use-case.
/**
 * Contains some standard 2D graphic functions, such as Text, Rectangles, lines and images.
 */
public class Graphics {
	// ----------------------------------------------------------------------------
	// Common stuff:
	private static int color;
	
	private static float globalAlphaMultiplier = 1;
	
	/**
	 * Sets a new color using the hexcode. The alpha channel is given seperately.
	 * @param rgb
	 */
	public static void setColor(int rgb, int alpha) {
		color = rgb | (int)(Math.min(alpha, 255)*globalAlphaMultiplier)<<24;
	}

	/**
	 * Sets a new color using the hexcode. Assumes that alpha is 255.
	 * @param rgb
	 */
	public static void setColor(int rgb) {
		setColor(rgb, 255);
	}
	
	/**
	 * Every alpha value will get multiplied by this multiplier.
	 * @param multiplier
	 */
	public static void setGlobalAlphaMultiplier(float multiplier) {
		globalAlphaMultiplier = multiplier;
	}
	

	// ----------------------------------------------------------------------------
	// Stuff for fillRect:
	
	static class RectUniforms {
		static int loc_screen;
		static int loc_start;
		static int loc_size;
		static int loc_rectColor;
	}
	static ShaderProgram rectShader;
	static final int rectVAO;
	
	static {
		try {
			rectShader = new ShaderProgram(Utils.loadResource("assets/cubyz/shaders/graphics/Rect.vs"),
					Utils.loadResource("assets/cubyz/shaders/graphics/Rect.fs"), RectUniforms.class);
		} catch (IOException e) {
			e.printStackTrace();
		}

		float[] rawdata = new float[] {
			0, 0,
			0, 1,
			1, 0,
			1, 1,
		};
		
		rectVAO = glGenVertexArrays();
		glBindVertexArray(rectVAO);
		int rectVBO = glGenBuffers();
		glBindBuffer(GL_ARRAY_BUFFER, rectVBO);
		glBufferData(GL_ARRAY_BUFFER, rawdata, GL_STATIC_DRAW);
		glVertexAttribPointer(0, 2, GL_FLOAT, false, 2*4, 0);
		glEnableVertexAttribArray(0);
	}
	
	/**
	 * 
	 * @param x coordinate of the starting point
	 * @param y coordinate of the starting point
	 * @param width width
	 * @param height height
	 */
	public static void fillRect(float x, float y, float width, float height) {
		rectShader.bind();
		
		glUniform2f(RectUniforms.loc_screen, Window.getWidth(), Window.getHeight());
		glUniform2f(RectUniforms.loc_start, x, y);
		glUniform2f(RectUniforms.loc_size, width, height);
		glUniform1i(RectUniforms.loc_rectColor, color);
		
		glBindVertexArray(rectVAO);
		glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
		
		rectShader.unbind();
	}
	
	// ----------------------------------------------------------------------------
	// Stuff for drawLine:
	
	static class LineUniforms {
		static int loc_screen;
		static int loc_start;
		static int loc_direction;
		static int loc_lineColor;
	}
	
	static ShaderProgram lineShader;
	static final int lineVAO;
	
	static {
		try {
			lineShader = new ShaderProgram(Utils.loadResource("assets/cubyz/shaders/graphics/Line.vs"),
					Utils.loadResource("assets/cubyz/shaders/graphics/Line.fs"), LineUniforms.class);
		} catch (IOException e) {
			e.printStackTrace();
		}

		float[] rawdata = new float[]{ 
			0, 0,
			1, 1,
		};

		lineVAO = glGenVertexArrays();
		glBindVertexArray(lineVAO);
		int lineVBO = glGenBuffers();
		glBindBuffer(GL_ARRAY_BUFFER, lineVBO);
		glBufferData(GL_ARRAY_BUFFER, rawdata, GL_STATIC_DRAW);
		glVertexAttribPointer(0, 2, GL_FLOAT, false, 2*4, 0);
		glEnableVertexAttribArray(0);
	}
	
	public static void drawLine(float x1, float y1, float x2, float y2) {
		lineShader.bind();

		glUniform2f(LineUniforms.loc_screen, Window.getWidth(), Window.getHeight());
		glUniform2f(LineUniforms.loc_start, x1, y1);
		glUniform2f(LineUniforms.loc_direction, x2 - x1, y2 - y1);
		glUniform1i(LineUniforms.loc_lineColor, color);
		
		glBindVertexArray(lineVAO);
		glDrawArrays(GL_LINE_STRIP, 0, 2);
		
		lineShader.unbind();
	}
	
	// ----------------------------------------------------------------------------
	// Stuff for drawRect:
	// Draw rect can use the same shader as drawline, because it essentially draws lines.
	static final int drawRectVAO;
	static {
		float[] rawdata = new float[]{ 
			0, 0,
			0, 1,
			1, 1,
			1, 0,
		};

		drawRectVAO = glGenVertexArrays();
		glBindVertexArray(drawRectVAO);
		int drawRectVBO = glGenBuffers();
		glBindBuffer(GL_ARRAY_BUFFER, drawRectVBO);
		glBufferData(GL_ARRAY_BUFFER, rawdata, GL_STATIC_DRAW);
		glVertexAttribPointer(0, 2, GL_FLOAT, false, 2*4, 0);
		glEnableVertexAttribArray(0);
	}
	
	/**
	 * Draws the border of the same area that fillRect uses.
	 * @param x1
	 * @param y1
	 * @param width
	 * @param height
	 */
	public static void drawRect(int x, int y, int width, int height) {
		lineShader.bind();

		glUniform2f(LineUniforms.loc_screen, Window.getWidth(), Window.getHeight());
		glUniform2f(LineUniforms.loc_start, x + 0.5f, y + 0.5f); // Move the coordinates, so they are in the center of a pixel.
		glUniform2f(LineUniforms.loc_direction, width - 1, height - 1); // The height is a lot smaller because the inner edge of the rect is drawn.
		glUniform1i(LineUniforms.loc_lineColor, color);
		
		glBindVertexArray(drawRectVAO);
		glDrawArrays(GL_LINE_LOOP, 0, 5);
		
		lineShader.unbind();
	}
	
	// ----------------------------------------------------------------------------
	// Stuff for fillCircle:
	
	static class CircleUniforms {
		static int loc_screen;
		static int loc_center;
		static int loc_radius;
		static int loc_circleColor;
	}
	static ShaderProgram circleShader;
	static final int circleVAO;
	
	static {
		try {
			circleShader = new ShaderProgram(Utils.loadResource("assets/cubyz/shaders/graphics/Circle.vs"),
					Utils.loadResource("assets/cubyz/shaders/graphics/Circle.fs"), CircleUniforms.class);
		} catch (IOException e) {
			e.printStackTrace();
		}

		float[] rawdata = new float[] {
			-1, -1,
			-1, 1,
			1, -1,
			1, 1,
		};
		
		circleVAO = glGenVertexArrays();
		glBindVertexArray(circleVAO);
		int circleVBO = glGenBuffers();
		glBindBuffer(GL_ARRAY_BUFFER, circleVBO);
		glBufferData(GL_ARRAY_BUFFER, rawdata, GL_STATIC_DRAW);
		glVertexAttribPointer(0, 2, GL_FLOAT, false, 2*4, 0);
		glEnableVertexAttribArray(0);
	}
	
	/**
	 * Draws an anti-aliased circle.
	 * @param x coordinate of the center point
	 * @param y coordinate of the center point
	 * @param radius
	 */
	public static void fillCircle(float x, float y, float radius) {
		circleShader.bind();
		
		glUniform2f(CircleUniforms.loc_screen, Window.getWidth(), Window.getHeight());
		glUniform2f(CircleUniforms.loc_center, x, y);
		glUniform1f(CircleUniforms.loc_radius, radius);
		glUniform1i(CircleUniforms.loc_circleColor, color);
		
		glBindVertexArray(circleVAO);
		glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
		
		circleShader.unbind();
	}
	
	// ----------------------------------------------------------------------------
	// Stuff for drawImage:
	// Luckily the vao of the regular rect can used.
	static class ImageUniforms {
		static int loc_screen;
		static int loc_start;
		static int loc_size;
		static int loc_image;
	}
	static ShaderProgram imageShader;
	
	static {
		try {
			imageShader = new ShaderProgram(Utils.loadResource("assets/cubyz/shaders/graphics/Image.vs"),
					Utils.loadResource("assets/cubyz/shaders/graphics/Image.fs"), ImageUniforms.class);
		} catch (IOException e) {
			e.printStackTrace();
		}
	}
	
	/**
	 * Draws an image inside the given region on the screen.
	 * @param texture can be null
	 * @param x coordinate of the starting point
	 * @param y coordinate of the starting point
	 * @param width width of the on-screen region
	 * @param height height of the on-screen region
	 */
	public static void drawImage(Texture texture, float x, float y, float width, float height) {
		if(texture == null) return;
		
		imageShader.bind();
		glActiveTexture(GL_TEXTURE0);
		texture.bind();
		
		glUniform2f(ImageUniforms.loc_screen, Window.getWidth(), Window.getHeight());
		glUniform2f(ImageUniforms.loc_start, x, y);
		glUniform2f(ImageUniforms.loc_size, width, height);
		
		glBindVertexArray(rectVAO);
		glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
		
		imageShader.unbind();
	}
}
