package cubyz.utils;

import java.awt.Graphics2D;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.util.Arrays;

import javax.imageio.ImageIO;

import org.lwjgl.system.MemoryUtil;

import cubyz.utils.datastructures.PixelUtils;

/**
 * Collection of texture conversion tools such as:<br>
 * laying textures on top of each other, converting the color and converting image to stream or buffer.
 */

public class TextureConverter {

	public static ByteBuffer byteBuffer(BufferedImage img) {
		ByteArrayOutputStream baos = new ByteArrayOutputStream();
		try {
			ImageIO.write(img, "png", baos);
		} catch (IOException e) {
			Logger.error(e);
		}
		byte[] array = baos.toByteArray();
		ByteBuffer buf = MemoryUtil.memAlloc(array.length);
		buf.put(array);
		buf.flip();
		return buf;
	}
	
	public static InputStream fromBufferedImage(BufferedImage img) {
		ByteArrayOutputStream baos = new ByteArrayOutputStream();
		try {
			ImageIO.write(img, "png", baos);
		} catch (IOException e) {
			Logger.error(e);
		}
		byte[] array = baos.toByteArray();
		return new ByteArrayInputStream(array);
	}
	
	public static BufferedImage compose(String[] paths) {
		try {
			BufferedImage out;
			if (paths[0].contains("|"))
				out = convertTemplate(paths[0]);
			else
				out = ImageIO.read(new File(paths[0]));
			Graphics2D g2d = out.createGraphics();
			for(int i = 1; i < paths.length; i++) {
				BufferedImage img;
				if (paths[i].contains("|"))
					img = convertTemplate(paths[i]);
				else
					img = ImageIO.read(new File(paths[i]));
				g2d.drawImage(img, 0, 0, null);
			}
			return out;
		}
		catch(IOException e) {
			Logger.error(e);
			Logger.info(Arrays.toString(paths));
		}
		return null;
	}
	
	public static BufferedImage convertTemplate(String path) throws IOException {
		String [] parts = path.split("\\|");
		BufferedImage template = ImageIO.read(new File(parts[0]+parts[2]));
		int color = Integer.parseInt(parts[1]);
		PixelUtils.convertTemplate(template, color);
		return template;
	}
}
