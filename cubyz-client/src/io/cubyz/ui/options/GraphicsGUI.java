package io.cubyz.ui.options;

import io.cubyz.Settings;
import io.cubyz.client.Cubyz;
import io.cubyz.translate.TextKey;
import io.cubyz.ui.MenuGUI;
import io.cubyz.ui.components.Button;
import io.jungle.Window;

public class GraphicsGUI extends MenuGUI {
	private Button done = new Button();
	private Button fog = new Button();
	private Button easyLighting = new Button();

	@Override
	public void init(long nvg) {
		done.setSize(250, 45);
		done.setText(new TextKey("gui.cubyz.options.done"));
		done.setFontSize(16f);
		
		done.setOnAction(() -> {
			Cubyz.gameUI.back();
		});

		if (Settings.fogCoefficient == 0f) {
			fog.setText(new TextKey("gui.cubyz.options.fog.off"));
		} else if (Settings.fogCoefficient <= 5f) {
			fog.setText(new TextKey("gui.cubyz.options.fog.near"));
		} if (Settings.fogCoefficient > 5f && Settings.fogCoefficient < 15f) {
			fog.setText(new TextKey("gui.cubyz.options.fog.med"));
		} else {
			fog.setText(new TextKey("gui.cubyz.options.fog.far"));
		}
		fog.setOnAction(() -> {
			if (Settings.fogCoefficient == 0f) { // off
				Settings.fogCoefficient = 5f;
				fog.setText(new TextKey("gui.cubyz.options.fog.near"));
			} else if (Settings.fogCoefficient <= 5f) { // near
				Settings.fogCoefficient = 10f;
				fog.setText(new TextKey("gui.cubyz.options.fog.med"));
			} else if (Settings.fogCoefficient > 5f && Settings.fogCoefficient < 15f) { // medium
				Settings.fogCoefficient = 15f;
				fog.setText(new TextKey("gui.cubyz.options.fog.far"));
			} else { // far
				Settings.fogCoefficient = 0f;
				fog.setText(new TextKey("gui.cubyz.options.fog.off"));
			}
		});
		fog.setSize(250, 45);
		fog.setFontSize(16f);
		
		if (Settings.easyLighting) {
			easyLighting.setText(new TextKey("gui.cubyz.options.easylighting.on"));
		} else {
			easyLighting.setText(new TextKey("gui.cubyz.options.easylighting.off"));
		}
		easyLighting.setOnAction(() -> {
			Settings.easyLighting = !Settings.easyLighting;
			if (Settings.easyLighting) {
				easyLighting.setText(new TextKey("gui.cubyz.options.easylighting.on"));
			} else {
				easyLighting.setText(new TextKey("gui.cubyz.options.easylighting.off"));
			}
		});
		easyLighting.setSize(250, 45);
		easyLighting.setFontSize(16f);
		
		// TODO: slider for RenderDistance.
	}

	@Override
	public void render(long nvg, Window win) {
		done.setPosition(win.getWidth() / 2 - 125, win.getHeight() - 75);
		fog.setPosition(win.getWidth() / 2 - 125, 75);
		easyLighting.setPosition(win.getWidth() / 2 - 125, 150);

		done.render(nvg, win);
		fog.render(nvg, win);
		easyLighting.render(nvg, win);
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
