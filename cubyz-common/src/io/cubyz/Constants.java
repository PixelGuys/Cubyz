package io.cubyz;

import java.nio.charset.Charset;

import io.cubyz.api.Side;

public class Constants {

	public static final String CHARSET_NAME = "UTF-8";
	public static final Charset CHARSET = Charset.forName(CHARSET_NAME);
	
	public static final String GAME_BUILD_TYPE = "alpha";
	
	// WARNING! Both brand name and version cannot contain ';' inside!
	public static final String GAME_VERSION = "0.6.0";
	public static final String GAME_BRAND = "cubyz";
	static Side currentSide = null;
	
	public static Side getGameSide() {
		return currentSide;
	}
	
	public static void setGameSide(Side side) {
		currentSide = side;
	}
	
}
