package cubyz.gui;

import java.util.ArrayDeque;
import java.util.Deque;

/**
 * Manages popup messages.<br>
 * TODO: Icons
 */

public class ToastManager {

	public static Deque<Toast> queuedToasts = new ArrayDeque<>();
	
	public static class Toast {
		public String title;
		public String text;
		
		public Toast(String title, String text) {
			this.title = title;
			this.text = text;
		}
	}
	
}
