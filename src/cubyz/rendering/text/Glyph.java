package cubyz.rendering.text;

/**
 * A simple data holder for the glyph data.
 */
public class Glyph {
	public final float x;
	public final float y;
	public final float width;
	public final float height;
	public final int codepoint;
	public final int charIndex;
	public Glyph(float x, float y, float width, float height, int codepoint, int charIndex) {
		this.x = x;
		this.y = y;
		this.width = width;
		this.height = height;
		this.codepoint = codepoint;
		this.charIndex = charIndex;
		
	}
}
