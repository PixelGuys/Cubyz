package io.spacycubyd;

import io.spacycubyd.api.Side;

public class Constants {

	public static final String GAME_VERSION = "dtr-1";
	public static final String GAME_BRAND = "vanilla";
	static Side currentSide = null;
	
	public Side getGameSide() {
		return currentSide;
	}
	
	public void setGameSide(Side side) {
		currentSide = side;
	}
	
}
