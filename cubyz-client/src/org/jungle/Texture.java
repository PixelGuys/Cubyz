package org.jungle;

import de.matthiasmann.twl.utils.PNGDecoder;
import de.matthiasmann.twl.utils.PNGDecoder.Format;

import java.io.FileInputStream;
import java.io.InputStream;
import java.nio.ByteBuffer;
import static org.lwjgl.opengl.GL11.*;
import static org.lwjgl.opengl.GL30.glGenerateMipmap;

public class Texture {

    private int id = Integer.MIN_VALUE;
    protected int width, height;
    protected InputStream is;

    public Texture(String fileName) throws Exception {
        this.is = new FileInputStream(fileName);
        bind();
    }
    
    public Texture(InputStream is) {
    	this.is = is;
    	bind();
    }

    public Texture(int id) {
        this.id = id;
    }

    public void bind() {
    	if (id == Integer.MIN_VALUE) {
    		if (is != null) {
    			try {
					id = loadTexture(is);
				} catch (Exception e) {
					e.printStackTrace();
				}
    		} else {
    			throw new IllegalStateException("ID not set and file name not providen.");
    		}
    	}
        glBindTexture(GL_TEXTURE_2D, id);
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
        ByteBuffer buf = ByteBuffer.allocateDirect(
                4 * decoder.getWidth() * decoder.getHeight());
        width = decoder.getWidth();
        height = decoder.getHeight();
        decoder.decode(buf, decoder.getWidth() * 4, Format.RGBA);
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
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, decoder.getWidth(), decoder.getHeight(), 0,
                GL_RGBA, GL_UNSIGNED_BYTE, buf);
        // Generate Mip Map
        glGenerateMipmap(GL_TEXTURE_2D);
        return textureId;
    }

    public void cleanup() {
        glDeleteTextures(id);
    }
}
