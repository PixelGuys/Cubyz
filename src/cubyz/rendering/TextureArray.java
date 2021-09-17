package cubyz.rendering;

import static org.lwjgl.opengl.GL42.*;

import java.awt.image.BufferedImage;
import java.nio.ByteBuffer;
import java.nio.IntBuffer;
import java.util.ArrayList;

import cubyz.Logger;
import cubyz.utils.math.CubyzMath;

public class TextureArray {
	private final ArrayList<BufferedImage> textures = new ArrayList<>();

	private final int textureId;

	public TextureArray() {
		textureId = glGenTextures();
	}

	/**
	 * Adds a texture to the array, but doesn't regenerate the GPU texture array.
	 * @param img width and height are recommended to be a power of 2. Otherwise artifacts will occur!
	 * @return index in the array.
	 */
	public synchronized int addTexture(BufferedImage img) {
		textures.add(img);
		return textures.size() - 1;
	}

	/**
	 * Removes all textures.
	 */
	public void clear() {
		textures.clear();
	}

	/**
	 * (Re-)Generates the GPU buffer.
	 */
	public void generate() {
		int maxWidth = 0, maxHeight = 0;
		int layers = textures.size();
		for(int i = 0; i < layers; i++) {
			maxWidth = Math.max(maxWidth, textures.get(i).getWidth());
			maxHeight = Math.max(maxHeight, textures.get(i).getHeight());
		}

		// Make sure the width and height use a power of 2:
		if((maxWidth-1 & maxWidth) != 0) {
			maxWidth = 2 << CubyzMath.binaryLog(maxWidth);
		}
		if((maxHeight-1 & maxHeight) != 0) {
			maxHeight = 2 << CubyzMath.binaryLog(maxHeight);
		}

		Logger.debug("Creating Texture Array of size "+maxWidth+", "+maxHeight+" with "+layers+" layers.");

		glBindTexture(GL_TEXTURE_2D_ARRAY, textureId);

		glTexStorage3D(GL_TEXTURE_2D_ARRAY, CubyzMath.binaryLog(Math.max(maxWidth, maxHeight)), GL_RGBA8, maxWidth, maxHeight, layers);

		IntBuffer buf = ByteBuffer.allocateDirect(4*maxWidth*maxHeight).asIntBuffer();

		for(int i = 0; i < layers; i++) {
			BufferedImage img = textures.get(i);
			// Fill the buffer using nearest sampling. Probably not the best solutions for all textures, but that's what happens when someone doesn't use power of 2 textures...
			for(int x = 0; x < maxWidth; x++) {
				for(int y = 0; y < maxHeight; y++) {
					int index = x + y*maxWidth;
					int argb = img.getRGB(x*img.getWidth()/maxWidth, y*img.getHeight()/maxHeight);
					int rgba = argb<<8 | argb>>>24;
					buf.put(index, rgba);
				}
			}
			glTexSubImage3D(GL_TEXTURE_2D_ARRAY, 0, 0, 0, i, maxWidth, maxHeight, 1, GL_RGBA, GL_UNSIGNED_BYTE, buf);
		}
		glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_WRAP_S, GL_REPEAT);
		glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_WRAP_T, GL_REPEAT);
	}
	
	public void bind() {
		glBindTexture(GL_TEXTURE_2D_ARRAY, textureId);
	}
}
