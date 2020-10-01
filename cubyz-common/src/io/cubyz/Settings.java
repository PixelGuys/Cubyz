package io.cubyz;

import io.cubyz.translate.Language;
import io.cubyz.translate.TextKey;

// Stores all things that can be changed using settings.

public class Settings {
	
	public static boolean easyLighting = true; // Enables the easy-lighting system.
	
	private static Language currentLanguage = null;
	public static void setLanguage(Language lang) {
		currentLanguage = lang;
		TextKey.updateLanguage();
	}
	public static Language getLanguage() {
		return currentLanguage;
	}
	
}
