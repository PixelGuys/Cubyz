package io.cubyz.translate;

import java.util.HashMap;

import static io.cubyz.CubyzLogger.logger;

public class Language {

	private HashMap<String, String> keyValues = new HashMap<>();
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
	
	public void translate(TextKey key) {
		if (keyValues.containsKey(key.getTranslateKey())) {
			key.translation = keyValues.get(key.getTranslateKey());
			return;
		}
		if(key.getTranslateKey().contains("."))
			logger.warning("Unable to translate key "+key.getTranslateKey()+" in language "+locale+".");
		key.translation = key.getTranslateKey();
	}
	
	public String getLocale() {
		return locale;
	}
	
}
