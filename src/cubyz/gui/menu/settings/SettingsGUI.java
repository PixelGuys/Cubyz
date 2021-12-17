package cubyz.gui.menu.settings;

import java.io.File;
import java.util.ArrayList;

import cubyz.Settings;
import cubyz.client.Cubyz;
import cubyz.gui.MenuGUI;
import cubyz.gui.components.Button;
import cubyz.gui.components.Component;
import cubyz.utils.DiscordIntegration;
import cubyz.utils.ResourceManager;
import cubyz.utils.translate.ContextualTextKey;
import cubyz.utils.translate.LanguageLoader;
import cubyz.utils.translate.TextKey;

import static cubyz.client.ClientSettings.GUI_SCALE;

public class SettingsGUI extends MenuGUI {

	private final Button done = new Button();
	private final Button graphics = new Button();
	private final Button sound = new Button();
	private final Button language = new Button();
	private final Button rpc = new Button();
	private final Button bindings = new Button();
	
	private ContextualTextKey langKey = new ContextualTextKey("gui.cubyz.settings.language", "lang.name");
	private ContextualTextKey rpcKeyOn = new ContextualTextKey("gui.cubyz.settings.discord", "gui.cubyz.general.on");
	private ContextualTextKey rpcKeyOff = new ContextualTextKey("gui.cubyz.settings.discord", "gui.cubyz.general.off");
	
	private String[] languages;
	
	@Override
	public void init() {
		// Dynamically load the list of languages:
		File[] assetsFolders = ResourceManager.listFiles("");
		ArrayList<String> languageFiles = new ArrayList<>();
		for (File assetFolder : assetsFolders) {
			File langFolder = ResourceManager.lookup(assetFolder.getName() + "/lang");
			if (langFolder == null) continue;
			iteratingLangFiles:
			for(File langFile : langFolder.listFiles()) {
				if (langFile.getName().endsWith(".lang")) {
					String name = langFile.getName().replace(".lang", "");
					// Check if this language is already in the list:
					for(String alreadyListed : languageFiles) {
						if (alreadyListed.equals(name)) continue iteratingLangFiles;
					}
					languageFiles.add(name);
				}
			}
		}
		languages = languageFiles.toArray(new String[0]);
		
		done.setText(TextKey.createTextKey("gui.cubyz.settings.done"));
		done.setOnAction(() -> {
			Cubyz.gameUI.back();
		});
		
		graphics.setText(TextKey.createTextKey("gui.cubyz.settings.graphics"));
		graphics.setOnAction(() -> {
			Cubyz.gameUI.setMenu(new GraphicsGUI());
		});

		sound.setText(TextKey.createTextKey("gui.cubyz.settings.sound"));
		sound.setOnAction(() -> {
			Cubyz.gameUI.setMenu(new SoundGUI());
		});

		bindings.setText(TextKey.createTextKey("gui.cubyz.settings.keybindings"));
		bindings.setOnAction(() -> {
			Cubyz.gameUI.setMenu(new KeybindingsGUI());
		});

		language.setText(langKey);
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
		
		rpc.setOnAction(() -> {
			if (DiscordIntegration.isEnabled()) {
				DiscordIntegration.closeRPC();
			} else {
				DiscordIntegration.startRPC();
			}
		});
		
		updateGUIScale();
	}

	@Override
	public void updateGUIScale() {
		done.setBounds(-125 * GUI_SCALE, 40 * GUI_SCALE, 250 * GUI_SCALE, 25 * GUI_SCALE, Component.ALIGN_BOTTOM);
		done.setFontSize(16f * GUI_SCALE);
		
		graphics.setBounds(-125 * GUI_SCALE, 40 * GUI_SCALE, 250 * GUI_SCALE, 25 * GUI_SCALE, Component.ALIGN_TOP);
		graphics.setFontSize(16f * GUI_SCALE);

		sound.setBounds(-125 * GUI_SCALE, 80 * GUI_SCALE, 250 * GUI_SCALE, 25 * GUI_SCALE, Component.ALIGN_TOP);
		sound.setFontSize(16f * GUI_SCALE);

		bindings.setBounds(-125 * GUI_SCALE, 200 * GUI_SCALE, 250 * GUI_SCALE, 25 * GUI_SCALE, Component.ALIGN_TOP);
		bindings.setFontSize(16f * GUI_SCALE);

		language.setBounds(-125 * GUI_SCALE, 120 * GUI_SCALE, 250 * GUI_SCALE, 25 * GUI_SCALE, Component.ALIGN_TOP);
		language.setFontSize(16f * GUI_SCALE);

		rpc.setBounds(-125 * GUI_SCALE, 160 * GUI_SCALE, 250 * GUI_SCALE, 25 * GUI_SCALE, Component.ALIGN_TOP);
		rpc.setFontSize(16f * GUI_SCALE);
	}

	@Override
	public void render() {
		rpc.setText(DiscordIntegration.isEnabled() ? rpcKeyOn : rpcKeyOff);

		done.render();
		graphics.render();
		sound.render();
		language.render();
		rpc.render();
		bindings.render();
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
