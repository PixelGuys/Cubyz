import java.awt.Color;
import java.awt.image.BufferedImage;
import java.io.File;
import java.io.IOException;
import javax.imageio.ImageIO;

public class GenerateTemplate {
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
		if ( r >= max )
	        h = (g - b) / delta;        // between yellow & magenta
	    else
	    if ( g >= max )
	        h = 2.0 + (b - r) / delta;  // between cyan & yellow
	    else
	        h = 4.0 + (r - g) / delta;  // between magenta & cyan
		
		h *= 60.0;                              // degrees

	    if (h < 0.0)
	        h += 360.0;
	    h /= 360;
		if (h > 1) h = 1;
		if (h < 0) h = 0;
		if (s > 1) s = 1;
		if (s < 0) s = 0;
		if (v > 1) v = 1;
		if (v < 0) v = 0;
	    int output = ((int)(h*255) << 16) | ((int)(s*255) << 8) | (int)(v*255);
	    return output;
	}
	public static BufferedImage getImage(String fileName) {
		try {
			return ImageIO.read(new File(fileName));
		} catch(Exception e) {}//e.printStackTrace();}
		return null;
	}
	public static void main(String[] args) {
		BufferedImage ore = (BufferedImage)getImage(args[0]);
		for(int i = 0; i < 16; i++) {
			for(int j = 0; j < 16; j++) {
				int color = 0x69bfbf;
				int hsv = getHSV(color);
				int colorOre = ore.getRGB(i, j);
				int hsvOre = getHSV(colorOre);
				int a = colorOre >>> 24;
				int h1 = (hsv >>> 16) & 255;
				int s1 = (hsv >>> 8) & 255;
				int v1 = (hsv >>> 0) & 255;
				int h2 = (hsvOre >>> 16) & 255;
				int s2 = (hsvOre >>> 8) & 255;
				int v2 = (hsvOre >>> 0) & 255;
				h2 -= h1;
				s2 -= s1;
				v2 -= v1;
				h2 &= 255;
				if (s2 > 127) s2 = 127;
				if (s2 < -128) s2 = -128;
				s2 &= 255;
				if (v2 > 127) v2 = 127;
				if (v2 < -128) v2 = -128;
				v2 &= 255;
				int res = (a << 24) | (h2 << 16) | (s2 << 8) | v2;
				
				ore.setRGB(i, j, res);
			}
		}
		
		File outputfile = new File("template.png");
		try {
			ImageIO.write(ore, "png", outputfile);
		} catch (IOException e) {}
	}
}
