package cubyz.utils.translate;

import java.io.File;
import java.io.FileReader;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Objects;
import java.util.Properties;

import cubyz.utils.Logger;
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
			loadLangFile(assetFolder, lang, langFile);
		}
		return lang;
	}

	public static Language loadFallbackLang(String worldAssetPath) {
		Language lang = new Language("fallback");
		loadLangFile(new File(worldAssetPath), lang, new File(worldAssetPath + "cubyz/lang/fallback.lang"));
		return lang;
	}

	private static void loadLangFile(File assetFolder, Language lang, File langFile) {
		if (langFile != null) {
			Properties props = new Properties();
			try {
				FileReader reader = new FileReader(langFile, StandardCharsets.UTF_8);
				props.load(reader);
				for (Object key : props.keySet()) {
					lang.add(key.toString(), props.getProperty(key.toString()));
				}
				reader.close();
			} catch (IOException e) {
				Logger.error("Could not open language file " + lang.getLocale() + " for mod " + assetFolder.getName());
				Logger.error(e);
			}
		} else if (assetFolder.getName().equals("cubyz")) {
			Logger.warning("Language \"" + lang.getLocale() + "\" not found");
		}
	}
}
