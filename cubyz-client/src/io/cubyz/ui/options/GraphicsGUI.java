package io.cubyz.ui.options;

import io.cubyz.ClientSettings;
import io.cubyz.Settings;
import io.cubyz.client.Cubyz;
import io.cubyz.translate.TextKey;
import io.cubyz.ui.MenuGUI;
import io.cubyz.ui.components.Button;
import io.cubyz.ui.components.CheckBox;
import io.jungle.Window;

public class GraphicsGUI extends MenuGUI {
	private Button done = new Button();
	private Button fog = new Button();
	private CheckBox easyLighting = new CheckBox();
	private CheckBox vsync = new CheckBox();

	@Override
	public void init(long nvg) {
		done.setSize(250, 45);
		done.setText(new TextKey("gui.cubyz.options.done"));
		done.setFontSize(16f);
		
		done.setOnAction(() -> {
			Cubyz.gameUI.back();
		});

		if (ClientSettings.FOG_COEFFICIENT == 0f) {
			fog.setText(new TextKey("gui.cubyz.options.fog.off"));
		} else if (ClientSettings.FOG_COEFFICIENT <= 5f) {
			fog.setText(new TextKey("gui.cubyz.options.fog.near"));
		} else if (ClientSettings.FOG_COEFFICIENT > 5f && ClientSettings.FOG_COEFFICIENT < 15f) {
			fog.setText(new TextKey("gui.cubyz.options.fog.med"));
		} else {
			fog.setText(new TextKey("gui.cubyz.options.fog.far"));
		}
		fog.setOnAction(() -> {
			if (ClientSettings.FOG_COEFFICIENT == 0f) { // off
				ClientSettings.FOG_COEFFICIENT = 5f;
				fog.setText(new TextKey("gui.cubyz.options.fog.near"));
			} else if (ClientSettings.FOG_COEFFICIENT <= 5f) { // near
				ClientSettings.FOG_COEFFICIENT = 10f;
				fog.setText(new TextKey("gui.cubyz.options.fog.med"));
			} else if (ClientSettings.FOG_COEFFICIENT > 5f && ClientSettings.FOG_COEFFICIENT < 15f) { // medium
				ClientSettings.FOG_COEFFICIENT = 15f;
				fog.setText(new TextKey("gui.cubyz.options.fog.far"));
			} else { // far
				ClientSettings.FOG_COEFFICIENT = 0f;
				fog.setText(new TextKey("gui.cubyz.options.fog.off"));
			}
		});
		fog.setSize(250, 45);
		fog.setFontSize(16f);
		
		easyLighting.setLabel(new TextKey("gui.cubyz.options.easylighting"));
		easyLighting.setSelected(Settings.easyLighting);
		easyLighting.setOnAction(() -> {
			Settings.easyLighting = easyLighting.isSelected();
		});
		easyLighting.getLabel().setFontSize(16f);
		
		Window win = Cubyz.ctx.getWindow();
		vsync.setLabel(new TextKey("gui.cubyz.options.vsync"));
		vsync.setSelected(win.isVSyncEnabled());
		vsync.setOnAction(() -> {
			win.setVSyncEnabled(vsync.isSelected());
		});
		
		// TODO: slider for RenderDistance.
	}

	@Override
	public void render(long nvg, Window win) {
		done.setPosition(win.getWidth() / 2 - 125, win.getHeight() - 75);
		fog.setPosition(win.getWidth() / 2 - 125, 75);
		easyLighting.setPosition(win.getWidth() / 2 - 125, 150);
		vsync.setPosition(win.getWidth() / 2 - 125, 225);

		done.render(nvg, win);
		fog.render(nvg, win);
		easyLighting.render(nvg, win);
		vsync.render(nvg, win);
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
