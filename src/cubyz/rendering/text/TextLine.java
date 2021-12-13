package cubyz.rendering.text;

import static org.lwjgl.opengl.GL11.GL_FLOAT;
import static org.lwjgl.opengl.GL11.GL_TRIANGLE_STRIP;
import static org.lwjgl.opengl.GL11.glDrawArrays;
import static org.lwjgl.opengl.GL13.GL_TEXTURE0;
import static org.lwjgl.opengl.GL13.glActiveTexture;
import static org.lwjgl.opengl.GL15.GL_ARRAY_BUFFER;
import static org.lwjgl.opengl.GL15.GL_STATIC_DRAW;
import static org.lwjgl.opengl.GL15.glBindBuffer;
import static org.lwjgl.opengl.GL15.glBufferData;
import static org.lwjgl.opengl.GL15.glGenBuffers;
import static org.lwjgl.opengl.GL20.glEnableVertexAttribArray;
import static org.lwjgl.opengl.GL20.glUniform1f;
import static org.lwjgl.opengl.GL20.glUniform1i;
import static org.lwjgl.opengl.GL20.glUniform2f;
import static org.lwjgl.opengl.GL20.glUniform4f;
import static org.lwjgl.opengl.GL20.glVertexAttribPointer;
import static org.lwjgl.opengl.GL30.glBindVertexArray;
import static org.lwjgl.opengl.GL30.glGenVertexArrays;

import java.awt.Rectangle;
import java.awt.Toolkit;
import java.awt.datatransfer.Clipboard;
import java.awt.datatransfer.DataFlavor;
import java.awt.datatransfer.StringSelection;
import java.awt.datatransfer.Transferable;
import java.awt.font.TextHitInfo;
import java.awt.font.TextLayout;
import java.awt.geom.Point2D;
import java.awt.geom.Rectangle2D;
import java.io.IOException;
import java.util.ArrayList;

import org.lwjgl.glfw.GLFW;

import cubyz.gui.input.KeyListener;
import cubyz.gui.input.Keyboard;
import cubyz.rendering.Graphics;
import cubyz.rendering.ShaderProgram;
import cubyz.rendering.Window;
import cubyz.utils.Utils;

/**
 * Manages all the unicode stuff and converts a line of text into unicode glyphs.
 * This is internally done using java.awt.TextLayout.
 */
public class TextLine implements KeyListener {
	public final CubyzFont font;
	final ArrayList<Glyph> glyphs = new ArrayList<Glyph>();
	final float height;
	private float textWidth;
	private float xOffset = 0; // Used to counteract the intrinsic offset of the glyphs.
	
	// Some internal data that is used for rendering:
	TextMarker[] textMarkingInfo = new TextMarker[0];
	LineSegment[] lines = new LineSegment[0];
	TextLayout layout;
	final boolean isEditable;
	String text;
	boolean[] isControlCharacter = new boolean[0];
	
	/**
	 * 
	 * @param font
	 * @param text
	 * @param height
	 */
	public TextLine(CubyzFont font, String text, float height, boolean isEditable) {
		this.font = font;
		this.height = height;
		this.isEditable = isEditable;
		_updateText(text);
	}
	
	/**
	 * This event came from the outside, so the cursor position is set to 0, to prevent issues.
	 * @param text
	 */
	public void updateText(String text) {
		if (cursorPosition != null)
			cursorPosition = TextHitInfo.trailing(-1);
		_updateText(text);
	}
	
	/**
	 * Make sure to correct the cursor position when calling!
	 * @param text
	 */
	private void _updateText(String text) {
		if (text == null) text = "";
		this.text = text;
		if (text.length() == 0) {
			layout = null;
			glyphs.clear();
			textWidth = 0;
		} else {
			PrettyText.parse(this);
			//layout = new TextLayout(text, font.font, font.fontGraphics.getFontRenderContext());
			TextLayoutGraphics.generateGlyphData(layout, this);
			textWidth = (float)layout.getPixelBounds(null, 0, 0).getWidth()*height/font.getSize();
			xOffset = (float)layout.getPixelBounds(null, 0, 0).getMinX();
		}
	}
	
