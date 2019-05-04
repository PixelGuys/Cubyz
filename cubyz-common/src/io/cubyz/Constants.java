package io.cubyz;

import java.nio.charset.Charset;

import io.cubyz.api.Side;

public class Constants {

	public static final String CHARSET = "UTF-8";
	public static final Charset CHARSET_IMPL = Charset.forName(CHARSET);
	
	public static final String GAME_BUILD_TYPE = "alpha";
	
	// WARNING! Both brand name and version cannot contain ';' inside!
	public static final String GAME_VERSION = "0.4.0";
	public static final String GAME_BRAND = "cubyz";
	static Side currentSide = null;
	
	public Side getGameSide() {
		return currentSide;
	}
	
	public void setGameSide(Side side) {
		currentSide = side;
	}
	
}
