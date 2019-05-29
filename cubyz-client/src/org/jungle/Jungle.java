package org.jungle;

import org.lwjgl.Version;

public final class Jungle {

	public static final int VERSION_MAJOR = 0;
	public static final int VERSION_MINOR = 2;
	public static final int VERSION_PATCH = 2;
	public static final String BUILD_TYPE = "alpha";
	
	static {
		init();
	}
	
	public final static void init() {
		// dead code if version is correct, JungleEngine is compatible with 3.2.x version
		if (Version.VERSION_MINOR != 2 || Version.VERSION_MAJOR != 3) {
			throw new IllegalStateException("invalid lwjgl version");
		}
	}
	
	public final static String getVersion() {
		return VERSION_MAJOR + "." + VERSION_MINOR + "." + VERSION_PATCH + " " + BUILD_TYPE;
	}
	
}
