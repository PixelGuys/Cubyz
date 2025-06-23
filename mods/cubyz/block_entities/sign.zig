const std = @import("std");

const main = @import("main");
const graphics = main.graphics;
const c = graphics.c;
const utils = main.utils;
const BinaryReader = utils.BinaryReader;
const BinaryWriter = utils.BinaryWriter;
const vec = main.vec;
const Mat4f = vec.Mat4f;
const Vec3i = vec.Vec3i;
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;
const Chunk = main.chunk.Chunk;
const block_entity = main.block_entity;
const UpdateEvent = block_entity.UpdateEvent;
const EventStatus = block_entity.EventStatus;
const BlockEntityIndex = block_entity.BlockEntityIndex;
const BlockEntityDataStorage = block_entity.BlockEntityDataStorage;

const StorageServer = BlockEntityDataStorage(struct {
	text: []const u8,
});
const StorageClient = BlockEntityDataStorage(struct {
	text: []const u8,
	renderedTexture: ?main.graphics.Texture = null,
	blockPos: Vec3i,
	block: main.blocks.Block,

	fn deinit(self: @This()) void {
		main.globalAllocator.free(self.text);
		if(self.renderedTexture) |texture| {
			textureDeinitLock.lock();
			defer textureDeinitLock.unlock();
			textureDeinitList.append(texture);
		}
	}
});
var textureDeinitList: main.List(graphics.Texture) = undefined;
var textureDeinitLock: std.Thread.Mutex = .{};
var pipeline: graphics.Pipeline = undefined;
var uniforms: struct {
	ambientLight: c_int,
	projectionMatrix: c_int,
	viewMatrix: c_int,
	playerPositionInteger: c_int,
	playerPositionFraction: c_int,
	quadIndex: c_int,
	lightData: c_int,
	chunkPos: c_int,
	blockPos: c_int,
} = undefined;

// TODO: Load these from some per-block settings
const textureWidth = 128;
const textureHeight = 72;
const textureMargin = 4;

pub fn init() void {
	StorageServer.init();
	StorageClient.init();
	textureDeinitList = .init(main.globalAllocator);

	pipeline = graphics.Pipeline.init(
		"assets/cubyz/shaders/block_entity/sign.vert",
		"assets/cubyz/shaders/block_entity/sign.frag",
		"",
		&uniforms,
		.{},
		.{.depthTest = true, .depthCompare = .equal, .depthWrite = false},
		.{.attachments = &.{.alphaBlending}},
	);
}
pub fn deinit() void {
	while(textureDeinitList.popOrNull()) |texture| {
		texture.deinit();
	}
	textureDeinitList.deinit();
	pipeline.deinit();
	StorageServer.deinit();
	StorageClient.deinit();
}
pub fn reset() void {
	StorageServer.reset();
	StorageClient.reset();
}

pub fn onUnloadClient(dataIndex: BlockEntityIndex) void {
	StorageClient.mutex.lock();
	defer StorageClient.mutex.unlock();
	const entry = StorageClient.removeAtIndex(dataIndex) orelse unreachable;
	entry.deinit();
}
pub fn onUnloadServer(dataIndex: BlockEntityIndex) void {
	StorageServer.mutex.lock();
	defer StorageServer.mutex.unlock();
	const entry = StorageServer.removeAtIndex(dataIndex) orelse unreachable;
	main.globalAllocator.free(entry.text);
}
pub fn onInteract(pos: Vec3i, chunk: *Chunk) EventStatus {
	if(main.KeyBoard.key("shift").pressed) return .ignored;

	StorageClient.mutex.lock();
	defer StorageClient.mutex.unlock();
	const data = StorageClient.get(pos, chunk);
	main.gui.windowlist.sign_editor.openFromSignData(pos, if(data) |_data| _data.text else "");

	return .handled;
}

