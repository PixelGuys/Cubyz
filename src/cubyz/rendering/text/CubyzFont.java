package cubyz.rendering.text;

import java.awt.Color;
import java.awt.Font;
import java.awt.FontFormatException;
import java.awt.FontMetrics;
import java.awt.Graphics2D;
import java.awt.Rectangle;
import java.awt.font.GlyphVector;
import java.awt.image.BufferedImage;
import java.io.File;
import java.io.IOException;
import java.util.HashMap;

import cubyz.utils.Logger;
import cubyz.rendering.Texture;

public class CubyzFont {

	//Graphical variables
	private final Font font;
	private final Font fallbackFont;
	private BufferedImage fontTexture = new BufferedImage(1, 1, BufferedImage.TYPE_INT_ARGB);
	private Texture texture = null;
	public Graphics2D fontGraphics = fontTexture.createGraphics();

	//List of all already used
	private HashMap<Integer, Rectangle> glyphs = new HashMap<Integer, Rectangle>();
	static int num = 0;
	
	/**
	 * Loads a system Font.
	 * @param name
	 */
	public CubyzFont(File file, String fallback, int size) {
		Font font;
		Font fallbackFont = new Font(fallback, Font.PLAIN, size);
		try {
			font = Font.createFonts(file)[0].deriveFont((float) size);
		} catch (FontFormatException | IOException e) {
			font = fallbackFont;
			Logger.warning("Failed to load font " + file.getPath());
			Logger.warning(e);
			e.printStackTrace();
		}
		
		this.font = font;
		this.fallbackFont = fallbackFont;
	}
	
	public int getSize() {
		return font.getSize();
	}
	
	// As of now, this is only used for creating a TextLayout object
	// however it is incapable of handling the case where a character isn't
	// in the font and the fallback font is used.
	// Once the todo in cubyz.rendering.text.PrettyText is fixed, this should be removed
	public Font getFont() {
		return font;
	}
	
	/**
	 * Get the glyph position inside the texture.
	 * @param letter
	 * @return the rectangle bounds of the glyph
	 */
	public Rectangle getGlyph(int letterCode) {
		//does the glyph already exist?
		if (glyphs.containsKey(letterCode))
			return glyphs.get(letterCode);
		
		Font usedFont = font;
		if (!font.canDisplay(letterCode) && false) { // due to missing support in PrettyText, fallback looks quite bad and so is disabled
			usedFont = fallbackFont;
		}

		//letter metrics
		FontMetrics metrics = fontGraphics.getFontMetrics();
		GlyphVector glyphVector = usedFont.createGlyphVector(metrics.getFontRenderContext(), new int[] {letterCode});
		if (glyphVector.getGlyphCode(0) == font.getMissingGlyphCode()) {
			Logger.info("Missing glyph code " + letterCode + " from font");
		}
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
		fontGraphics.drawImage(fontTexture, 0, 0, null);
		//drawing the new letter
		fontGraphics.setFont(usedFont);
		fontGraphics.setColor(Color.white);
		fontGraphics.drawGlyphVector(glyphVector, glyph.x-bounds.x, -bounds.y);
		
		fontTexture = newFontTexture;
		
		if (texture==null)
			texture = Texture.loadFromImage(fontTexture);
		else
			texture.updateTexture(fontTexture);
		
		
		
		glyphs.put(letterCode, glyph);
	    return glyph;
	}
	public void bind() {
		if (texture != null) {
			texture.bind();
		}
	}
	public Texture getTexture() {
		return texture;
	}
}
