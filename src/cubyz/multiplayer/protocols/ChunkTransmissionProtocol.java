package cubyz.multiplayer.protocols;

import cubyz.client.Cubyz;
import cubyz.multiplayer.Protocol;
import cubyz.multiplayer.UDPConnection;
import cubyz.rendering.VisibleChunk;
import cubyz.utils.ThreadPool;
import cubyz.utils.math.Bits;
import cubyz.world.ChunkData;
import cubyz.world.NormalChunk;
import cubyz.world.ReducedChunkVisibilityData;
import cubyz.world.save.ChunkIO;

import java.util.Arrays;

public class ChunkTransmissionProtocol extends Protocol {
	public ChunkTransmissionProtocol() {
		super((byte)3, true);
	}

	@Override
	public void receive(UDPConnection conn, byte[] data, int offset, int length) {
		int wx = Bits.getInt(data, offset);
		int wy = Bits.getInt(data, offset + 4);
		int wz = Bits.getInt(data, offset + 8);
		int voxelSize = Bits.getInt(data, offset + 12);
		offset += 16;
		length -= 16;
		if(voxelSize == 1) {
			byte[] chunkData = ChunkIO.decompressChunk(data, offset, length);
			if(chunkData == null)
				return;
			VisibleChunk ch = new VisibleChunk(Cubyz.world, wx, wy, wz);
			ch.loadFromByteArray(chunkData, chunkData.length);
			ThreadPool.addTask(new ChunkLoadTask(ch));
		} else {
			data = ChunkIO.decompressChunk(data, offset, length);
			length = data.length;
			offset = 0;
			int size = length/8;
			byte[] x = Arrays.copyOfRange(data, offset, offset + size);
			byte[] y = Arrays.copyOfRange(data, offset + size, offset + 2*size);
			byte[] z = Arrays.copyOfRange(data, offset + 2*size, offset + 3*size);
			byte[] neighbors = Arrays.copyOfRange(data, offset + 3*size, offset + 4*size);
			int[] visibleBlocks = new int[size];
			offset += 4*size;
			for(int i = 0; i < size; i++) {
				visibleBlocks[i] = Bits.getInt(data, offset);
				offset += 4;
			}
			ReducedChunkVisibilityData visDat = new ReducedChunkVisibilityData(wx, wy, wz, voxelSize, x, y, z, neighbors, visibleBlocks);
			Cubyz.chunkTree.updateChunkMesh(visDat);
		}
	}

	public void sendChunk(UDPConnection conn, ChunkData ch) {
		byte[] data;
		if(ch instanceof NormalChunk) {
			byte[] compressedChunk = ChunkIO.compressChunk((NormalChunk)ch);
			data = new byte[compressedChunk.length + 16];
			System.arraycopy(compressedChunk, 0, data, 16, compressedChunk.length);
		} else if(ch instanceof ReducedChunkVisibilityData) {
			ReducedChunkVisibilityData visDat = (ReducedChunkVisibilityData)ch;
			data = new byte[visDat.size*8];
			System.arraycopy(visDat.x, 0, data, 0, visDat.size);
			System.arraycopy(visDat.y, 0, data, visDat.size, visDat.size);
			System.arraycopy(visDat.z, 0, data, 2*visDat.size, visDat.size);
			System.arraycopy(visDat.neighbors, 0, data, 3*visDat.size, visDat.size);
			int offset = 4*visDat.size;
			for(int i = 0; i < visDat.size; i++) {
				Bits.putInt(data, offset, visDat.visibleBlocks[i]);
				offset += 4;
			}
			byte[] compressedData = ChunkIO.compressChunk(data);
			data = new byte[compressedData.length + 16];
			System.arraycopy(compressedData, 0, data, 16, compressedData.length);
		} else {
			assert false: "Invalid chunk class to send over the network " + ch.getClass() + ".";
			return;
		}
		Bits.putInt(data, 0, ch.wx);
		Bits.putInt(data, 4, ch.wy);
		Bits.putInt(data, 8, ch.wz);
		Bits.putInt(data, 12, ch.voxelSize);
		conn.send(this, data);
	}

	private static class ChunkLoadTask extends ThreadPool.Task {
		private final VisibleChunk ch;
		public ChunkLoadTask(VisibleChunk ch) {
			this.ch = ch;
		}
		@Override
		public float getPriority() {
			return ch.getPriority(Cubyz.player);
		}

		@Override
		public boolean isStillNeeded() {
			return Cubyz.chunkTree.findNode(ch) != null;
		}

		@Override
		public void run() {
			ch.load();
		}
	}
}
