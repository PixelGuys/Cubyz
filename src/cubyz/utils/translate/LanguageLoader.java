package cubyz.utils.translate;

import java.io.File;
import java.io.FileReader;
import java.io.IOException;
import java.util.Objects;
import java.util.Properties;

import cubyz.Logger;
import cubyz.utils.ResourceManager;

/**
 * Loads a language file based on locale.
 */

public class LanguageLoader {

	public static Language load(String locale) {
		locale = Objects.requireNonNull(locale);
		File[] assetsFolders = ResourceManager.listFiles("");
		Language lang = new Language(locale);
		for (File assetFolder : assetsFolders) {
			File langFile = ResourceManager.lookup(assetFolder.getName() + "/lang/" + locale + ".lang");
			if (langFile != null) {
				Properties props = new Properties();
				try {
					FileReader reader = new FileReader(langFile);
					props.load(reader);
					for (Object key : props.keySet()) {
						lang.add(key.toString(), props.getProperty(key.toString()));
					}
					reader.close();
				} catch (IOException e) {
					Logger.severe("Could not open language file " + locale + " for mod " + assetFolder.getName());
					Logger.throwable(e);
				}
			} else if (assetFolder.getName().equals("cubyz")) {
				Logger.warning("Language \"" + locale + "\" not found");
			}
		}
		return lang;
	}
	
}
