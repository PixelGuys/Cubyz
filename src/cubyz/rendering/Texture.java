package cubyz.rendering;

import de.matthiasmann.twl.utils.PNGDecoder;
import de.matthiasmann.twl.utils.PNGDecoder.Format;

import java.awt.image.BufferedImage;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.ByteBuffer;

import cubyz.utils.Logger;
import cubyz.client.ClientSettings;
import cubyz.utils.TextureConverter;

import static org.lwjgl.opengl.GL30.*;

public class Texture {

	protected int id = Integer.MIN_VALUE;
	protected int width, height;
	protected int pixelFormat;
	protected int internalFormat;
	
	public static Texture loadFromFile(String path) {
		try {
			return new Texture(path);
		} catch(IOException e) {
			Logger.error(e);
			return null; // TODO: Default image.
		}
	}
	
	public static Texture loadFromFile(File file) {
		try {
			return new Texture(file);
		} catch(IOException e) {
			Logger.error(e);
			return null; // TODO: Default image.
		}
	}
	
	public static Texture loadFromImage(BufferedImage img) {
		return new Texture(TextureConverter.fromBufferedImage(img));
	}

	private Texture(String fileName) throws IOException {
		this(new FileInputStream(fileName));
	}
	
	public Texture(File file) throws IOException {
		this(new FileInputStream(file));
	}

	public Texture(InputStream is) {
		create(is);
	}

	public Texture(int id) {
		this.id = id;
	}
	
	
	// depth texture
	public Texture(int width, int height, int pixelFormat) {
		this.id = glGenTextures();
		this.width = width;
		this.height = height;
		glBindTexture(GL_TEXTURE_2D, id);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
		glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT, width, height, 0, pixelFormat, GL_FLOAT, (ByteBuffer) null);
	}
	
	public void updateTexture(BufferedImage img) {
		cleanup();
		InputStream is = TextureConverter.fromBufferedImage(img);
		create(is);
	}
	
	public void setWrapMode(int wrap) {
		glBindTexture(GL_TEXTURE_2D, id);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, wrap);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, wrap);
	}
	
	public void create(InputStream is) {
		try {
			id = loadTexture(is);
			is.close();
		} catch (Exception e) {
			Logger.error(e);
		}
	}
	
	public void bind() {
		glBindTexture(GL_TEXTURE_2D, id);
	}
	
	public void unbind() {
		glBindTexture(GL_TEXTURE_2D, 0);
	}

	public int getId() {
		return id;
	}

	public int getWidth() {
		return width;
	}

	public int getHeight() {
		return height;
	}

	private int loadTexture(InputStream is) throws Exception {
		// Load Texture file
		PNGDecoder decoder = new PNGDecoder(is);

		// Load texture contents into a byte buffer
		width = decoder.getWidth();
		height = decoder.getHeight();
		ByteBuffer buf = ByteBuffer.allocateDirect(width * height << 2);
		decoder.decode(buf, width << 2, Format.RGBA);
		buf.flip();

		// Create a new OpenGL texture
		int textureId = glGenTextures();
		// Bind the texture
		glBindTexture(GL_TEXTURE_2D, textureId);

		// Tell OpenGL how to unpack the RGBA bytes. Each component is 1 byte size
		glPixelStorei(GL_UNPACK_ALIGNMENT, 1);

		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

		// Upload the texture data
		glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, decoder.getWidth(), decoder.getHeight(), 0, GL_RGBA, GL_UNSIGNED_BYTE,
				buf);

		if (ClientSettings.MIPMAPPING) {
			glGenerateMipmap(GL_TEXTURE_2D);
		}
		glBindTexture(GL_TEXTURE_2D, 0);
		return textureId;
	}

	public void cleanup() {
		glDeleteTextures(id);
	}
}
