package io.jungle.game;

import io.jungle.Camera;
import io.jungle.Fog;
import io.jungle.Window;
import io.jungle.hud.Hud;

public class Context {

	private Window win;
	private Game game;
	private Camera camera;
	private Hud hud;
	private Fog fog;
	
	public Context(Game g, Camera c) {
		camera = c;
		game = g;
		win = g.win;
		hud = new Hud();
	}
	
	public Fog getFog() {
		return fog;
	}

	public void setFog(Fog fog) {
		this.fog = fog;
	}
	
	public Hud getHud() {
		return hud;
	}
	
	public void setHud(Hud hud) {
		this.hud = hud;
	}

	public Window getWindow() {
		return win;
	}

	public Game getGame() {
		return game;
	}

	public Camera getCamera() {
		return camera;
	}

}
