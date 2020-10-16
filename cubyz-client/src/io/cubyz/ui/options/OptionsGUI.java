package io.cubyz.ui.options;

import java.io.File;
import java.util.ArrayList;

import io.cubyz.Settings;
import io.cubyz.client.Cubyz;
import io.cubyz.translate.ContextualTextKey;
import io.cubyz.translate.LanguageLoader;
import io.cubyz.translate.TextKey;
import io.cubyz.ui.MenuGUI;
import io.cubyz.ui.components.Button;
import io.cubyz.utils.DiscordIntegration;
import io.cubyz.utils.ResourceManager;
import io.jungle.Window;

public class OptionsGUI extends MenuGUI {

	private final Button done = new Button();
	private final Button graphics = new Button();
	private final Button language = new Button();
	private final Button rpc = new Button();
	private final Button bindings = new Button();
	
	private ContextualTextKey langKey = new ContextualTextKey("gui.cubyz.options.language", "lang.name");
	private ContextualTextKey rpcKeyOn = new ContextualTextKey("gui.cubyz.options.discord", "gui.cubyz.general.on");
	private ContextualTextKey rpcKeyOff = new ContextualTextKey("gui.cubyz.options.discord", "gui.cubyz.general.off");
	
	private String[] languages;
	
	@Override
	public void init(long nvg) {
		// Dynamically load the list of languages:
		File[] assetsFolders = ResourceManager.listFiles("");
		ArrayList<String> languageFiles = new ArrayList<>();
		for (File assetFolder : assetsFolders) {
			File langFolder = ResourceManager.lookup(assetFolder.getName() + "/lang");
			if(langFolder == null) continue;
			iteratingLangFiles:
			for(File langFile : langFolder.listFiles()) {
				if(langFile.getName().endsWith(".lang")) {
					String name = langFile.getName().replace(".lang", "");
					// Check if this language is already in the list:
					for(String alreadyListed : languageFiles) {
						if(alreadyListed.equals(name)) continue iteratingLangFiles;
					}
					languageFiles.add(name);
					System.out.println(name);
				}
			}
		}
		languages = languageFiles.toArray(new String[0]);
		
		done.setSize(250, 45);
		done.setText(TextKey.createTextKey("gui.cubyz.options.done"));
		done.setFontSize(16f);
		
		done.setOnAction(() -> {
			Cubyz.gameUI.back();
		});
		
		graphics.setSize(250, 45);
		graphics.setText(TextKey.createTextKey("gui.cubyz.options.graphics"));
		graphics.setFontSize(16f);
		
		graphics.setOnAction(() -> {
			Cubyz.gameUI.setMenu(new GraphicsGUI());
		});
		
		bindings.setSize(250, 45);
		bindings.setText(TextKey.createTextKey("gui.cubyz.options.keybindings"));
		bindings.setFontSize(16f);
		
		bindings.setOnAction(() -> {
			Cubyz.gameUI.setMenu(new KeybindingsGUI());
		});
		
		language.setSize(250, 45);
		language.setText(langKey);
		language.setFontSize(16f);
		
		language.setOnAction(() -> {
			int index = -1;
			for (int i = 0; i < languages.length; i++) {
				if (languages[i].equals(Settings.getLanguage().getLocale())) {
					index = i;
					break;
				}
			}
			index++;
			if (index >= languages.length) index = 0;
			Settings.setLanguage(LanguageLoader.load(languages[index]));
		});
		
		rpc.setSize(250, 45);
		rpc.setFontSize(16f);
		
		rpc.setOnAction(() -> {
			if (DiscordIntegration.isEnabled()) {
				DiscordIntegration.closeRPC();
			} else {
				DiscordIntegration.startRPC();
			}
		});
		
	}

	@Override
	public void render(long nvg, Window win) {
		done.setPosition(win.getWidth() / 2 - 125, win.getHeight() - 75);
		graphics.setPosition(win.getWidth() / 2 - 125, 75);
		language.setPosition(win.getWidth() / 2 - 125, 150);
		rpc.setPosition(win.getWidth() / 2 - 125, 225);
		bindings.setPosition(win.getWidth() / 2 - 125, 300);

		rpc.setText(DiscordIntegration.isEnabled() ? rpcKeyOn : rpcKeyOff);

		done.render(nvg, win);
		graphics.render(nvg, win);
		language.render(nvg, win);
		rpc.render(nvg, win);
		bindings.render(nvg, win);
	}
	
	@Override
	public boolean ungrabsMouse() {
		return true;
	}

	@Override
	public boolean doesPauseGame() {
		return true;
	}

}
