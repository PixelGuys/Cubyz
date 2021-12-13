package cubyz.utils.datastructures;

import java.awt.image.BufferedImage;

/**
 * Some useful methods for generating graphics.
 */

public class PixelUtils {
	
	/**
	 * Colors a template image.
	 * @param template
	 * @param color
	 */
	public static void convertTemplate(BufferedImage template, int color) {
		color |= 0x1f1f1f; // Prevent overflows.
		int hsv = getHSV(color);
		int h1 =  (hsv >>> 16) & 255;
		int s1 = (hsv >>> 8) & 255;
		int v1 = (hsv >>> 0) & 255;
		for(int x = 0; x < template.getWidth(); x++) {
			for(int y = 0; y < template.getHeight(); y++) {
				int hsvTemp = template.getRGB(x, y);
				int a = hsvTemp >>> 24;
				int h2 =  (hsvTemp >>> 16) & 255;
				// Make sure the sign of the saturation and value parameters is correct:
				int s2 = (hsvTemp >>> 8) & 255;
				if (s2 >= 128) s2 |= 0xffffff00;
				int v2 = (hsvTemp >>> 0) & 255;
				if (v2 >= 128) v2 |= 0xffffff00;
				h2 += h1;
				s2 += s1;
				v2 += v1;
				h2 &= 255;
				// Make sure there are no jumps in saturation or value:
				s2 = Math.max(0, Math.min(s2, 255));
				v2 = Math.max(0, Math.min(v2, 255));
				int resHSV = (h2 << 16) | (s2 << 8) | v2;
				template.setRGB(x, y, getRGB(resHSV) | (a << 24));
			}
		}
	}
	
	/**
	 * Converts rgb int to hsv int.
	 * @param rgb
	 * @return hsv
	 */
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

	/**
	 * Converts hsv int to rgb int.
	 * @param hsv
	 * @return rgb
	 */
	public static int getRGB(int hsv) {
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
		if (r > 1) r = 1;
		if (r < 0) r = 0;
		if (g > 1) g = 1;
		if (g < 0) g = 0;
		if (b > 1) b = 1;
		if (b < 0) b = 0;
	    // Store every value at highest possible precision(10 bit each). h gets the extra 2 bit:
	    int output = ((int)(r*255) << 16) | ((int)(g*255) << 8) | (int)(b*255);
	    return output;
	}
}
