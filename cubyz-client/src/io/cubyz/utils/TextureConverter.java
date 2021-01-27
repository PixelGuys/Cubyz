package io.cubyz.utils;

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

import io.cubyz.util.ColorUtils;

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
			e.printStackTrace();
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
			e.printStackTrace();
		}
		byte[] array = baos.toByteArray();
		return new ByteArrayInputStream(array);
	}
	
	public static BufferedImage compose(String[] paths) {
		try {
			BufferedImage out;
			if(paths[0].contains("|"))
				out = convertTemplate(paths[0]);
			else
				out = ImageIO.read(new File(paths[0]));
			Graphics2D g2d = out.createGraphics();
			for(int i = 1; i < paths.length; i++) {
				BufferedImage img;
				if(paths[i].contains("|"))
					img = convertTemplate(paths[i]);
				else
					img = ImageIO.read(new File(paths[i]));
				g2d.drawImage(img, 0, 0, null);
			}
			return out;
		}
		catch(IOException e) {
			e.printStackTrace();
			System.out.println(Arrays.toString(paths));
		}
		return null;
	}
	
	public static BufferedImage convertTemplate(String path) throws IOException {
		String [] parts = path.split("\\|");
		BufferedImage template = ImageIO.read(new File(parts[0]+parts[2]));
		int color = Integer.parseInt(parts[1]);
		convertTemplate(template, color);
		return template;
	}
	
	public static void convertTemplate(BufferedImage tem, int color) {
		color |= 0x1f1f1f; // Prevent overflows.
		for(int x = 0; x < tem.getWidth(); x++) {
			for(int y = 0; y < tem.getHeight(); y++) {
				int hsvItem = ColorUtils.getHSV(color);
				int hsvTemp = tem.getRGB(x, y);
				int a = hsvTemp >>> 24;
				int h1 =  (hsvItem >>> 16) & 255;
				int s1 = (hsvItem >>> 8) & 255;
				int v1 = (hsvItem >>> 0) & 255;
				int h2 =  (hsvTemp >>> 16) & 255;
				int s2 = (hsvTemp >>> 8) & 255;
				int v2 = (hsvTemp >>> 0) & 255;
				h2 += h1;
				s2 += s1;
				v2 += v1;
				h2 &= 255;
				s2 &= 255;
				v2 &= 255;
				int resHSV = (h2 << 16) | (s2 << 8) | v2;
				tem.setRGB(x, y, ColorUtils.getRGB(resHSV) | (a << 24));
			}
		}
	}
}
