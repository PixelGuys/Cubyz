package cubyz.gui.settings;

import java.io.File;
import java.util.ArrayList;

import cubyz.Settings;
import cubyz.client.Cubyz;
import cubyz.gui.Component;
import cubyz.gui.MenuGUI;
import cubyz.gui.components.Button;
import cubyz.utils.DiscordIntegration;
import cubyz.utils.ResourceManager;
import cubyz.utils.translate.ContextualTextKey;
import cubyz.utils.translate.LanguageLoader;
import cubyz.utils.translate.TextKey;

public class SettingsGUI extends MenuGUI {

	private final Button done = new Button();
	private final Button graphics = new Button();
	private final Button language = new Button();
	private final Button rpc = new Button();
	private final Button bindings = new Button();
	
	private ContextualTextKey langKey = new ContextualTextKey("gui.cubyz.settings.language", "lang.name");
	private ContextualTextKey rpcKeyOn = new ContextualTextKey("gui.cubyz.settings.discord", "gui.cubyz.general.on");
	private ContextualTextKey rpcKeyOff = new ContextualTextKey("gui.cubyz.settings.discord", "gui.cubyz.general.off");
	
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
				}
			}
		}
		languages = languageFiles.toArray(new String[0]);
		
		done.setBounds(-125, 75, 250, 45, Component.ALIGN_BOTTOM);
		done.setText(TextKey.createTextKey("gui.cubyz.settings.done"));
		done.setFontSize(16f);
		
		done.setOnAction(() -> {
			Cubyz.gameUI.back();
		});
		
		graphics.setBounds(-125, 75, 250, 45, Component.ALIGN_TOP);
		graphics.setText(TextKey.createTextKey("gui.cubyz.settings.graphics"));
		graphics.setFontSize(16f);
		
		graphics.setOnAction(() -> {
			Cubyz.gameUI.setMenu(new GraphicsGUI());
		});

		bindings.setBounds(-125, 300, 250, 45, Component.ALIGN_TOP);
		bindings.setText(TextKey.createTextKey("gui.cubyz.settings.keybindings"));
		bindings.setFontSize(16f);
		
		bindings.setOnAction(() -> {
			Cubyz.gameUI.setMenu(new KeybindingsGUI());
		});

		language.setBounds(-125, 150, 250, 45, Component.ALIGN_TOP);
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

		rpc.setBounds(-125, 225, 250, 45, Component.ALIGN_TOP);
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
	public void render(long nvg) {
		rpc.setText(DiscordIntegration.isEnabled() ? rpcKeyOn : rpcKeyOff);

		done.render(nvg);
		graphics.render(nvg);
		language.render(nvg);
		rpc.render(nvg);
		bindings.render(nvg);
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
