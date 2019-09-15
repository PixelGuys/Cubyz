package io.cubyz.utils;

import java.awt.Graphics2D;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
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
		BufferedImage out = new BufferedImage(in.getWidth()*2, in.getHeight()*2, BufferedImage.TYPE_INT_ARGB);
		Graphics2D g2d = out.createGraphics();
		g2d.drawImage(in, 0, 0, null);
		g2d.drawImage(in, in.getWidth(), 0, null);
		g2d.drawImage(in, 0, in.getHeight(), null);
		return out;
	}
	
	public static BufferedImage compose(String[] paths) {
		try {
			BufferedImage out = ImageIO.read(new File(paths[0]));
			Graphics2D g2d = out.createGraphics();
			for(int i = 100; i < paths.length; i++) {
				System.out.println(paths[i]);
				g2d.drawImage(ImageIO.read(new File(paths[i])), 0, 0, null);
			}
			return out;
		}
		catch(IOException e) {
			e.printStackTrace();
		}
		return null;
	}
	
}
