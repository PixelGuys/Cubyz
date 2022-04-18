package cubyz.gui.menu.settings;

import cubyz.client.ClientSettings;
import cubyz.client.Cubyz;
import cubyz.gui.MenuGUI;
import cubyz.gui.components.Button;
import cubyz.gui.components.CheckBox;
import cubyz.gui.components.Component;
import cubyz.gui.components.Label;
import cubyz.gui.components.Slider;
import cubyz.rendering.Graphics;
import cubyz.rendering.Window;
import cubyz.utils.translate.TextKey;

import static cubyz.client.ClientSettings.GUI_SCALE;

public class GraphicsGUI extends MenuGUI {
	private Button done = new Button();
	private Button fog = new Button();
	private CheckBox bloom = new CheckBox();
	private CheckBox vsync = new CheckBox();
	private Label effectiveRenderDistance = new Label();
	private final Slider renderDistance = new Slider(1, 12, ClientSettings.RENDER_DISTANCE);
	private final Slider LODFactor = new Slider(Math.round(ClientSettings.LOD_FACTOR*2) - 1, new String[] {"0.5", "1.0", "1.5", "2.0", "2.5", "3.0", "3.5", "4.0", "4.5", "5.0", "5.5", "6.0", "6.5", "7.0", "7.5", "8.0"});

	private void recalculateERD() {
		ClientSettings.EFFECTIVE_RENDER_DISTANCE = ClientSettings.calculatedEffectiveRenderDistance();
		effectiveRenderDistance.setText("Effective Render Distance ≈ " + ClientSettings.EFFECTIVE_RENDER_DISTANCE);
	}
	
	@Override
	public void init() {
		done.setText(TextKey.createTextKey("gui.cubyz.settings.done"));
		
		done.setOnAction(() -> {
			Cubyz.gameUI.back();
		});
		
		recalculateERD();


		renderDistance.setText("Render Distance: ");
		renderDistance.setOnAction(() -> {
			ClientSettings.RENDER_DISTANCE = renderDistance.getValue();
			recalculateERD();
		});

		LODFactor.setText("LOD Factor: ");
		LODFactor.setOnAction(() -> {
			ClientSettings.LOD_FACTOR = (LODFactor.getValue() + 1)/2.0f;
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

		bloom.setLabel(TextKey.createTextKey("gui.cubyz.settings.bloom"));
		bloom.setSelected(ClientSettings.BLOOM);
		bloom.setOnAction(() -> {
			ClientSettings.BLOOM = bloom.isSelected();
		});
		
		vsync.setLabel(TextKey.createTextKey("gui.cubyz.settings.vsync"));
		vsync.setSelected(Window.isVSyncEnabled());
		vsync.setOnAction(() -> {
			Window.setVSyncEnabled(vsync.isSelected());
		});

		updateGUIScale();
	}

	@Override
	public void updateGUIScale() {
		done.setBounds(-125 * GUI_SCALE, 40 * GUI_SCALE, 250 * GUI_SCALE, 25 * GUI_SCALE, Component.ALIGN_BOTTOM);
		done.setFontSize(16f * GUI_SCALE);

		renderDistance.setBounds(-125 * GUI_SCALE, 40 * GUI_SCALE, 250 * GUI_SCALE, 30 * GUI_SCALE, Component.ALIGN_TOP);
		renderDistance.setFontSize(16 * GUI_SCALE);

		LODFactor.setBounds(-125 * GUI_SCALE, 120 * GUI_SCALE, 250 * GUI_SCALE, 30 * GUI_SCALE, Component.ALIGN_TOP);
		LODFactor.setFontSize(16 * GUI_SCALE);
		
		effectiveRenderDistance.setBounds(0 * GUI_SCALE, 20 * GUI_SCALE, 0 * GUI_SCALE, 16 * GUI_SCALE, Component.ALIGN_TOP);

		fog.setBounds(-125 * GUI_SCALE, 160 * GUI_SCALE, 250 * GUI_SCALE, 25 * GUI_SCALE, Component.ALIGN_TOP);
		fog.setFontSize(16f * GUI_SCALE);

		bloom.setBounds(-125 * GUI_SCALE, 200 * GUI_SCALE, 16 * GUI_SCALE, 16 * GUI_SCALE, Component.ALIGN_TOP);
		bloom.getLabel().setFontSize(16f * GUI_SCALE);
		
		vsync.setBounds(-125 * GUI_SCALE, 240 * GUI_SCALE, 16 * GUI_SCALE, 16 * GUI_SCALE, Component.ALIGN_TOP);
		vsync.getLabel().setFontSize(16f * GUI_SCALE);

	}

	@Override
	public void render() {
		renderDistance.render();
		//highestLOD.render();
		LODFactor.render();
		Graphics.setColor(0x7F7FA0);
		Graphics.fillRect(Window.getWidth()/2 - effectiveRenderDistance.getWidth()/2 - 2, 20 * GUI_SCALE - effectiveRenderDistance.getHeight()/2, effectiveRenderDistance.getWidth() + 4, effectiveRenderDistance.getHeight());
		effectiveRenderDistance.render();
		done.render();
		fog.render();
		bloom.render();
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
