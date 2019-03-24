package io.cubyz.ui.components;

import org.jungle.Window;
import org.jungle.hud.Font;

import io.cubyz.ui.Component;
import io.cubyz.ui.NGraphics;

public class Label extends Component {

	private Font font = new Font("OpenSans Bold", 12.f);
	private String text = "";
	
	public String getText() {
		return text;
	}

	public void setText(String text) {
		this.text = text;
	}

	public Font getFont() {
		return font;
	}
	
	public void setFont(Font font) {
		this.font = font;
	}

	@Override
	public void render(long nvg, Window src) {
		NGraphics.setFont(font);
		NGraphics.drawText(x, y, text);
	}
	
}