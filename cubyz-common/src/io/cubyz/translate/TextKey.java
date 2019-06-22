package io.cubyz.translate;

import java.util.Objects;

public class TextKey {

	protected String key;
	
	public TextKey(String key) {
		this.key = Objects.requireNonNull(key);
	}
	
	public String getTranslation(Language lang) {
		return lang.translate(this);
	}
	
	public String getTranslateKey() {
		return key;
	}
	
	public String translationOverride(Language lang) {
		return null;
	}
	
}
