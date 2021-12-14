import java.io.*;

// Searches through the mineral names and generates a table of probabilities for every 3 char combination.

public class ProbabilityExtractor {
	static int getIndex(char c) {
		if (c == ' ') return 0;
		if ('a' <= c && c <= 'z') return 1+c-'a';
		if ('A' <= c && c <= 'Z') return 1+c-'A';
		System.err.println("Unknown \'"+c+"\'"+" "+(int)c);
		System.exit(1);
		return 0;
	}
	static char getChar(int i) {
		if (i == 0) return ' ';
		if (i <= 26) return (char)('a'+i-1);
		System.err.println("Unknown "+i);
		System.exit(1);
		return '0';
	}
	public static void main(String[] args) throws IOException {
		int[] number = new int[27*27*27*27];
		try (BufferedReader br = new BufferedReader(new FileReader("./"+args[0]+".txt"))) {
			String line;
			while ((line = br.readLine()) != null) {
				if (line.charAt(0) == '#') continue; // Comments:
				char c1 = ' ', c2 = ' ', c3 = ' ', c4 = ' ';
				for(char c : line.toCharArray()) {
					c1 = c2;
					c2 = c3;
					c3 = c4;
					c4 = c;
					number[getIndex(c1)*27*27*27 + getIndex(c2)*27*27 + getIndex(c3)*27 + getIndex(c4)]++;
				}
				number[getIndex(c2)*27*27*27 + getIndex(c3)*27*27 + getIndex(c4)*27]++;
				number[getIndex(c3)*27*27*27 + getIndex(c4)*27*27]++;
				number[getIndex(c4)*27*27*27]++;
			}
		} catch(Exception e) {}
		DataOutputStream os = new DataOutputStream(new BufferedOutputStream(new FileOutputStream("./"+args[0]+".dat")));
		boolean used;
		// pre-loop to get the length:
		byte n = 0;
		os.writeByte(0);
		outer:
		for(byte i = 0; i < 27; i++) {
			for(byte j = 0; j < 27; j++) {
				for(byte k = 0; k < 27; k++) {
					for(byte l = 0; l < 27; l++) { // pre-loop to get the length
						if (number[i*27*27*27 + j*27*27 + k*27 + l] != 0) {
							n++;
							continue outer;
						}
					}
				}
			}
		}
		os.writeByte(n);
		for(byte i = 0; i < 27; i++) {
			// pre-loop to see if it is actually used:
			used = false;
			outer2:
			for(byte j = 0; j < 27; j++) {
				for(byte k = 0; k < 27; k++) {
					for(byte l = 0; l < 27; l++) { // pre-loop to get the length
						if (number[i*27*27*27 + j*27*27 + k*27 + l] != 0) {
							used = true;
							break outer2;
						}
					}
				}
			}
			if (!used) continue;
			os.writeByte(i);
			// pre-loop to get the length:
			n = 0;
			outer3:
			for(byte j = 0; j < 27; j++) {
				for(byte k = 0; k < 27; k++) {
					for(byte l = 0; l < 27; l++) { // pre-loop to get the length
						if (number[i*27*27*27 + j*27*27 + k*27 + l] != 0) {
							n++;
							continue outer3;
						}
					}
				}
			}
			os.writeByte(n);
			for(byte j = 0; j < 27; j++) {
				// pre-loop to see if it is actually used:
				used = false;
				outer4:
				for(byte k = 0; k < 27; k++) {
					for(byte l = 0; l < 27; l++) { // pre-loop to get the length
						if (number[i*27*27*27 + j*27*27 + k*27 + l] != 0) {
							used = true;
							break outer4;
						}
					}
				}
				if (!used) continue;
				os.writeByte(j);
				// pre-loop to get the length:
				n = 0;
				outer5:
				for(byte k = 0; k < 27; k++) {
					for(byte l = 0; l < 27; l++) { // pre-loop to get the length
						if (number[i*27*27*27 + j*27*27 + k*27 + l] != 0) {
							n++;
							continue outer5;
						}
					}
				}
				os.writeByte(n);
				for(byte k = 0; k < 27; k++) {
					// pre-loop to see if it is actually used:
					used = false;
					for(byte l = 0; l < 27; l++) { // pre-loop to get the length
						if (number[i*27*27*27 + j*27*27 + k*27 + l] != 0) {
							used = true;
							break;
						}
					}
					if (!used) continue;
					os.writeByte(k);
					// pre-loop to get the length:
					n = 0;
					int total = 0;
					for(byte l = 0; l < 27; l++) { // pre-loop to get the length
						if (number[i*27*27*27 + j*27*27 + k*27 + l] != 0) {
							total += number[i*27*27*27 + j*27*27 + k*27 + l];
							n++;
						}
					}
					os.writeByte(n);
					for(byte l = 0; l < 27; l++) {
						if (number[i*27*27*27 + j*27*27 + k*27 + l] != 0) {
							os.writeByte(l);
						}
					}
				}
			}
		}
		os.close();
	}
}
