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
			if (depth == 0) return;
			next = new Node[is.readByte()];
			for(int i = 0; i < next.length; i++) {
				next[i] = new Node(is, depth-1);
			}
		}
		Node get(byte b) {
			for(Node n: next) {
				if (n.value == b) {
					return n;
				}
			}
			return null;
		}
	}
	static int getIndex(char c) {
		if (c == ' ') return 0;
		if ('a' <= c && c <= 'z') return 1+c-'a';
		return -1;
	}
	static char getChar(int i) {
		if (i == 0) return ' ';
		if (i <= 26) return (char)('a'+i-1);
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
			tree = new Node(is, 4);
			is.close();
		} catch (Exception e) {
			e.printStackTrace();
		}
	}
	
	private static char choose(char c1, char c2, char c3, Random rand, int length) {
		try {
			int i1 = getIndex(c1);
			int i2 = getIndex(c2);
			int i3 = getIndex(c3);
			Node[] list = tree.get((byte)i1).get((byte)i2).get((byte)i3).next;
			int i4 = rand.nextInt(list.length);
			return getChar(list[i4].value);
		} catch(ArrayIndexOutOfBoundsException e) {
			return ' ';
		}
	}
	
	private static String randomName(Random rand) {
		StringBuilder sb = new StringBuilder();
		
		char c1 = ' ', c2 = ' ', c3 = ' ', c4 = choose(c1, c2, c3, rand, 0);
		sb.append((char)(c4+'A'-'a'));
		int i = 0;
		while (true) {
			char c5 = choose(c2, c3, c4, rand, ++i);
			if (c4 == ' ') {
				if (c5 == ' ') {
					break;
				}
				sb.append(c4);
			}
			c1 = c2;
			c2 = c3;
			c3 = c4;
			c4 = c5;
			if (c5 != ' ')
				sb.append(c5);
		}
		String[] words = sb.toString().split(" ");
		boolean wrongSize = false;
		for(i = 0; i < words.length; i++) {
			if (words[i].length() > 10)
				wrongSize = true;
			// The first word should not be to small.
			if (words[i].length() < 5 && i == 0)
				wrongSize = true;
		}
		if (wrongSize)
			return randomName(rand); // Repeat until a long enough name is generated.
		else
			return sb.toString();
	}
	
	public static void next(StringBuilder current, char c1, char c2, char c3, int depth) {
		int i1 = getIndex(c1);
		int i2 = getIndex(c2);
		int i3 = getIndex(c3);
		Node[] list = tree.get((byte)i1).get((byte)i2).get((byte)i3).next;
		for(int i = 0; i < list.length; i++) {
			char c4 = getChar(list[i].value);
			if (c3 == ' ' && c4 == ' ') {
				if (depth >= 5) {
					System.out.println(current.toString().trim());
				}
			} else if (depth <= 10) {
				StringBuilder sb = new StringBuilder(current);
				if (c3 == ' ') {
					sb.append((char)(c4+'A'-'a'));
				} else {
					sb.append(c4);
				}
				next(sb, c2, c3, c4, depth+1);
			}
		}
	}
	
	public static void generateAll() {
		next(new StringBuilder(), ' ', ' ', ' ', 0);
	}
	
	public static void main(String[] args) {
		readData(args[0]);
		if (args.length == 1) {
			for(int i = 0; i < 100; i++) {
				System.out.println(randomName(new Random()));
			}
		} else if (args[1].equals("all")) {
			generateAll();
		} else {
			for(int i = 0; i < Integer.parseInt(args[1]); i++) {
				System.out.println(randomName(new Random()));
			}
		}
	}
}
