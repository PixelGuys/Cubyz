package cubyz.utils.json;

import java.io.BufferedReader;
import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.ArrayList;

import cubyz.utils.Logger;

public abstract class JsonParser {

	public static JsonObject parseObjectFromStream(BufferedReader in) throws IOException {
		//try to gather the full message (end indicated by a emptyline)
		String fullmessage = "", message = "";
		while (!(message = in.readLine()).isEmpty()) {
			fullmessage += message;
		}
		try {
			return JsonParser.parseObjectFromString(fullmessage);
		} catch (Exception e) {
			e.printStackTrace();
		}
		return new JsonObject();
	}

	public static JsonObject parseObjectFromString(String text) {
		char[] characters = text.trim().toCharArray(); // Remove leading and trailing spaces and convert to char array.

		if (characters[0] != '{') {
			throw new IllegalArgumentException("Expected the json data to start with an object.");
		}
		int[] index = new int[] {1};
		JsonObject head = parseObject(characters, index);
		return head;
	}

	public static JsonObject parseObjectFromFile(String path){
		String text = "";
		try {
			text = new String(Files.readAllBytes(Paths.get(path)));
		} catch (IOException e) {
			Logger.error(e);
			return new JsonObject();
		}
		/*TODO: filePathForErrorHandling is a static variable. Might cause weired behavior in the future (especially with multithreading) */
		filePathForErrorHandling = path;
		try {
			return parseObjectFromString(text);
		} catch (Exception e) {
			Logger.warning("Expected the json file to start with an object: "+path);
		}
		return new JsonObject();
	}

	public static void storeToFile(JsonElement json, String path){
		String text = json.toString();
		File file = new File(path);
		file.getParentFile().mkdirs();
		try {
			Files.write(file.toPath(), text.getBytes("UTF-8"));
		} catch (IOException e) {
			Logger.error(e);
		}
	}

	private static String filePathForErrorHandling;

	private static void printError(int index, char[] chars, String message) {
		// Determine the line:
		int line = 1;
		for(int i = 0; i < index; i++) {
			if (chars[i] == '\n') line++;
		}
		Logger.warning("Syntax error reading json file \"" + filePathForErrorHandling + "\" in line " + line + ": " + message);
	}

	private static void skipWhitespaces(char[] chars, int[] index) {
		for(; index[0] < chars.length; index[0]++) {
			if (!Character.isWhitespace(chars[index[0]])) break;
		}
	}

	private static JsonArray parseArray(char[] chars, int[] index) {
		JsonArray jsonArray = new JsonArray();
		ArrayList<JsonElement> array = jsonArray.array;
		for(; index[0] < chars.length; index[0]++) {
			if (Character.isWhitespace(chars[index[0]])) continue;
			if (chars[index[0]] == ',') {
				// Just ignore it. I don't care if someone puts multiple or none in there.
			} else if (chars[index[0]] == ']') {
				break;
			} else {
				JsonElement element = parseValue(chars, index);
				array.add(element);
			}
		}
		return jsonArray;
	}

	private static JsonObject parseObject(char[] chars, int[] index) {
		JsonObject object = new JsonObject();
		// Parse all entries for this  object.
		for(; index[0] < chars.length; index[0]++) {
			if (Character.isWhitespace(chars[index[0]])) continue;
			if (chars[index[0]] == ',') continue; // Just ignore it. I don't care if someone puts multiple or none in there.

			if (chars[index[0]] == '}') break;
			if (chars[index[0]] == '\"') { // Beginning of a new expression.
				index[0]++;
				String key = parseString(chars, index);
				index[0]++;
				// Parse the ":":
				skipWhitespaces(chars, index);
				// Complain about other characters if present:
				while (chars[index[0]++] != ':') {
					printError(index[0], chars, "Unexpected character while parsing object parameter: "+chars[index[0]]+". Expected \':\'.");
				}
				skipWhitespaces(chars, index);
				// Parse the value:
				JsonElement element = parseValue(chars, index);
				object.put(key, element);
			} else {
				// A character that shouldn't be there.
				printError(index[0], chars, "Unexpected character while parsing object parameter: "+chars[index[0]]+". Expected \" or \'}\'.");
			}
		}
		return object;
	}

