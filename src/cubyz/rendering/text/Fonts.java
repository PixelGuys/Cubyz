package cubyz.rendering.text;

import java.io.File;

import cubyz.utils.ResourceManager;

public class Fonts {
	
	private static final File BASE_FONT = ResourceManager.lookup("cubyz/fonts/unscii-16.ttf");
	
	public static final CubyzFont PIXEL_FONT = new CubyzFont(BASE_FONT, "sansserif", 16);
	public static final CubyzFont SMALL_PIXEL_FONT = new CubyzFont(BASE_FONT, "sansserif", 8);
	
}
