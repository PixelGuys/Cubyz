package cubyz.rendering;

import static org.lwjgl.opengl.GL42.*;

import java.awt.image.BufferedImage;
import java.nio.ByteBuffer;
import java.nio.IntBuffer;
import java.util.ArrayList;

import cubyz.utils.Logger;
import cubyz.utils.math.CubyzMath;

public class TextureArray {
	private final ArrayList<BufferedImage> textures = new ArrayList<>();

	private final int textureId;

	public boolean[] isTransparent;

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

	private static int lodColorInterpolation(int[] colors, boolean isTransparent) {
		int[] r = new int[4];
		int[] g = new int[4];
		int[] b = new int[4];
		int[] a = new int[4];
		for(int i = 0; i < 4; i++) {
			r[i] = colors[i]>>>24;
			g[i] = colors[i]>>>16 & 0xFF;
			b[i] = colors[i]>>>8 & 0xFF;
			a[i] = colors[i] & 0xFF;
		}
		// Use gamma corrected average(https://stackoverflow.com/a/832314/13082649):
		int aSum = 0;
		int rSum = 0;
		int gSum = 0;
		int bSum = 0;
		for(int i = 0; i < 4; i++) {
			aSum += a[i]*a[i];
			rSum += r[i]*r[i];
			gSum += g[i]*g[i];
			bSum += b[i]*b[i];
		}
		aSum = (int)Math.round(Math.sqrt(aSum))/2;
		if (!isTransparent) {
			// If the source image isn't transparent then the mipmapped version shouldn't do that either. In case of uncertainty an opaque version gets used.
			if (aSum < 128) {
				aSum = 0;
			} else {
				aSum = 255;
			}
		}
		rSum = (int)Math.round(Math.sqrt(rSum))/2;
		gSum = (int)Math.round(Math.sqrt(gSum))/2;
		bSum = (int)Math.round(Math.sqrt(bSum))/2;
		if (aSum > 0xFF) {
			Logger.warning("@IntegratedQuantum: color out of range");
			aSum = 0xFF;
		}
		if (rSum > 0xFF) {
			Logger.warning("@IntegratedQuantum: color out of range");
			rSum = 0xFF;
		}
		if (gSum > 0xFF) {
			Logger.warning("@IntegratedQuantum: color out of range");
			gSum = 0xFF;
		}
		if (bSum > 0xFF) {
			Logger.warning("@IntegratedQuantum: color out of range");
			bSum = 0xFF;
		}
		return rSum<<24 | gSum<<16 | bSum<<8 | aSum;
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
		if ((maxWidth-1 & maxWidth) != 0) {
			maxWidth = 2 << CubyzMath.binaryLog(maxWidth);
		}
		if ((maxHeight-1 & maxHeight) != 0) {
			maxHeight = 2 << CubyzMath.binaryLog(maxHeight);
		}

		Logger.debug("Creating Texture Array of size "+maxWidth+", "+maxHeight+" with "+layers+" layers.");

		glBindTexture(GL_TEXTURE_2D_ARRAY, textureId);

		int maxLOD = 1 + CubyzMath.binaryLog(Math.max(maxWidth, maxHeight));
		glTexStorage3D(GL_TEXTURE_2D_ARRAY, maxLOD, GL_RGBA8, maxWidth, maxHeight, layers);

		IntBuffer[] buf = new IntBuffer[maxLOD];
		for(int i = 0; i < maxLOD; i++) {
			buf[i] = ByteBuffer.allocateDirect(4*(maxWidth >> i)*(maxHeight >> i)).asIntBuffer();
		}

		isTransparent = new boolean[layers];

		for(int i = 0; i < layers; i++) {
			BufferedImage img = textures.get(i);
			// Check if the image contains non-binary alpha values, which makes it transparent.
			for(int x = 0; x < img.getWidth(); x++) {
				for(int y = 0; y < img.getHeight(); y++) {
					int a = img.getRGB(x, y) & 0xff000000;
					if (a != 0 && a != 0xff000000) {
						isTransparent[i] = true;
						break;
					}
				}
			}

			// Fill the buffer using nearest sampling. Probably not the best solutions for all textures, but that's what happens when someone doesn't use power of 2 textures...
			for(int x = 0; x < maxWidth; x++) {
				for(int y = 0; y < maxHeight; y++) {
					int index = x + y*maxWidth;
					int argb = img.getRGB(x*img.getWidth()/maxWidth, y*img.getHeight()/maxHeight);
					int rgba = argb<<8 | argb>>>24;
					buf[0].put(index, rgba);
				}
			}

			// Calculate the mipmap levels:
			for(int lod = 0; lod < maxLOD; lod++) {
				int curWidth = maxWidth >> lod;
				int curHeight = maxHeight >> lod;
				if (lod != 0) {
					for(int x = 0; x < curWidth; x++) {
						for(int y = 0; y < curHeight; y++) {
							int index = x + y*curWidth;
							int index2 = 2*x + 2*y*2*curWidth;
							int[] colors = new int[4]; // The 4 colors that should be combined.
							colors[0] = buf[lod-1].get(index2);
							colors[1] = buf[lod-1].get(index2 + 1);
							colors[2] = buf[lod-1].get(index2 + curWidth*2);
							colors[3] = buf[lod-1].get(index2 + curWidth*2 + 1);
							int result = lodColorInterpolation(colors, isTransparent[i]);
							buf[lod].put(index, result);
						}
					}
				}
				glTexSubImage3D(GL_TEXTURE_2D_ARRAY, lod, 0, 0, i, curWidth, curHeight, 1, GL_RGBA, GL_UNSIGNED_BYTE, buf[lod]);
			}
		}
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAX_LOD, CubyzMath.binaryLog(Math.max(maxWidth, maxHeight)));
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_BASE_LEVEL, 5);
		//glGenerateMipmap(GL_TEXTURE_2D_ARRAY);
		glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MIN_FILTER, GL_NEAREST_MIPMAP_LINEAR);
		glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_WRAP_S, GL_REPEAT);
		glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_WRAP_T, GL_REPEAT);
	}
	
	public void bind() {
		glBindTexture(GL_TEXTURE_2D_ARRAY, textureId);
	}
}
