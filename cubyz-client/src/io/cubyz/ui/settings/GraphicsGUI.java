package io.cubyz.ui.settings;

import io.cubyz.ClientSettings;
import io.cubyz.Settings;
import io.cubyz.client.Cubyz;
import io.cubyz.translate.TextKey;
import io.cubyz.ui.MenuGUI;
import io.cubyz.ui.components.Button;
import io.cubyz.ui.components.CheckBox;
import io.cubyz.ui.components.Label;
import io.cubyz.ui.components.Slider;
import io.jungle.Window;

public class GraphicsGUI extends MenuGUI {
	private Button done = new Button();
	private Button fog = new Button();
	private CheckBox easyLighting = new CheckBox();
	private CheckBox vsync = new CheckBox();
	private Label effectiveRenderDistance = new Label();
	private final Slider renderDistance = new Slider(1, 24, ClientSettings.RENDER_DISTANCE);
	private final Slider maxResolution = new Slider(ClientSettings.MAX_RESOLUTION, new String[] {"16 (no reduced quality chunks are generated)", "8", "4", "2", "1"});
	private final Slider farDistanceFactor = new Slider(Math.round(ClientSettings.FAR_DISTANCE_FACTOR*2) - 1, new String[] {"0.5", "1.0", "1.5", "2.0", "2.5", "3.0", "3.5", "4.0"});

	private void recalculateERD() {
		effectiveRenderDistance.setText("Effective Render Distance ≈ " + (ClientSettings.RENDER_DISTANCE + ((((int)(ClientSettings.RENDER_DISTANCE*ClientSettings.FAR_DISTANCE_FACTOR) & ~1) << ClientSettings.MAX_RESOLUTION))));
	}
	
	@Override
	public void init(long nvg) {
		done.setSize(250, 45);
		done.setText(TextKey.createTextKey("gui.cubyz.settings.done"));
		done.setFontSize(16f);
		
		done.setOnAction(() -> {
			Cubyz.gameUI.back();
		});
		
		effectiveRenderDistance.setFontSize(18);
		recalculateERD();
		
		renderDistance.setSize(250, 45);
		renderDistance.setFontSize(18);
		renderDistance.setText("Render Distance: ");
		renderDistance.setOnAction(() -> {
			ClientSettings.RENDER_DISTANCE = renderDistance.getValue();
			recalculateERD();
		});
		
		maxResolution.setSize(250, 45);
		maxResolution.setFontSize(18);
		maxResolution.setText("Minimal Resolution of chunks: ");
		maxResolution.setOnAction(() -> {
			ClientSettings.MAX_RESOLUTION = maxResolution.getValue();
			recalculateERD();
		});
		
		farDistanceFactor.setSize(250, 45);
		farDistanceFactor.setFontSize(18);
		farDistanceFactor.setText("Scale of effective render distance: ");
		farDistanceFactor.setOnAction(() -> {
			ClientSettings.FAR_DISTANCE_FACTOR = (farDistanceFactor.getValue() + 1)/2.0f;
			recalculateERD();
		});

		if (ClientSettings.FOG_COEFFICIENT == 0f) {
			fog.setText(TextKey.createTextKey("gui.cubyz.settings.fog.off"));
		} else if (ClientSettings.FOG_COEFFICIENT <= 5f) {
			fog.setText(TextKey.createTextKey("gui.cubyz.settings.fog.near"));
		} else if (ClientSettings.FOG_COEFFICIENT > 5f && ClientSettings.FOG_COEFFICIENT < 15f) {
			fog.setText(TextKey.createTextKey("gui.cubyz.settings.fog.med"));
		} else {
			fog.setText(TextKey.createTextKey("gui.cubyz.settings.fog.far"));
		}
		fog.setOnAction(() -> {
			if (ClientSettings.FOG_COEFFICIENT == 0f) { // off
				ClientSettings.FOG_COEFFICIENT = 5f;
				fog.setText(TextKey.createTextKey("gui.cubyz.settings.fog.near"));
			} else if (ClientSettings.FOG_COEFFICIENT <= 5f) { // near
				ClientSettings.FOG_COEFFICIENT = 10f;
				fog.setText(TextKey.createTextKey("gui.cubyz.settings.fog.med"));
			} else if (ClientSettings.FOG_COEFFICIENT > 5f && ClientSettings.FOG_COEFFICIENT < 15f) { // medium
				ClientSettings.FOG_COEFFICIENT = 15f;
				fog.setText(TextKey.createTextKey("gui.cubyz.settings.fog.far"));
			} else { // far
				ClientSettings.FOG_COEFFICIENT = 0f;
				fog.setText(TextKey.createTextKey("gui.cubyz.settings.fog.off"));
			}
		});
		fog.setSize(250, 45);
		fog.setFontSize(16f);
		
		easyLighting.setLabel(TextKey.createTextKey("gui.cubyz.settings.easylighting"));
		easyLighting.setSelected(Settings.easyLighting);
		easyLighting.setOnAction(() -> {
			Settings.easyLighting = easyLighting.isSelected();
		});
		easyLighting.getLabel().setFontSize(16f);
		
		Window win = Cubyz.ctx.getWindow();
		vsync.setLabel(TextKey.createTextKey("gui.cubyz.settings.vsync"));
		vsync.setSelected(win.isVSyncEnabled());
		vsync.setOnAction(() -> {
			win.setVSyncEnabled(vsync.isSelected());
		});
		
		// TODO: slider for RenderDistance.
	}

	@Override
	public void render(long nvg, Window win) {
		renderDistance.setPosition(win.getWidth()/2 - 125, 75);
		maxResolution.setPosition(win.getWidth()/2 - 125, 150);
		farDistanceFactor.setPosition(win.getWidth()/2 - 125, 225);
		effectiveRenderDistance.setPosition(win.getWidth()/2 - 125, 300);
		done.setPosition(win.getWidth()/2 - 125, win.getHeight() - 75);
		fog.setPosition(win.getWidth()/2 - 125, 375);
		easyLighting.setPosition(win.getWidth()/2 - 125, 450);
		vsync.setPosition(win.getWidth()/2 - 125, 525);

		renderDistance.render(nvg, win);
		maxResolution.render(nvg, win);
		farDistanceFactor.render(nvg, win);
		effectiveRenderDistance.render(nvg, win);
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
