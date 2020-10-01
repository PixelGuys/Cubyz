package io.cubyz.ui.components;

import io.cubyz.translate.TextKey;
import io.cubyz.ui.Component;
import io.cubyz.ui.NGraphics;
import io.jungle.Window;
import io.jungle.hud.Font;

public class Label extends Component {

	private Font font = new Font("Default", 12.f);
	private TextKey text = TextKey.createTextKey("");
	
	public Label() {}
	
	public Label(String text) {
		this.text = TextKey.createTextKey(text);
	}
	
	public Label(TextKey text) {
		this.text = text;
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

	public Font getFont() {
		return font;
	}
	
	public void setFont(Font font) {
		this.font = font;
	}
	
	public void setFontSize(float size) {
		font = new Font("Default", size);
	}

	@Override
	public void render(long nvg, Window src) {
		NGraphics.setColor(255, 255, 255);
		NGraphics.setFont(font);
		if (text != null) {
			NGraphics.drawText(x, y, text.getTranslation());
		}
	}
	
}