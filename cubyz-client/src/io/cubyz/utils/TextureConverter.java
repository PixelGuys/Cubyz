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
				int hsvItem = getHSV(color);
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
				tem.setRGB(x, y, getRGB(resHSV) | (a << 24));
			}
		}
	}
	
	

	// Some useful color conversions:
	public static int getHSV(int rgb) {
		double r = ((rgb >>> 16) & 255)/255.0;
		double g = ((rgb >>> 8) & 255)/255.0;
		double b = ((rgb >>> 0) & 255)/255.0;
		double min = Math.min(r, Math.min(g, b));
		double max = Math.max(r, Math.max(g, b));
		double delta = max-min;
		double h, s, v;
		v = max;
		s = delta/max;
		if( r >= max )
	        h = (g - b) / delta;        // between yellow & magenta
	    else
	    if( g >= max )
	        h = 2.0 + (b - r) / delta;  // between cyan & yellow
	    else
	        h = 4.0 + (r - g) / delta;  // between magenta & cyan
		
		h *= 60.0;                              // degrees

	    if(h < 0.0)
	        h += 360.0;
	    h /= 360;
		if(h > 1) h = 1;
		if(h < 0) h = 0;
		if(s > 1) s = 1;
		if(s < 0) s = 0;
		if(v > 1) v = 1;
		if(v < 0) v = 0;
	    int output = ((int)(h*255) << 16) | ((int)(s*255) << 8) | (int)(v*255);
	    return output;
	}
	
	static int getRGB(int hsv) {
		double h = ((hsv >>> 16) & 255)/255.0;
		double s = ((hsv >>> 8) & 255)/255.0;
		double v = ((hsv >>> 0) & 255)/255.0;
		double hh = h*360;
		hh /= 60;
		int i = (int)hh;
		double ff = hh-i;
		double p = v*(1-s);
		double q = v*(1-s*ff);
		double t = v*(1-s*(1-ff));
		double r, g, b;
		switch(i) {
	    case 0:
	        r = v;
	        g = t;
	        b = p;
	        break;
	    case 1:
	        r = q;
	        g = v;
	        b = p;
	        break;
	    case 2:
	        r = p;
	        g = v;
	        b = t;
	        break;

	    case 3:
	        r = p;
	        g = q;
	        b = v;
	        break;
	    case 4:
	        r = t;
	        g = p;
	        b = v;
	        break;
	    case 5:
	    default:
	        r = v;
	        g = p;
	        b = q;
	        break;
	    }
		if(r > 1) r = 1;
		if(r < 0) r = 0;
		if(g > 1) g = 1;
		if(g < 0) g = 0;
		if(b > 1) b = 1;
		if(b < 0) b = 0;
	    // Store every value at highest possible precision(10 bit each). h gets the extra 2 bit:
	    int output = ((int)(r*255) << 16) | ((int)(g*255) << 8) | (int)(b*255);
	    return output;
	}
}
