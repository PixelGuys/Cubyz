package io.cubyz.ui;

import io.cubyz.client.Cubyz;
import io.cubyz.ui.components.Label;
import io.cubyz.ui.components.ProgressBar;
import io.cubyz.utils.ResourceManager;
import io.jungle.Window;

public class LoadingGUI extends MenuGUI {

	private static final LoadingGUI INSTANCE = new LoadingGUI();
	
	private Label step = new Label();
	private Label step2 = new Label();
	private boolean hasStep2 = false;
	private ProgressBar pb1 = new ProgressBar();
	private ProgressBar pb2 = new ProgressBar();
	private int alpha = 0;
	boolean alphaDecrease = false;
	int splashID = -1;
	
	public void finishLoading() {
		while (alpha > 0 || !alphaDecrease) {
			try {
				Thread.sleep(10);
			} catch (InterruptedException e) {
				e.printStackTrace();
			}
		}
		MainMenuGUI mmg = new MainMenuGUI();
		Cubyz.gameUI.setMenu(mmg);
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

	void setPosition(float x, float y, Component c, Window w) {
		c.setPosition((int) (x * w.getWidth()), (int) (y * w.getHeight()));
	}
	
	void setSize(float w, float h, Component c, Window win) {
		c.setSize((int) (w * win.getWidth()), (int) (h * win.getHeight()));
	}
	
	@Override
	public void render(long nvg, Window win) {
		if (splashID == -1) {
			splashID = NGraphics.loadImage(ResourceManager.lookupPath("cubyz/textures/splash.png"));
		}
		
		NGraphics.setColor(0, 0, 0);
		NGraphics.fillRect(0, 0, win.getWidth(), win.getHeight());
		NGraphics.setColor(255, 255, 255, alpha);
		NGraphics.fillRect(0, 0, win.getWidth(), win.getHeight());
		NGraphics.drawImage(splashID, win.getWidth()/2-100, (int)(0.1f*win.getHeight()), 200, 200);
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
		setPosition(0.25f, 0.55f, pb1, win);
		setPosition(0.25f, 0.75f, pb2, win);
		setSize(0.50f, 0.1f, pb1, win);
		setSize(0.50f, 0.1f, pb2, win);
		setPosition(0.5f, 0.6f, step, win);
		setPosition(0.5f, 0.8f, step2, win);
		pb1.render(nvg, win);
		if (hasStep2) {
			pb2.render(nvg, win);
		}
		NGraphics.setColor(0, 0, 0);
		step.render(nvg, win);
		if (hasStep2) {
			step2.render(nvg, win);
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
