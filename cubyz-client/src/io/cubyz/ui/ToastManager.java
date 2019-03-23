package io.cubyz.ui;

import java.util.Deque;

public class ToastManager  {

	public static Deque<Toast> queuedToasts;
	
	public static class Toast {
		public String title;
		public String text;
		
		public Toast(String title, String text) {
			this.title = title;
			this.text = text;
		}
	}
	
}