pub fn onLoadClient(pos: Vec3i, chunk: *Chunk, reader: *BinaryReader) BinaryReader.AllErrors!void {
	return updateClientData(pos, chunk, .{.createOrUpdate = reader});
}
pub fn updateClientData(pos: Vec3i, chunk: *Chunk, event: UpdateEvent) BinaryReader.AllErrors!void {
	if(event == .remove or event.createOrUpdate.remaining.len == 0) {
		const entry = StorageClient.remove(pos, chunk) orelse return;
		entry.deinit();
		return;
	}

	StorageClient.mutex.lock();
	defer StorageClient.mutex.unlock();

	const data = StorageClient.getOrPut(pos, chunk);
	if(data.foundExisting) {
		data.valuePtr.deinit();
	}
	data.valuePtr.* = .{
		.blockPos = pos,
		.block = chunk.data.getValue(chunk.getLocalBlockIndex(pos)),
		.renderedTexture = null,
		.text = main.globalAllocator.dupe(u8, event.createOrUpdate.remaining),
	};
}

pub fn onLoadServer(pos: Vec3i, chunk: *Chunk, reader: *BinaryReader) BinaryReader.AllErrors!void {
	return updateServerData(pos, chunk, .{.createOrUpdate = reader});
}
pub fn updateServerData(pos: Vec3i, chunk: *Chunk, event: UpdateEvent) BinaryReader.AllErrors!void {
	if(event == .remove or event.createOrUpdate.remaining.len == 0) {
		const entry = StorageServer.remove(pos, chunk) orelse return;
		main.globalAllocator.free(entry.text);
		return;
	}

	StorageServer.mutex.lock();
	defer StorageServer.mutex.unlock();

	const data = StorageServer.getOrPut(pos, chunk);
	if(data.foundExisting) main.globalAllocator.free(data.valuePtr.text);
	data.valuePtr.text = main.globalAllocator.dupe(u8, event.createOrUpdate.remaining);
}

pub const onStoreServerToClient = onStoreServerToDisk;
pub fn onStoreServerToDisk(dataIndex: BlockEntityIndex, writer: *BinaryWriter) void {
	StorageServer.mutex.lock();
	defer StorageServer.mutex.unlock();

	const data = StorageServer.getByIndex(dataIndex) orelse return;
	writer.writeSlice(data.text);
}
pub fn getServerToClientData(pos: Vec3i, chunk: *Chunk, writer: *BinaryWriter) void {
	StorageServer.mutex.lock();
	defer StorageServer.mutex.unlock();

	const data = StorageServer.get(pos, chunk) orelse return;
	writer.writeSlice(data.text);
}

pub fn getClientToServerData(pos: Vec3i, chunk: *Chunk, writer: *BinaryWriter) void {
	StorageClient.mutex.lock();
	defer StorageClient.mutex.unlock();

	const data = StorageClient.get(pos, chunk) orelse return;
	writer.writeSlice(data.text);
}

pub fn updateTextFromClient(pos: Vec3i, newText: []const u8) void {
	{
		const mesh = main.renderer.mesh_storage.getMeshAndIncreaseRefCount(.initFromWorldPos(pos, 1)) orelse return;
		defer mesh.decreaseRefCount();
		mesh.mutex.lock();
		defer mesh.mutex.unlock();
		const index = mesh.chunk.getLocalBlockIndex(pos);
		const block = mesh.chunk.data.getValue(index);
		const blockEntity = block.blockEntity() orelse return;
		if(!std.mem.eql(u8, blockEntity.id, "sign")) return;

		StorageClient.mutex.lock();
		defer StorageClient.mutex.unlock();

		const data = StorageClient.getOrPut(pos, mesh.chunk);
		if(data.foundExisting) {
			data.valuePtr.deinit();
		}
		data.valuePtr.* = .{
			.blockPos = pos,
			.block = mesh.chunk.data.getValue(mesh.chunk.getLocalBlockIndex(pos)),
			.renderedTexture = null,
			.text = main.globalAllocator.dupe(u8, newText),
		};
	}

	main.network.Protocols.blockEntityUpdate.sendClientDataUpdateToServer(main.game.world.?.conn, pos);
}

