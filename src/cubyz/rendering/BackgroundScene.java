package cubyz.rendering;

import static org.lwjgl.opengl.GL30.*;

import java.awt.image.BufferedImage;
import java.io.File;
import java.io.FileFilter;
import java.io.IOException;
import java.nio.ByteBuffer;

import javax.imageio.ImageIO;

import org.joml.Matrix4f;
import org.joml.Vector3f;

import cubyz.utils.Logger;
import cubyz.client.ClientSettings;
import cubyz.client.Cubyz;
import cubyz.client.GameLauncher;
import cubyz.utils.Utils;

/**
 * Renders the background landscape you see in the menu.
 */

public class BackgroundScene {
	static ShaderProgram cubeShader;

	public static int loc_image;
	public static int loc_viewMatrix;
	public static int loc_projectionMatrix;

	private static int vao;

	private static Texture texture;

	private static float angle = 0;
	private static long lastTime = System.nanoTime();

	static {
		try {
			cubeShader = new ShaderProgram(Utils.loadResource("assets/cubyz/shaders/background/vertex.vs"),
					Utils.loadResource("assets/cubyz/shaders/background/fragment.fs"), BackgroundScene.class);
		} catch (IOException e) {
			e.printStackTrace();
		}

		// 4 sides of a simple cube with some panorama texture on it.
		float[] rawdata = new float[] {
			-1, -1, -1, 1, 1,
			-1, 1, -1, 1, 0,
			-1, -1, 1, 0.75f, 1,
			-1, 1, 1, 0.75f, 0,
			1, -1, 1, 0.5f, 1,
			1, 1, 1, 0.5f, 0,
			1, -1, -1, 0.25f, 1,
			1, 1, -1, 0.25f, 0,
			-1, -1, -1, 0, 1,
			-1, 1, -1, 0, 0,
		};

		int[] indices = new int[] {
			0, 1, 2,
			2, 3, 1,
			2, 3, 4,
			4, 5, 3,
			4, 5, 6,
			6, 7, 5,
			6, 7, 8,
			8, 9, 7,
		};
		
		vao = glGenVertexArrays();
		glBindVertexArray(vao);
		int vbo = glGenBuffers();
		glBindBuffer(GL_ARRAY_BUFFER, vbo);
		glBufferData(GL_ARRAY_BUFFER, rawdata, GL_STATIC_DRAW);
		glVertexAttribPointer(0, 3, GL_FLOAT, false, 5*4, 0);
		glVertexAttribPointer(1, 2, GL_FLOAT, false, 5*4, 3*4);
		glEnableVertexAttribArray(0);
		glEnableVertexAttribArray(1);
		// index VBO
		vbo = glGenBuffers();
		glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, vbo);
		glBufferData(GL_ELEMENT_ARRAY_BUFFER, indices, GL_STATIC_DRAW);

		// Load a random texture from the backgrounds folder. The player may make their own pictures which have a chance of getting shown aswell.
		File bgs = new File("assets/backgrounds");
		File[] images = bgs.listFiles(new FileFilter() {
			public boolean accept(File file) {
				return file.isFile() && file.getName().toLowerCase().endsWith(".png");
			}
		});
		// Choose a random image if available.
		if (images.length != 0) {
			texture = Texture.loadFromFile(images[(int)(Math.random()*images.length)]);
		} else {
			texture = null;
			Logger.error("Couldn't find any menu background images.");
		}
	}
	public static void renderBackground() {
		if (texture == null) return;

		glDisable(GL_CULL_FACE); // I'm not sure if my triangles are rotated correctly, and there are no triangles facing away from the player anyways.

		// Use a simple rotation around the y axis, with a steadily increasing angle.
		long newTime = System.nanoTime();
		angle += (newTime - lastTime)/2e10f;
		lastTime = newTime;
		Matrix4f viewMatrix = new Matrix4f().identity().rotateY(angle);
		cubeShader.bind();

		cubeShader.setUniform(loc_viewMatrix, viewMatrix);
		cubeShader.setUniform(loc_projectionMatrix, Window.getProjectionMatrix());
		cubeShader.setUniform(loc_image, 0);

		texture.bind();

		glBindVertexArray(vao);
		glDrawElements(GL_TRIANGLES, 24, GL_UNSIGNED_INT, 0);
	}

	public static void takeBackgroundImage() {
		int SIZE = 2048; // Use a power of 2 here, to reduce video memory waste.
		int[] pixels = new int[SIZE*SIZE];

		// allocate space for RBG pixels
		ByteBuffer fb = ByteBuffer.allocateDirect(SIZE*SIZE*3);

		// Change the viewport and the matrices to render 4 cube faces:

		GameLauncher.renderer.updateViewport(SIZE, SIZE, 90.0f);

		FrameBuffer buffer = new FrameBuffer();
		buffer.genColorTexture(SIZE, SIZE);
		buffer.genRenderbuffer(SIZE, SIZE);
		Window.setRenderTarget(buffer);

		Vector3f cameraRotation = Camera.getRotation();
		Vector3f rotationCopy = new Vector3f(cameraRotation);

		float[] angles = {(float)Math.PI/2, (float)Math.PI, (float)Math.PI*3/2, (float)Math.PI*2};

		// All 4 sides are stored in a single image.
		BufferedImage image = new BufferedImage(SIZE*4, SIZE, BufferedImage.TYPE_INT_RGB);

		boolean showOverlay = Cubyz.gameUI.showOverlay;
		Cubyz.gameUI.showOverlay = false; // Disable GUI overlay.
		for(int i = 0; i < 4; i++) {
			cameraRotation.set(0, angles[i], 0);
			// Draw to frame buffer.
			GameLauncher.renderer.render();
			// Copy the pixels directly from openGL
			buffer.bind();
			glReadPixels(0, 0, SIZE, SIZE, GL_RGB, GL_UNSIGNED_BYTE, fb);

			// convert bytes to integer array
			for (int j = 0; j < pixels.length; j++) {
				int i3 = j*3;
				// The resulting image needs to be turned upside down. This is done by simply changing the index in the output array:
				pixels[j%SIZE + (SIZE - 1 - j/SIZE)*SIZE] =
					((fb.get(i3) << 16)) +
					((fb.get(i3+1) << 8)) +
					((fb.get(i3+2) << 0));
			}

			// Draw it to the BufferedImage:
			image.setRGB(i*SIZE, 0, SIZE, SIZE, pixels, 0, SIZE);
		}

		Window.setRenderTarget(null);

		try {//Try to create image, else show exception.
			ImageIO.write(image, "png", new File("assets/backgrounds/"+Cubyz.world.getName()+"_"+Cubyz.world.getGameTime()+".png"));
		}
		catch (Exception e) {
			Logger.error(e);
		}

		GameLauncher.renderer.updateViewport(Window.getWidth(), Window.getHeight(), ClientSettings.FOV);
		Logger.debug("Made background image.");
		cameraRotation.set(rotationCopy);
		Cubyz.gameUI.showOverlay = showOverlay;
	}
}
