package cubyz.gui;

import cubyz.client.Cubyz;
import cubyz.gui.components.Label;
import cubyz.gui.components.ProgressBar;
import cubyz.rendering.Graphics;
import cubyz.rendering.Texture;
import cubyz.rendering.Window;
import cubyz.utils.ResourceManager;

/**
 * A GUI showing the progress of the loading phase.
 */

public class LoadingGUI extends MenuGUI {

	private static final LoadingGUI INSTANCE = new LoadingGUI();
	
	private Label step = new Label();
	private Label step2 = new Label();
	private boolean hasStep2 = false;
	private ProgressBar pb1 = new ProgressBar();
	private ProgressBar pb2 = new ProgressBar();
	private int alpha = 0;
	boolean alphaDecrease = false;
	private static Texture splash;
	
	public LoadingGUI() {
		step.setTextAlign(Component.ALIGN_CENTER);
		step2.setTextAlign(Component.ALIGN_CENTER);
	}
	
	public void finishLoading() {
		while (alpha > 0 || !alphaDecrease) {
			try {
				Thread.sleep(10);
			} catch (InterruptedException e) {}
		}
		MainMenuGUI mmg = new MainMenuGUI();
		Cubyz.gameUI.setMenu(mmg, false); // don't add itself to the back queue
		Cubyz.gameUI.addOverlay(new DebugOverlay());
		Cubyz.gameUI.addOverlay(new GeneralOverlay());
	}
	
	public void setStep(int step, int subStep, int subStepMax) {
		this.step.setText(step + "/5");
		pb1.setValue(step);
		if (subStepMax != 0) {
			hasStep2 = true;
			pb2.setValue(subStep);
			pb2.setMaxValue(subStepMax);
			step2.setText(subStep + "/" + subStepMax);
		} else {
			hasStep2 = false;
		}
	}
	
	@Override
	public void init(long nvg) {
		pb1.setMaxValue(5);
	}

	void setPosition(float x, float y, Component c) {
		c.setPosition((int)(x*Window.getWidth()), (int)(y*Window.getHeight()), Component.ALIGN_TOP_LEFT);
	}

	void setBounds(float x, float y, float w, float h, Component c) {
		c.setBounds((int)(x*Window.getWidth()), (int)(y*Window.getHeight()), (int)(w*Window.getWidth()), (int)(h*Window.getHeight()), Component.ALIGN_TOP_LEFT);
	}
	
	@Override
	public void render(long nvg) {
		if (splash == null) {
			splash = Texture.loadFromFile(ResourceManager.lookupPath("cubyz/textures/splash.png"));
		}		
		
		Graphics.setColor(0x000000);
		Graphics.fillRect(0, 0, Window.getWidth(), Window.getHeight());
		Graphics.setColor(0xFFFFFF, alpha);
		Graphics.fillRect(0, 0, Window.getWidth(), Window.getHeight());
		Graphics.drawImage(splash, Window.getWidth()/2-100, (int)(0.1f*Window.getHeight()), 200, 200);
		if (alphaDecrease) {
			if (alpha > 0) {
				alpha -= 4;
			}
		} else {
			if (alpha < 255) {
				alpha += 4;
			} else {
				alphaDecrease = true;
			}
		}
		setBounds(0.25f, 0.55f, 0.5f, 0.1f, pb1);
		setBounds(0.25f, 0.75f, 0.5f, 0.1f, pb2);
		setPosition(0.5f, 0.6f, step);
		setPosition(0.5f, 0.8f, step2);
		pb1.render(nvg);
		if (hasStep2) {
			pb2.render(nvg);
		}
		Graphics.setColor(0x000000);
		step.render(nvg);
		if (hasStep2) {
			step2.render(nvg);
		}
	}
	
	@Override
	public boolean doesPauseGame() {
		return true;
	}

	public static LoadingGUI getInstance() {
		return INSTANCE;
	}
	
}
