package cubyz.rendering.text;

import java.awt.Color;
import java.awt.Font;
import java.awt.FontMetrics;
import java.awt.Graphics2D;
import java.awt.Rectangle;
import java.awt.font.GlyphVector;
import java.awt.image.BufferedImage;
import java.util.HashMap;

import cubyz.rendering.Texture;

public class CubyzFont {
	/**
	 * Loads a system Font.
	 * @param name
	 */
	public CubyzFont(String name, int size) {
		font = new Font(name, Font.PLAIN, size);
	}
	// TODO: Load font from file.
	
	//Graphical variables
	public final Font font;
	private BufferedImage fontTexture = new BufferedImage(1, 1, BufferedImage.TYPE_INT_ARGB);
	private Texture texture = null;
	public Graphics2D fontGraphics = fontTexture.createGraphics();

	//List of all already used
	private HashMap<Integer, Rectangle> glyphs = new HashMap<Integer, Rectangle>();
	static int num = 0;
	/**
	 * Get the glyph position inside the texture.
	 * @param letter
	 * @return the rectangle bounds of the glyph
	 */
	public Rectangle getGlyph(int letterCode) {
		//does the glyph already exist?
		if(glyphs.containsKey(letterCode))
			return glyphs.get(letterCode);

		//letter metrics
		FontMetrics metrics = fontGraphics.getFontMetrics();
		GlyphVector glyphVector = font.createGlyphVector(metrics.getFontRenderContext(), new int[] {letterCode});
		Rectangle bounds = glyphVector.getGlyphPixelBounds(0, metrics.getFontRenderContext(), 0, 0);

		//create the Glyph
		Rectangle glyph = new Rectangle();
		glyph.x = fontTexture.getWidth();
		glyph.width = bounds.width;
		glyph.height = bounds.height;
		
		// Paint the new glyph in the texture:
		
		//make the fontTexture bigger.
		fontGraphics.dispose();
		BufferedImage newFontTexture = new BufferedImage(fontTexture.getWidth()+glyph.width, metrics.getHeight(), BufferedImage.TYPE_INT_ARGB);
		fontGraphics = newFontTexture.createGraphics();
		
		//drawing the old stuff
		fontGraphics.drawImage(fontTexture,0,0,null);
		//drawing the new letter
		fontGraphics.setFont(font);
		fontGraphics.setColor(Color.white);
		fontGraphics.drawGlyphVector(glyphVector, glyph.x-bounds.x,-bounds.y);
		
		fontTexture = newFontTexture;
		
		if(texture==null)
			texture = Texture.loadFromImage(fontTexture);
		else
			texture.updateTexture(fontTexture);
		
		
		
		glyphs.put(letterCode, glyph);
	    return glyph;
	}
	public void bind() {
		if(texture != null) {
			texture.bind();
		}
	}
	public Texture getTexture() {
		return texture;
	}
}
