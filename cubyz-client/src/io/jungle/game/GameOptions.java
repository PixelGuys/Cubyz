package io.jungle.game;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

public class GameOptions {

	public boolean antialiasing = false;
	public boolean showTriangles = false;
	public boolean cullFace = true;
	public boolean frustumCulling = true;
	public boolean fullscreen = false;
	public boolean blending = false;
	
	public void exportTo(OutputStream o) throws IOException {
		o.write(antialiasing ? 1 : 0);
		o.write(showTriangles ? 1 : 0);
		o.write(cullFace ? 1 : 0);
		o.write(frustumCulling ? 1 : 0);
		o.write(fullscreen ? 1 : 0);
		o.write(blending ? 1 : 0);
	}
	
	public void importFrom(InputStream i) throws IOException {
		antialiasing = i.read() == 1;
		showTriangles = i.read() == 1;
		cullFace = i.read() == 1;
		frustumCulling = i.read() == 1;
		fullscreen = i.read() == 1;
		blending = i.read() == 1;
	}
	
}
