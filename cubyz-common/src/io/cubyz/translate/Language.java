package io.cubyz.translate;

import java.util.HashMap;

public class Language {

	private static HashMap<String, String> keyValues = new HashMap<>();
	private String locale;
	
	public Language(String locale) {
		this.locale = locale;
	}
	
	public void add(String key, String text) {
		keyValues.put(key, text);
	}
	
	public void remove(String key) {
		keyValues.remove(key);
	}
	
	public String get(String key) {
		return keyValues.get(key);
	}
	
	public String translate(TextKey key) {
		String override = key.translationOverride(this);
		if (override != null) {
			return override;
		}
		String v = key.getTranslateKey();
		if (keyValues.containsKey(key.getTranslateKey())) {
			v = keyValues.get(key.getTranslateKey());
		}
		return v;
	}
	
	public String getLocale() {
		return locale;
	}
	
}
