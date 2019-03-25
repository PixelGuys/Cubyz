package io.cubyz.utils;

import java.awt.Graphics2D;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;

import javax.imageio.ImageIO;

public class TextureConverter {

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
	
	public static BufferedImage convert(BufferedImage in, String name) {
		File cached = new File("cache/" + name.replace('/', '.') + ".png");
		File cacheDir = new File("cache");
		if (!cacheDir.exists())
			cacheDir.mkdirs();
		if (cached.exists()) {
			try {
				return ImageIO.read(cached);
			} catch (IOException e) {
				System.err.println("Could not read cache of " + name + " texture");
			}
		}
		BufferedImage out = new BufferedImage(1024, 1024, BufferedImage.TYPE_INT_ARGB);
		Graphics2D g2d = out.createGraphics();
		g2d.drawImage(in, 0, 0, 512, 512, null);
		g2d.drawImage(in, 512, 0, 512, 512, null);
		g2d.drawImage(in, 0, 512, 512, 512, null);
		try {
			ImageIO.write(out, "png", new FileOutputStream(cached));
		} catch (IOException e) {
			System.err.println("Could not cache converted texture: " + name);
		}
		return out;
	}
	
}
