package cubyz.gui;

public abstract class Transition {
	
	/**
	 * The duration in milliseconds.
	 */
	protected long duration;
	
	public long getDuration() {
		return duration;
	}

	// The 'time' parameter is relative to the transition's start that is between 0 and 1
	public abstract float getOldGuiOpacity(float time);
	public abstract float getCurrentGuiOpacity(float time);
	
	public static class None extends Transition {
		
		public None() {
			this.duration = 0;
		}
		
		public float getOldGuiOpacity(float time) {
			return 0.0f;
		}
		
		public float getCurrentGuiOpacity(float time) {
			return 1.0f;
		}
		
	}
	
	public static class FadeOutIn extends Transition {
		
		public FadeOutIn() {
			this(250); // 250ms transition by default
		}
		
		public FadeOutIn(long duration) {
			this.duration = duration;
		}
		
		public float getOldGuiOpacity(float time) {
			return Math.max(0, 0.5f - time);
		}
		
		public float getCurrentGuiOpacity(float time) {
			if (time >= 0.5f) {
				return 1 - Math.max(0, 0.5f - (time - 0.5f));
			} else {
				return 0.0f;
			}
		}
		
	}
	
}
