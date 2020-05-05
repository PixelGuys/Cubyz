import java.util.Random;
import java.io.BufferedInputStream;
import java.io.DataInputStream;
import java.io.InputStream;

public class SampleTester {
	private static class Node {
		byte value;
		Node[] next;
		public Node(DataInputStream is, int depth) throws Exception {
			value = is.readByte();
			next = new Node[is.readByte()];
			for(int i = 0; i < next.length; i++) {
				if(depth == 0) {
					next[i] = new EndNode(is);
					((EndNode)next[i]).valuef = 1.0f/next.length;
				} else {
					next[i] = new Node(is, depth-1);
				}
			}
		}
		Node get(byte b) {
			for(Node n: next) {
				if(n.value == b) {
					return n;
				}
			}
			return null;
		}
		public Node() {}
	}
	private static class EndNode extends Node {
		float valuef;
		public EndNode(DataInputStream is) throws Exception {
			value = is.readByte();
			valuef = is.readFloat();
		}
	}
	static int getIndex(char c) {
		if(c == ' ') return 0;
		if('a' <= c && c <= 'z') return 1+c-'a';
		return -1;
	}
	static char getChar(int i) {
		if(i == 0) return ' ';
		if(i <= 26) return (char)('a'+i-1);
		System.err.println("Unknown "+i);
		System.exit(1);
		return '0';
	}
	
	private int color;
	private String name;
	public int template;
	
	private static Node tree;
	
	private static void readData(String file) {
		try {
			InputStream ois = SampleTester.class.getClassLoader().getResourceAsStream(file);
			DataInputStream is = new DataInputStream(new BufferedInputStream(ois));
			tree = new Node(is, 3);
			is.close();
		} catch (Exception e) {
			e.printStackTrace();
		}
	}
	
	private static char choose(char c1, char c2, char c3, float rand, int length) {
		try {
			int i1 = getIndex(c1);
			int i2 = getIndex(c2);
			int i3 = getIndex(c3);
			int i4 = 0;
			Node[] list = tree.get((byte)i1).get((byte)i2).get((byte)i3).next;
			if(length >= 10 && list[0].value == 0) { // Make sure the word ends.
				return ' ';
			}
			for(;;i4++) {
				rand -= ((EndNode)list[i4]).valuef;
				if(rand <= 0) {
					break;
				}
			}
			return getChar(list[i4].value);
		} catch(ArrayIndexOutOfBoundsException e) {
			return ' ';
		}
	}
	
	private static String randomName(Random rand) {
		StringBuilder sb = new StringBuilder();
		
		char c1 = ' ', c2 = ' ', c3 = ' ', c4 = choose(c1, c2, c3, rand.nextFloat(), 0);
		sb.append((char)(c4+'A'-'a'));
		int i = 0;
		while(true) {
			char c5 = choose(c2, c3, c4, rand.nextFloat(), ++i);
			if(c4 == ' ') {
				if(c5 == ' ') {
					break;
				}
				sb.append(c4);
			}
			c1 = c2;
			c2 = c3;
			c3 = c4;
			c4 = c5;
			if(c5 != ' ')
				sb.append(c5);
		}
		if(sb.length() <= 15 && sb.length() >= 5)
			return sb.toString();
		else
			return randomName(rand); // Repeat until a long enought name is generated.
	}
	
	public static void main(String[] args) {
		readData(args[0]);
		for(int i = 0; i < 100; i++) {
			System.out.println(randomName(new Random()));
		}
	}
}