	public float getWidth() {
		return textWidth;
	}
	
	public String getText() {
		return text;
	}

	public float getTextWidth() {
		return textWidth;
	}
	
	// -------------------------------------------------
	// Cursor and selection stuff:
	private TextHitInfo cursorPosition;
	private TextHitInfo selectionStart;
	
	private TextHitInfo getCursorPosition(float mouseX) {
		if (layout == null) {
			return TextHitInfo.trailing(-1);
		} else {
			// Do the hit-test using an overestimated bound.
			return layout.hitTestChar(mouseX*font.getSize()/height, font.getSize()/2,
					new Rectangle2D.Float(-1000, -1000, textWidth*font.getSize()/height + 2000, font.getSize() + 2000));
		}
	}
	
	public void startSelection(float mouseX) {
		cursorPosition = selectionStart = getCursorPosition(mouseX);
	}
	
	public void changeSelection(float mouseX) {
		cursorPosition = getCursorPosition(mouseX);
	}
	
	public void endSelection(float mouseX) {
		cursorPosition = getCursorPosition(mouseX);
		if (cursorPosition.equals(selectionStart))
			selectionStart = null;
		Keyboard.activeComponent = this; // Register as key listener.
	}
	
	public void unselect() {
		cursorPosition = selectionStart = null;
		if (Keyboard.activeComponent == this) { // Unregister as key listener.
			Keyboard.activeComponent = null;
		}
	}

	/**
	 * Makes sure that the cursor is on the correct edge for further usage, by moving it one field and back.
	 * @param position `cursorPosition` or `selectionStart`
	 * @return
	 */
	private TextHitInfo fixEdge(TextHitInfo position) {
		if (position == null || layout == null) return position;
		if (text.length() == 0) return TextHitInfo.trailing(-1);
		if (layout.getNextLeftHit(position) != null) {
			position = layout.getNextLeftHit(position);
			position = layout.getNextRightHit(position);
		} else {
			position = layout.getNextRightHit(position);
			position = layout.getNextLeftHit(position);
		}
		return position;
	}

	/**
	 * Add chars at the cursor position.
	 * @param chars
	 * @param cursorPosition
	 */
	public void addText(String addition) {
		if (cursorPosition == null) return;
		if (selectionStart != null) deleteTextAtCursor(true); // overwrite selected text.
		int insertionIndex = cursorPosition.getInsertionIndex();
		text = text.substring(0, insertionIndex)+addition+text.substring(insertionIndex);
		_updateText(text);
		cursorPosition = TextHitInfo.leading(insertionIndex + addition.length());
		
		cursorPosition = fixEdge(cursorPosition);
	}
	
	/**
	 * Moves the cursor. Positive direction is to the right.
	 * @param offset
	 */
	public void moveCursor(int offset) {
		if (text.length() == 0) {
			cursorPosition = TextHitInfo.trailing(-1);
			return;
		}
		if (offset < 0) {
			while (offset++ < 0) {
				TextHitInfo newPosition = layout.getNextLeftHit(cursorPosition);
				if (newPosition != null) {
					cursorPosition = newPosition;
					break;
				}
			}
		} else if (offset > 0) {
			while (offset-- > 0) {
				TextHitInfo newPosition = layout.getNextRightHit(cursorPosition);
				if (newPosition != null) {
					cursorPosition = newPosition;
					break;
				}
			}
		}
		cursorPosition = fixEdge(cursorPosition);
	}
	
