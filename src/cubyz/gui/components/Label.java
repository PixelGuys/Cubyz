package cubyz.gui.components;

import cubyz.rendering.text.CubyzFont;
import cubyz.rendering.text.Fonts;
import cubyz.rendering.text.TextLine;
import cubyz.utils.translate.TextKey;

/**
 * Just a simple component for text display only.
 */

public class Label extends Component {

	private TextKey text = TextKey.createTextKey("");
	private CubyzFont font = Fonts.PIXEL_FONT;
	private TextLine line;
	private byte textAlign;
	
	public Label() {
		height = 24;
		line = new TextLine(font, text.getTranslation(), height, false);
	}
	
	public Label(CubyzFont font, int textSize) {
		this.font = font;
		height = textSize;
		line = new TextLine(font, text.getTranslation(), height, false);
	}
	
	public Label(String text) {
		this.text = TextKey.createTextKey(text);
		height = 24;
		line = new TextLine(font, this.text.getTranslation(), height, false);
	}
	
	public Label(TextKey text) {
		this.text = text;
		height = 24;
		line = new TextLine(font, text.getTranslation(), height, false);
	}
	
	public TextKey getText() {
		return text;
	}

	public void setText(String text) {
		this.text = TextKey.createTextKey(text);
	}
	
	public void setText(TextKey text) {
		this.text = text;
	}
	/**
	 * How the text is aligned comapred to the label coordinates.
	 * @param align
	 */
	public void setTextAlign(byte align) {
		this.textAlign = align;
	}
	
	public void setFont(CubyzFont font) {
		this.font = font;
		line = new TextLine(font, text.getTranslation(), height, false);
	}
	
	public void setFontSize(float size) {
		height = (int)size;
		line = new TextLine(font, text.getTranslation(), height, false);
	}
	
	@Override
	public void setBounds(int x, int y, int width, int height, byte align) {
		super.setBounds(x, y, width, height, align);
		line = new TextLine(font, text.getTranslation(), height, false);
	}

	@Override
	public void render(int x, int y) {
		line.updateText(text.getTranslation());
		this.width = (int)line.getWidth();
		// Calculate text alignment:
		if ((textAlign & ALIGN_LEFT) != 0) {
			// x = x;
		} else if ((textAlign & ALIGN_RIGHT) != 0) {
			x -= width;
		} else {
			x -= width/2;
		}
		if ((textAlign & ALIGN_TOP) != 0) {
			// y = y;
		} else if ((textAlign & ALIGN_BOTTOM) != 0) {
			y -= height;
		} else {
			y -= height/2;
		}
		line.render(x, y);
	}
	
}