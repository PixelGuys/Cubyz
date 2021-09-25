package cubyz.gui.settings;

import cubyz.client.ClientSettings;
import cubyz.client.Cubyz;
import cubyz.gui.Component;
import cubyz.gui.MenuGUI;
import cubyz.gui.components.Button;
import cubyz.gui.components.CheckBox;
import cubyz.gui.components.Label;
import cubyz.gui.components.Slider;
import cubyz.rendering.Window;
import cubyz.utils.translate.TextKey;

public class GraphicsGUI extends MenuGUI {
	private Button done = new Button();
	private Button fog = new Button();
	private CheckBox easyLighting = new CheckBox();
	private CheckBox vsync = new CheckBox();
	private Label effectiveRenderDistance = new Label();
	private final Slider renderDistance = new Slider(1, 12, ClientSettings.RENDER_DISTANCE);
	private final Slider highestLOD = new Slider(ClientSettings.HIGHEST_LOD, new String[] {"1", "2", "4", "8", "16"});
	private final Slider LODFactor = new Slider(Math.round(ClientSettings.LOD_FACTOR*2) - 1, new String[] {"0.5", "1.0", "1.5", "2.0", "2.5", "3.0", "3.5", "4.0", "4.5", "5.0"});

	private void recalculateERD() {
		ClientSettings.EFFECTIVE_RENDER_DISTANCE = (ClientSettings.RENDER_DISTANCE + ((((int)(ClientSettings.RENDER_DISTANCE*ClientSettings.LOD_FACTOR) & ~1) << ClientSettings.HIGHEST_LOD)));
		effectiveRenderDistance.setText("Effective Render Distance ≈ " + ClientSettings.EFFECTIVE_RENDER_DISTANCE);
	}
	
	@Override
	public void init() {
		done.setBounds(-125, 75, 250, 45, Component.ALIGN_BOTTOM);
		done.setText(TextKey.createTextKey("gui.cubyz.settings.done"));
		done.setFontSize(32f);
		
		done.setOnAction(() -> {
			Cubyz.gameUI.back();
		});
		
		recalculateERD();

		renderDistance.setBounds(-125, 75, 250, 45, Component.ALIGN_TOP);
		renderDistance.setFontSize(16);
		renderDistance.setText("Render Distance: ");
		renderDistance.setOnAction(() -> {
			ClientSettings.RENDER_DISTANCE = renderDistance.getValue();
			recalculateERD();
		});

		highestLOD.setBounds(-125, 150, 250, 45, Component.ALIGN_TOP);
		highestLOD.setFontSize(16);
		highestLOD.setText("Maximum LOD: ");
		highestLOD.setOnAction(() -> {
			ClientSettings.HIGHEST_LOD = highestLOD.getValue();
			recalculateERD();
		});

		LODFactor.setBounds(-125, 225, 250, 45, Component.ALIGN_TOP);
		LODFactor.setFontSize(16);
		LODFactor.setText("LOD Factor: ");
		LODFactor.setOnAction(() -> {
			ClientSettings.LOD_FACTOR = (LODFactor.getValue() + 1)/2.0f;
			recalculateERD();
		});
		
		effectiveRenderDistance.setBounds(0, 300, 0, 16, Component.ALIGN_TOP);

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
		fog.setBounds(-125, 375, 250, 45, Component.ALIGN_TOP);
		fog.setFontSize(32f);

		easyLighting.setPosition(-125, 450, Component.ALIGN_TOP);
		easyLighting.setLabel(TextKey.createTextKey("gui.cubyz.settings.easylighting"));
		easyLighting.setSelected(ClientSettings.easyLighting);
		easyLighting.setOnAction(() -> {
			//ClientSettings.easyLighting = easyLighting.isSelected();
			easyLighting.setSelected(true);
			throw new UnsupportedOperationException("Only easy lighting is supported for now.");
		});
		easyLighting.getLabel().setFontSize(32f);
		
		vsync.setPosition(-125, 525, Component.ALIGN_TOP);
		vsync.setLabel(TextKey.createTextKey("gui.cubyz.settings.vsync"));
		vsync.setSelected(Window.isVSyncEnabled());
		vsync.setOnAction(() -> {
			Window.setVSyncEnabled(vsync.isSelected());
		});
		vsync.getLabel().setFontSize(32f);
	}

	@Override
	public void render() {
		renderDistance.render();
		highestLOD.render();
		LODFactor.render();
		effectiveRenderDistance.render();
		done.render();
		fog.render();
		easyLighting.render();
		vsync.render();
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
