package cubyz.rendering.text;

import java.awt.Color;
import java.awt.Composite;
import java.awt.Font;
import java.awt.FontMetrics;
import java.awt.Graphics;
import java.awt.Graphics2D;
import java.awt.GraphicsConfiguration;
import java.awt.Image;
import java.awt.Paint;
import java.awt.Rectangle;
import java.awt.RenderingHints;
import java.awt.Shape;
import java.awt.Stroke;
import java.awt.RenderingHints.Key;
import java.awt.font.FontRenderContext;
import java.awt.font.GlyphVector;
import java.awt.font.TextLayout;
import java.awt.geom.AffineTransform;
import java.awt.image.BufferedImage;
import java.awt.image.BufferedImageOp;
import java.awt.image.ImageObserver;
import java.awt.image.RenderedImage;
import java.awt.image.renderable.RenderableImage;
import java.text.AttributedCharacterIterator;
import java.util.Map;

/**
 * The Graphics2D object that will be inserted into the Textlayout.
 * DO NOT USE FOR ANYTHING ELSE!
 *
 */
class TextLayoutGraphics extends Graphics2D {
	private static TextLayoutGraphics instance = new TextLayoutGraphics();
	private TextLayoutGraphics() {}
	
	static TextLine storage;
	static synchronized void generateGlyphData(TextLayout layout, TextLine storage) {
		TextLayoutGraphics.storage = storage;
		storage.glyphs.clear();
		layout.draw(instance, 0, 0);
	}

	@Override
	public void drawGlyphVector(GlyphVector glyphs, float x, float y) {
		for (int i = 0; i < glyphs.getNumGlyphs(); i++) {
			Rectangle bounds = glyphs.getGlyphPixelBounds(i, storage.font.fontGraphics.getFontRenderContext(), x, y);
			int codepoint = glyphs.getGlyphCode(i);
			int charIndex = glyphs.getGlyphCharIndex(i);
			bounds.y += storage.font.fontGraphics.getFontMetrics().getAscent();
			storage.glyphs.add(new Glyph(bounds.x, bounds.y, bounds.width, bounds.height, codepoint, charIndex));
		}
	}
	
	
	
	
	// --------------------------------------------
	// junkyard:
	
	@Deprecated
	@Override
	public void drawLine(int x1, int y1, int x2, int y2) {
		throw new UnsupportedOperationException();
	}
	@Deprecated
	@Override
	public void addRenderingHints(Map<?, ?> arg0) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void clip(Shape arg0) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void draw(Shape arg0) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public boolean drawImage(Image arg0, AffineTransform arg1, ImageObserver arg2) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void drawImage(BufferedImage arg0, BufferedImageOp arg1, int arg2, int arg3) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void drawRenderableImage(RenderableImage arg0, AffineTransform arg1) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void drawRenderedImage(RenderedImage arg0, AffineTransform arg1) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void drawString(String arg0, int arg1, int arg2) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void drawString(String arg0, float arg1, float arg2) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void drawString(AttributedCharacterIterator arg0, int arg1, int arg2) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void drawString(AttributedCharacterIterator arg0, float arg1, float arg2) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void fill(Shape arg0) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public Color getBackground() {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public Composite getComposite() {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public GraphicsConfiguration getDeviceConfiguration() {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public FontRenderContext getFontRenderContext() {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public Paint getPaint() {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public Object getRenderingHint(Key arg0) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public RenderingHints getRenderingHints() {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public Stroke getStroke() {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public AffineTransform getTransform() {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public boolean hit(Rectangle arg0, Shape arg1, boolean arg2) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void rotate(double arg0) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void rotate(double arg0, double arg1, double arg2) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void scale(double arg0, double arg1) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void setBackground(Color arg0) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void setComposite(Composite arg0) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void setPaint(Paint arg0) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void setRenderingHint(Key arg0, Object arg1) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void setRenderingHints(Map<?, ?> arg0) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void setStroke(Stroke arg0) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void setTransform(AffineTransform arg0) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void shear(double arg0, double arg1) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void transform(AffineTransform arg0) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void translate(int arg0, int arg1) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void translate(double arg0, double arg1) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void clearRect(int arg0, int arg1, int arg2, int arg3) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void clipRect(int arg0, int arg1, int arg2, int arg3) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void copyArea(int arg0, int arg1, int arg2, int arg3, int arg4, int arg5) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public Graphics create() {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void dispose() {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void drawArc(int arg0, int arg1, int arg2, int arg3, int arg4, int arg5) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public boolean drawImage(Image arg0, int arg1, int arg2, ImageObserver arg3) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public boolean drawImage(Image arg0, int arg1, int arg2, Color arg3, ImageObserver arg4) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public boolean drawImage(Image arg0, int arg1, int arg2, int arg3, int arg4, ImageObserver arg5) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public boolean drawImage(Image arg0, int arg1, int arg2, int arg3, int arg4, Color arg5, ImageObserver arg6) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public boolean drawImage(Image arg0, int arg1, int arg2, int arg3, int arg4, int arg5, int arg6, int arg7, int arg8, ImageObserver arg9) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public boolean drawImage(Image arg0, int arg1, int arg2, int arg3, int arg4, int arg5, int arg6, int arg7, int arg8, Color arg9, ImageObserver arg10) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void drawOval(int arg0, int arg1, int arg2, int arg3) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void drawPolygon(int[] arg0, int[] arg1, int arg2) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void drawPolyline(int[] arg0, int[] arg1, int arg2) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void drawRoundRect(int arg0, int arg1, int arg2, int arg3, int arg4, int arg5) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void fillArc(int arg0, int arg1, int arg2, int arg3, int arg4, int arg5) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void fillOval(int arg0, int arg1, int arg2, int arg3) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void fillPolygon(int[] arg0, int[] arg1, int arg2) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void fillRect(int arg0, int arg1, int arg2, int arg3) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void fillRoundRect(int arg0, int arg1, int arg2, int arg3, int arg4, int arg5) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public Shape getClip() {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public Rectangle getClipBounds() {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public Color getColor() {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public FontMetrics getFontMetrics(Font arg0) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void setClip(Shape arg0) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void setClip(int arg0, int arg1, int arg2, int arg3) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void setColor(Color arg0) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void setFont(Font font) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void setPaintMode() {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public void setXORMode(Color arg0) {
		throw new UnsupportedOperationException();
	}

	@Deprecated
	@Override
	public Font getFont() {
		throw new UnsupportedOperationException();
	}
}
