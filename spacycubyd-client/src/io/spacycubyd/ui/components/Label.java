package io.spacycubyd.ui.components;

import org.jungle.Window;

import io.spacycubyd.ui.Component;
import io.spacycubyd.ui.NGraphics;
import io.spacycubyd.ui.UISystem;

public class Label extends Component {

	private String fontName = UISystem.OPENSANS;
	private float fontSize = 12.f;
	private String text = "";
	
	public String getText() {
		return text;
	}

	public void setText(String text) {
		this.text = text;
	}

	public String getFontName() {
		return fontName;
	}
	
	public void setFontName(String fontName) {
		this.fontName = fontName;
	}
	
	public float getFontSize() {
		return fontSize;
	}
	
	public void setFontSize(float fontSize) {
		this.fontSize = fontSize;
	}

	@Override
	public void render(long nvg, Window src) {
		NGraphics.setFont(fontName, fontSize);
		NGraphics.drawText(x, y, text);
	}
	
	
	
}
