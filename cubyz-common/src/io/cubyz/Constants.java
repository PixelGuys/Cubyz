package io.cubyz;

import io.cubyz.api.Side;

public class Constants {

	public static final String GAME_BUILD_TYPE = "alpha";
	public static final String GAME_VERSION = "0.3.1";
	public static final String GAME_BRAND = "cubyz";
	static Side currentSide = null;
	
	public Side getGameSide() {
		return currentSide;
	}
	
	public void setGameSide(Side side) {
		currentSide = side;
	}
	
}
