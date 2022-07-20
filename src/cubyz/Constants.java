package cubyz;

import java.nio.charset.Charset;

import cubyz.api.Side;

/**
 * A set of constant like version or math.
 */

public final class Constants {

	private Constants() {} // No instances allowed.

	public static final String CHARSET_NAME = "UTF-8";
	public static final Charset CHARSET = Charset.forName(CHARSET_NAME);
	
	public static final String GAME_BUILD_TYPE = "ALPHA";
	
	// WARNING! Both brand name and version cannot contain ';' inside!
	public static final String GAME_VERSION = "0.11.0";
	public static final int GAME_PROTOCOL_VERSION = 1;
	public static final String GAME_BRAND = "cubyz";

	/**maximum quality reduction.*/
	public static final int HIGHEST_LOD = 5;
	
	/**float math constants*/
	public static final float	PI = (float)Math.PI,
								PI_HALF = PI/2;


	public static final int DEFAULT_PORT = 5678;
	public static final int CONNECTION_TIMEOUT = 30000;
	public static final short ENTITY_LOOKBACK = 100;

	static Side currentSide = null;
	
	public static Side getGameSide() {
		return currentSide;
	}
	
	public static void setGameSide(Side side) {
		currentSide = side;
	}
	
}
