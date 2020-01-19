package io.jungle;

import io.jungle.FrameBuffer.FrameBufferException;

public class ShadowMap {

	private final FrameBuffer fbo;
	
	public ShadowMap(int width, int height) throws FrameBufferException {
		fbo = new FrameBuffer();
		fbo.genDepthTexture(width, height);
		fbo.validate();
	}
	
	public FrameBuffer getDepthMapFBO() {
		return fbo;
	}
	
}