pub fn renderAll(projectionMatrix: Mat4f, ambientLight: Vec3f, playerPos: Vec3d) void {
	var oldFramebufferBinding: c_int = undefined;
	c.glGetIntegerv(c.GL_DRAW_FRAMEBUFFER_BINDING, &oldFramebufferBinding);

	StorageClient.mutex.lock();
	defer StorageClient.mutex.unlock();

	for(StorageClient.storage.dense.items) |*signData| {
		if(signData.renderedTexture != null) continue;

		c.glViewport(0, 0, textureWidth, textureHeight);
		defer c.glViewport(0, 0, main.Window.width, main.Window.height);

		var finalFrameBuffer: graphics.FrameBuffer = undefined;
		finalFrameBuffer.init(false, c.GL_NEAREST, c.GL_REPEAT);
		finalFrameBuffer.updateSize(textureWidth, textureHeight, c.GL_RGBA8);
		finalFrameBuffer.bind();
		finalFrameBuffer.clear(.{0, 0, 0, 0});
		signData.renderedTexture = .{.textureID = finalFrameBuffer.texture};
		defer c.glDeleteFramebuffers(1, &finalFrameBuffer.frameBuffer);

		const oldTranslation = graphics.draw.setTranslation(.{textureMargin, textureMargin});
		defer graphics.draw.restoreTranslation(oldTranslation);
		const oldClip = graphics.draw.setClip(.{textureWidth - 2*textureMargin, textureHeight - 2*textureMargin});
		defer graphics.draw.restoreClip(oldClip);

		var textBuffer = graphics.TextBuffer.init(main.stackAllocator, signData.text, .{.color = 0x000000}, false, .center); // TODO: Make the color configurable in the zon
		defer textBuffer.deinit();
		_ = textBuffer.calculateLineBreaks(16, textureWidth - 2*textureMargin);
		textBuffer.renderTextWithoutShadow(0, 0, 16);
	}

	c.glBindFramebuffer(c.GL_FRAMEBUFFER, @bitCast(oldFramebufferBinding));

	pipeline.bind(null);
	c.glBindVertexArray(main.renderer.chunk_meshing.vao);

	c.glUniform3f(uniforms.ambientLight, ambientLight[0], ambientLight[1], ambientLight[2]);
	c.glUniformMatrix4fv(uniforms.projectionMatrix, 1, c.GL_TRUE, @ptrCast(&projectionMatrix));
	c.glUniformMatrix4fv(uniforms.viewMatrix, 1, c.GL_TRUE, @ptrCast(&main.game.camera.viewMatrix));
	c.glUniform3i(uniforms.playerPositionInteger, @intFromFloat(@floor(playerPos[0])), @intFromFloat(@floor(playerPos[1])), @intFromFloat(@floor(playerPos[2])));
	c.glUniform3f(uniforms.playerPositionFraction, @floatCast(@mod(playerPos[0], 1)), @floatCast(@mod(playerPos[1], 1)), @floatCast(@mod(playerPos[2], 1)));

	outer: for(StorageClient.storage.dense.items) |signData| {
		if(main.blocks.meshes.model(signData.block).model().internalQuads.len == 0) continue;
		const quad = main.blocks.meshes.model(signData.block).model().internalQuads[0];

		signData.renderedTexture.?.bindTo(0);

		c.glUniform1i(uniforms.quadIndex, quad.index);
		const mesh = main.renderer.mesh_storage.getMeshAndIncreaseRefCount(main.chunk.ChunkPosition.initFromWorldPos(signData.blockPos, 1)) orelse continue :outer;
		defer mesh.decreaseRefCount();
		mesh.lightingData[0].lock.lockRead();
		defer mesh.lightingData[0].lock.unlockRead();
		mesh.lightingData[1].lock.lockRead();
		defer mesh.lightingData[1].lock.unlockRead();
		const light: [4]u32 = main.renderer.chunk_meshing.PrimitiveMesh.getLight(mesh, signData.blockPos -% Vec3i{mesh.pos.wx, mesh.pos.wy, mesh.pos.wz}, 0, quad);
		c.glUniform4ui(uniforms.lightData, light[0], light[1], light[2], light[3]);
		c.glUniform3i(uniforms.chunkPos, signData.blockPos[0] & ~main.chunk.chunkMask, signData.blockPos[1] & ~main.chunk.chunkMask, signData.blockPos[2] & ~main.chunk.chunkMask);
		c.glUniform3i(uniforms.blockPos, signData.blockPos[0] & main.chunk.chunkMask, signData.blockPos[1] & main.chunk.chunkMask, signData.blockPos[2] & main.chunk.chunkMask);

		c.glDrawElements(c.GL_TRIANGLES, 6, c.GL_UNSIGNED_INT, null);
	}
}