	private static JsonElement parseValue(char[] chars, int[] index) {
		JsonElement value;
		switch(chars[index[0]]) {
			case '0':
			case '1':
			case '2':
			case '3':
			case '4':
			case '5':
			case '6':
			case '7':
			case '8':
			case '9':
			case '+':
			case '-':
				// That's a number. If it contains a non-digit character, then it's probably a float. The end is either a whitespace or a ','.
				// Find the end:
				int end = index[0]+1;
				boolean isFloat = false;
				while (!Character.isWhitespace(chars[end]) && chars[end] != ',' && chars[end] != '}' && chars[end] != ']') {
					switch(chars[end]) {
					case '0':
					case '1':
					case '2':
					case '3':
					case '4':
					case '5':
					case '6':
					case '7':
					case '8':
					case '9':
					case 'a':
					case 'b':
					case 'c':
					case 'd':
					case 'e':
					case 'f':
					case 'x':
						break;
					default:
						isFloat = true;
					}
					end++;
				}
				try {
					if (isFloat) {
						value = new JsonFloat(Double.parseDouble(new String(chars, index[0], end - index[0])));
					} else {
						value = new JsonInt(Long.decode(new String(chars, index[0], end - index[0])));
					}
				} catch(Exception e) {
					printError(index[0], chars, "Cannot parse number: "+new String(chars, index[0], end - index[0])+".");
					value = new JsonOthers(true, false);
					e.printStackTrace();
				}
				index[0] = end-1;
				break;
			case 't': // Only true would be valid here.
				if (chars[index[0]+1] != 'r' && chars[index[0]+2] != 'u' && chars[index[0]+3] != 'e') {
					printError(index[0], chars, "Unexpected value: "+new String(chars, index[0], chars.length - index[0]).replaceAll("\\s*", "")+".");
				}
				index[0] += 4-1;
				value = new JsonOthers(false, true);
				break;
			case 'f': // Only false would be valid here.
				if (chars[index[0]+1] != 'a' && chars[index[0]+2] != 'l' && chars[index[0]+3] != 's' && chars[index[0]+4] != 'e') {
					printError(index[0], chars, "Unexpected value: "+new String(chars, index[0], chars.length - index[0]).replaceAll("\\s*", "")+".");
				}
				index[0] += 5-1;
				value = new JsonOthers(false, false);
				break;
			case '\"':
				index[0]++;
				value = new JsonString(parseString(chars, index));
				break;
			case 'n': // Only null would be valid here.
				if (chars[index[0]+1] != 'u' && chars[index[0]+2] != 'l' && chars[index[0]+3] != 'l') {
					printError(index[0], chars, "Unexpected value: "+new String(chars, index[0], chars.length - index[0]).replaceAll("\\s*", "")+".");
				}
				index[0] += 4-1;
				value = new JsonOthers(true, false);
				break;
			case '[':
				index[0]++;
				value = parseArray(chars, index);
				break;
			case '{':
				index[0]++;
				value = parseObject(chars, index);
				break;
			default:
				printError(index[0], chars, "Unexpected value: "+new String(chars, index[0], chars.length - index[0]).replaceAll("\\s*", "")+".");
				value = new JsonOthers(true, false);
		}
		return value;
	}

	private static String parseString(char[] chars, int[] index) {
		StringBuilder builder = new StringBuilder();
		for(; index[0] < chars.length; index[0]++) {
			if (chars[index[0]] == '\"') {
				return builder.toString();
			}
			if (chars[index[0]] == '\\') {
				index[0]++;
				if (index[0] == chars.length) break;
				switch(chars[index[0]]) {
					case 'b':
						builder.append('\b');
						break;
					case 't':
						builder.append('\t');
						break;
					case 'n':
						builder.append('\n');
						break;
					case 'r':
						builder.append('\r');
						break;
					case 'f':
						builder.append('\f');
						break;
					case 'u':
						if (index[0]+4 >= chars.length) break;
						builder.append((char)Short.parseShort("0x"+chars[++index[0]]+chars[++index[0]]+chars[++index[0]]+chars[++index[0]]));
						break;
					default:
						builder.append(chars[index[0]]);
						break;
				}
			} else {
				builder.append(chars[index[0]]);
			}
		}
		printError(index[0], chars, "Unexpected end of File while reading String. Perhaps you forgot the closing \".");
		return builder.toString();
	}
}