	private void deleteTextRange(int start, int end) {
		text = text.substring(0, start) + text.substring(end);
	}
	/**
	 * Removes the selected text or if no text is selected, removes the right or left character depending on what key is pressed.
	 * @param isRightDelete on which side the character should be removed.
	 */
	public void deleteTextAtCursor(boolean isRightDelete) {
		if (cursorPosition != null && layout != null) {
			boolean isLeading = cursorPosition.isLeadingEdge();
			int oldPositionIndex = cursorPosition.getCharIndex();
			// Make a selection to determine which character should be removed:
			if (selectionStart == null) { // If nothing is selected.
				if (isRightDelete) {
					selectionStart = layout.getNextRightHit(cursorPosition);
				} else {
					selectionStart = layout.getNextLeftHit(cursorPosition);
				}
				if (selectionStart == null) {
					return;
				}
			}
			int[] selection = layout.getLogicalRangesForVisualSelection(cursorPosition, selectionStart);
			selectionStart = null;
			// Remove all selected characters:
			for(int i = 0; i < selection.length; i += 2) {
				int start = selection[i];
				int end = selection[i+1];
				deleteTextRange(start, end);
				// Go through other indices and shift them:
				for(int j = i + 2; j < selection.length; j += 2) {
					if (selection[j] >= end) {
						selection[j] -= end - start;
						selection[j+1] -= end - start;
					}
				}
				// Also move the current cursor location:
				if (oldPositionIndex >= end || (oldPositionIndex == end-1 && !isLeading)) {
					oldPositionIndex -= end - start;
				}
			}
			_updateText(text);
			// Update cursor:
			if (isLeading)
				cursorPosition = TextHitInfo.leading(oldPositionIndex);
			else
				cursorPosition = TextHitInfo.trailing(oldPositionIndex);
			
			cursorPosition = fixEdge(cursorPosition);
		}
	}
	
	public void onKeyPress(int code) {
		boolean isMovementKey;
		switch(code) {
		case GLFW.GLFW_KEY_LEFT:
		case GLFW.GLFW_KEY_RIGHT:
		case GLFW.GLFW_KEY_END:
		case GLFW.GLFW_KEY_HOME:
			isMovementKey = true;
			break;
		default:
			isMovementKey = false;
			break;
		}
		if (selectionStart == null && isMovementKey &&
				(Keyboard.isKeyPressed(GLFW.GLFW_KEY_LEFT_SHIFT) || Keyboard.isKeyPressed(GLFW.GLFW_KEY_RIGHT_SHIFT))) {
			// Start a selection if the shift key was pressed and the user moved in the text:
			selectionStart = cursorPosition;
		}
		if (code == GLFW.GLFW_KEY_BACKSPACE) {
			deleteTextAtCursor(false);
		} else if (code == GLFW.GLFW_KEY_DELETE) {
			deleteTextAtCursor(true);
		} else if (code == GLFW.GLFW_KEY_LEFT) {
			moveCursor(-1);
		} else if (code == GLFW.GLFW_KEY_RIGHT) {
			moveCursor(1);
		} else if (code == GLFW.GLFW_KEY_END) {
			cursorPosition = fixEdge(TextHitInfo.leading(text.length()));
		} else if (code == GLFW.GLFW_KEY_HOME) {
			cursorPosition = fixEdge(TextHitInfo.trailing(-1));
		} else if (code == GLFW.GLFW_KEY_C && // copy
				(Keyboard.isKeyPressed(GLFW.GLFW_KEY_LEFT_CONTROL) || Keyboard.isKeyPressed(GLFW.GLFW_KEY_RIGHT_CONTROL))) {
			copyText();
		} else if (code == GLFW.GLFW_KEY_X && // cut
				(Keyboard.isKeyPressed(GLFW.GLFW_KEY_LEFT_CONTROL) || Keyboard.isKeyPressed(GLFW.GLFW_KEY_RIGHT_CONTROL))) {
			cutText();
		} else if (code == GLFW.GLFW_KEY_V && // paste
				(Keyboard.isKeyPressed(GLFW.GLFW_KEY_LEFT_CONTROL) || Keyboard.isKeyPressed(GLFW.GLFW_KEY_RIGHT_CONTROL))) {
			pasteText();
		}
		if (selectionStart != null && isMovementKey &&
				!Keyboard.isKeyPressed(GLFW.GLFW_KEY_LEFT_SHIFT) &&
				!Keyboard.isKeyPressed(GLFW.GLFW_KEY_RIGHT_SHIFT)) {
			// End the selection if the shift key wasn't pressed and the user moved in the text:
			selectionStart = null;
		}
	}

