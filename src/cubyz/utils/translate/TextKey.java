package cubyz.utils.translate;

import java.util.Objects;

import cubyz.Settings;
import cubyz.utils.datastructures.Tree;

/**
 * A Translation key which is changed every time the language is changed.
 */

public class TextKey {

	protected final String key;
	protected String translation;
	
	protected TextKey(String key) {
		this.key = Objects.requireNonNull(key);
		if (Settings.getLanguage() != null) {
			Settings.getLanguage().translate(this);
		} else {
			translation = key;
		}
	}
	
	public String getTranslation() {
		return translation;
	}
	
	public String getTranslateKey() {
		return key;
	}
	
	// Store the TextKeys in a tree, so access times are low and languages can be cached in the TextKeys:
	public static Tree<String, TextKey> textKeys = new Tree<String, TextKey>();
	public static TextKey createTextKey(String key) {
		if (!key.contains(".")) return new TextKey(key); // Don't store it if this is no real text key
		return textKeys.getOrAdd(key.split("\\."), () -> new TextKey(key));
	}
	
	public static void updateLanguage() {
		// Updates the language of all TextKeys:
		textKeys.foreach((key) -> {
			if (Settings.getLanguage() != null) {
				Settings.getLanguage().translate(key);
			} else {
				key.translation = key.key;
			}
		});
	}
}
