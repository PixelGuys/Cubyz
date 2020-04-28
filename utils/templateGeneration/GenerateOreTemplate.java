import java.awt.Color;
import java.awt.image.BufferedImage;
import java.io.File;
import java.io.IOException;
import javax.imageio.ImageIO;

public class GenerateOreTemplate {
	public static BufferedImage getImage(String fileName) {
		try {
			return ImageIO.read(new File(fileName));
		} catch(Exception e) {e.printStackTrace();}
		return null;
	}
	public static void main(String[] args) {
		// Algorithm for automatically generating an ore template from the ore image. Uses the reverse-engineered color erase algorithm from gimp.
		BufferedImage stone = getImage(args[2]);
		BufferedImage ore = getImage(args[0]);
		for(int i = 0; i < 16; i++) {
			for(int j = 0; j < 16; j++) {
				int colorStone = stone.getRGB(i, j);
				int bS = colorStone & 255;
				int gS = (colorStone >> 8) & 255;
				int rS = (colorStone >> 16) & 255;
				int colorOre = ore.getRGB(i, j);
				int bO = colorOre & 255;
				int gO = (colorOre >> 8) & 255;
				int rO = (colorOre >> 16) & 255;
				
				// Color erase algorithm:
				// O = a*I+(1-a)*S → a*(I-S) = O-S → a = (O-S)/(I-S)
				int ar, ag, ab;
				if(rO == rS) {
					ar = 0;
				} else if(rO < rS) {
					ar = -255*(rO-rS)/rS;
				} else {
					ar = 255*(rO-rS)/(255-rS);
				}
				if(gO == gS) {
					ag = 0;
				} else if(gO < gS) {
					ag = -255*(gO-gS)/gS;
				} else {
					ag = 255*(gO-gS)/(255-gS);
				}
				if(bO == bS) {
					ab = 0;
				} else if(bO < bS) {
					ab = -255*(bO-bS)/bS;
				} else {
					ab = 255*(bO-bS)/(255-bS);
				}
				// O = a*I+(1-a)*S → a*I = O+(a-1)*S → I = O/a+S-S/a
				int a = Math.max(ar, Math.max(ag,  ab)); // Erase as much color as possible.
				if(a >= 255) a = 255;
				if(a < 0) a = 0;
				int rI, gI, bI;
				if(a == 0) {
					rI = gI = bI = 0;
				} else {
					rI = 255*rO/a+rS-255*rS/a;
					gI = 255*gO/a+gS-255*gS/a;
					bI = 255*bO/a+bS-255*bS/a;
					if(rI < 0) rI = 0;
					if(rI > 255) rI = 255;
					if(gI < 0) gI = 0;
					if(gI > 255) gI = 255;
					if(bI < 0) bI = 0;
					if(bI > 255) bI = 255;
				}
				
				ore.setRGB(i, j, new Color(rI, gI, bI, a).getRGB());
			}
			File outputfile = new File(args[1]);
			try {
				ImageIO.write(ore, "png", outputfile);
			} catch (IOException e) {}
		}
	}
}