	/**
	 * Copies selected text to clipboard.
	 */
	public void copyText() {
		if (selectionStart == null) return; // Don't copy if nothing is selected.
		int[] selections = layout.getLogicalRangesForVisualSelection(cursorPosition, selectionStart);
		String result = "";
		for(int i = 0; i < selections.length; i += 2) {
			int start = selections[i];
			int end = selections[i+1];
			result += text.substring(start, end);
		}
		StringSelection selection = new StringSelection(result);
		Clipboard clipboard = Toolkit.getDefaultToolkit().getSystemClipboard();
		clipboard.setContents(selection, selection);
	}

	/**
	 * Pastes text from clipboard at the current cursor position.
	 */
	public void pasteText() {
		// Check if there even is a String non-zero length on the clipboard:
		String pasted = "";
		try {
			Clipboard clipboard = Toolkit.getDefaultToolkit().getSystemClipboard();
			Transferable clipBoardContent = clipboard.getContents(this);
			pasted = clipBoardContent.getTransferData(DataFlavor.stringFlavor).toString();
		} catch(Exception e) {
			return;
		}
		if (pasted.length() == 0) return;
		// Delete the current selection and replace it with the inserted value:
		if (selectionStart != null) {
			deleteTextAtCursor(true);
		}
		addText(pasted);
	}

	/**
	 * Copies selected text to clipboard and deletes it.
	 */
	public void cutText() {
		copyText();
		if (selectionStart != null)
			deleteTextAtCursor(true);
	}
	

	// -------------------------------------------------
	// Rendering stuff:

	// Shader stuff:
	public static class TextUniforms {
		public static int loc_texture_rect;
		public static int loc_scene;
		public static int loc_offset;
		public static int loc_ratio;
		public static int loc_fontEffects;
		public static int loc_fontSize;
		public static int loc_texture_sampler;
		public static int loc_alpha;
	}

	static int textVAO;
	public static ShaderProgram textShader;
	
	static { // opengl stuff:
		try {
			textShader = new ShaderProgram(Utils.loadResource("assets/cubyz/shaders/graphics/Text.vs"),
					Utils.loadResource("assets/cubyz/shaders/graphics/Text.fs"), TextUniforms.class);
		} catch (IOException e) {
			e.printStackTrace();
		}
		// vertex buffer
		float rawdata[] = { 
			0, 0,		0, 0,
			0, -1,		0, 1,
			1, 0,		1, 0,
			1, -1,		1, 1
		};
		
		textVAO = glGenVertexArrays();
		glBindVertexArray(textVAO);
		int textVBO = glGenBuffers();
		glBindBuffer(GL_ARRAY_BUFFER, textVBO);
		glBufferData(GL_ARRAY_BUFFER, rawdata, GL_STATIC_DRAW);
		glVertexAttribPointer(0, 2, GL_FLOAT, false, 4*4, 0);
		glVertexAttribPointer(1, 2, GL_FLOAT, false, 4*4, 8);
		glEnableVertexAttribArray(0);
		glEnableVertexAttribArray(1);
	}

	public static void setGlobalAlphaMultiplier(float multiplier) {
		textShader.bind();
		glUniform1f(TextUniforms.loc_alpha, multiplier);
	}
	
	/**
	 * Gets the x-position of the cursor on the text.
	 * @param cursorPosition
	 * @return
	 */
	private float getCursorX(TextHitInfo cursorPosition) {
		if (cursorPosition == null || layout == null) return 0;
		Point2D.Float cursorPos = new Point2D.Float();
		layout.hitToPoint(cursorPosition, cursorPos);
		return cursorPos.x;
	}
	
	public void render(float x, float y) {
		// Correct by the height of the font:
		float ratio = (float)height/font.getSize();
		y += 0.01f; // Prevents artifact on pixel borders.
		
		// Draw the lines:
		for(LineSegment line : lines) {
			line.draw(ratio, x, y);
		}
		
		// Transform coordinate system:
		x /= ratio;
		y /= ratio;
		x -= xOffset;
		
		// Draw the cursor and selected region:
		if (cursorPosition != null) {
			float cursorX = getCursorX(cursorPosition);
			Graphics.setColor(0xff000000);
			Graphics.drawLine((x + cursorX)*ratio, y*ratio, (x + cursorX)*ratio, y*ratio + height);
			
			if (selectionStart != null) {
				float startX = x + cursorX;
				float selectionStartX = getCursorX(selectionStart);
				float endX = x + selectionStartX;
				Graphics.setColor(0x000000, 127);
				Graphics.fillRect(Math.min(startX, endX)*ratio, y*ratio, Math.abs(endX - startX)*ratio, height);
			}
		}
		
		textShader.bind();

		glActiveTexture(GL_TEXTURE0);
		if (font.getTexture() != null) {
			font.getTexture().bind();
			glUniform2f(TextUniforms.loc_fontSize, font.getTexture().getWidth(), font.getTexture().getHeight());
		}

		glUniform2f(TextUniforms.loc_scene, Window.getWidth(), Window.getHeight());
		glUniform1f(TextUniforms.loc_ratio, ratio);
		

		glBindVertexArray(textVAO);
		int markerIndex = 0;
		byte activeFontEffects = 0;
		int color = 0;

		// Draw all the glyphs:
		for (int i = 0; i < glyphs.size(); i++) {
			Glyph glyph = glyphs.get(i);
			// Check if new markers are active:
			if (textMarkingInfo != null) {
				while (markerIndex < textMarkingInfo.length && glyph.charIndex >= textMarkingInfo[markerIndex].charPosition) {
					switch(textMarkingInfo[markerIndex].type) {
						case TextMarker.TYPE_BOLD:
						case TextMarker.TYPE_ITALIC:
							activeFontEffects ^= textMarkingInfo[markerIndex].type;
							break;
						case TextMarker.TYPE_COLOR:
							color = textMarkingInfo[markerIndex].color;
							break;
						case TextMarker.TYPE_COLOR_ANIMATION:
							color = textMarkingInfo[markerIndex].animation.getColor();
							break;
					}
					markerIndex++;
				}
			}
			Rectangle textureBounds = font.getGlyph(glyph.codepoint);
			if ((activeFontEffects & TextMarker.TYPE_BOLD) != 0) {
				// Increase the texture size for the bold shadering to work.
				textureBounds = new Rectangle(textureBounds.x, textureBounds.y-1, textureBounds.width, textureBounds.height+1);
				y -= 1; // Make sure that the glyph stays leveled.
			}
			if (isControlCharacter[i]) {
				// Control characters are drawn using a gray color and without font effects, to make them stand out.
				glUniform1i(TextUniforms.loc_fontEffects, 0x007f7f7f);
			} else {
				glUniform1i(TextUniforms.loc_fontEffects, color | (activeFontEffects << 24));
			}
			
			glUniform2f(TextUniforms.loc_offset, glyph.x + x, glyph.y + y);
			glUniform4f(TextUniforms.loc_texture_rect, textureBounds.x+42e-5f, textureBounds.y, textureBounds.width, textureBounds.height);
			
			
			glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
			if ((activeFontEffects & TextMarker.TYPE_BOLD) != 0 && !isControlCharacter[i]) {
				// Just draw another thing on top in x direction. y-direction is handled in the shader.
				glUniform2f(TextUniforms.loc_offset, glyph.x + x + 0.5f, glyph.y + y);
				glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
			}
			
			if ((activeFontEffects & TextMarker.TYPE_BOLD) != 0) {
				y += 1; // Revert the previous transformation.
			}
		}

		if (font.getTexture() != null) {
			font.getTexture().unbind();
		}
		textShader.unbind();
	}
}
