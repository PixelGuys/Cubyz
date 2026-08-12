const std = @import("std");

const main = @import("main");
const vulkan = main.graphics.vulkan;

const c = @import("c");

handle: c.VkCommandBuffer,

const CommandBuffer = @This();

pub fn init() CommandBuffer {
	var self: CommandBuffer = undefined;
	const allocInfo = c.VkCommandBufferAllocateInfo{
		.sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
		.commandPool = vulkan.command_pool.handle,
		.level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
		.commandBufferCount = 1,
	};
	vulkan.checkResult(c.vkAllocateCommandBuffers(vulkan.device, &allocInfo, &self.handle));
	return self;
}

pub fn deinit(self: CommandBuffer) void {
	c.vkFreeCommandBuffers(vulkan.device, vulkan.command_pool.handle, 1, &self.handle);
}

pub fn beginRecording(self: CommandBuffer, flags: c.VkCommandBufferUsageFlags) void {
	const beginInfo = c.VkCommandBufferBeginInfo{
		.sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
		.flags = flags,
	};
	vulkan.checkResult(c.vkBeginCommandBuffer(self.handle, &beginInfo));
}

pub fn endRecording(self: CommandBuffer) void {
	vulkan.checkResult(c.vkEndCommandBuffer(self.handle));
}

pub fn submit(self: CommandBuffer, queue: c.VkQueue, waitSemaphores: []const c.VkSemaphore, waitStages: []const c.VkPipelineStageFlags, signalSemaphores: []const c.VkSemaphore, fence: c.VkFence) void {
	std.debug.assert(waitSemaphores.len == waitStages.len);
	const submitInfo = c.VkSubmitInfo{
		.sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
		.waitSemaphoreCount = @intCast(waitSemaphores.len),
		.pWaitSemaphores = waitSemaphores.ptr,
		.pWaitDstStageMask = waitStages.ptr,
		.commandBufferCount = 1,
		.pCommandBuffers = &self.handle,
		.signalSemaphoreCount = @intCast(signalSemaphores.len),
		.pSignalSemaphores = signalSemaphores.ptr,
	};
	vulkan.checkResult(c.vkQueueSubmit(queue, 1, &submitInfo, fence));
}

const PipelineBarrierOptions = struct {
	memoryBarriers: []const c.VkMemoryBarrier2 = &.{},
	bufferMemoryBarriers: []const c.VkBufferMemoryBarrier2 = &.{},
	imageMemoryBarriers: []const c.VkImageMemoryBarrier2 = &.{},
	flags: c.VkDependencyFlagBits = 0,
};

pub fn pipelineBarrier(self: CommandBuffer, options: PipelineBarrierOptions) void {
	const dependencyInfo: c.VkDependencyInfo = .{
		.sType = c.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
		.dependencyFlags = options.flags,
		.memoryBarrierCount = @intCast(options.memoryBarriers.len),
		.pMemoryBarriers = options.memoryBarriers.ptr,
		.bufferMemoryBarrierCount = @intCast(options.bufferMemoryBarriers.len),
		.pBufferMemoryBarriers = options.bufferMemoryBarriers.ptr,
		.imageMemoryBarrierCount = @intCast(options.imageMemoryBarriers.len),
		.pImageMemoryBarriers = options.imageMemoryBarriers.ptr,
	};
	c.vkCmdPipelineBarrier2(self.handle, &dependencyInfo);
}

const BeginRenderingOptions = struct {
	const StoreOp = enum {
		store,
		dontCare,
		none,

		fn toVulkan(self: StoreOp) c.VkAttachmentStoreOp {
			return switch (self) {
				.store => c.VK_ATTACHMENT_STORE_OP_STORE,
				.dontCare => c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
				.none => c.VK_ATTACHMENT_STORE_OP_NONE,
			};
		}
	};
	const LoadOp = union(enum) {
		load: void,
		dontCare: void,
		clearColor: c.VkClearColorValue,
		clearDepth: c.VkClearDepthStencilValue,

		fn toVulkanEnum(self: LoadOp) c.VkAttachmentLoadOp {
			return switch (self) {
				.load => c.VK_ATTACHMENT_LOAD_OP_LOAD,
				.dontCare => c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
				.clearColor, .clearDepth => c.VK_ATTACHMENT_LOAD_OP_CLEAR,
			};
		}
		fn toVulkanValue(self: LoadOp) c.VkClearValue {
			return switch (self) {
				.load, .dontCare => undefined,
				.clearColor => |color| .{.color = color},
				.clearDepth => |depth| .{.depthStencil = depth},
			};
		}
	};
	const AttachmentInfo = struct {
		imageView: c.VkImageView,
		layout: c.VkImageLayout,
		loadOp: LoadOp,
		storeOp: StoreOp,

		fn toVulkan(self: AttachmentInfo) c.VkRenderingAttachmentInfo {
			return .{
				.sType = c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
				.imageView = self.imageView,
				.imageLayout = self.layout,
				.loadOp = self.loadOp.toVulkanEnum(),
				.storeOp = self.storeOp.toVulkan(),
				.clearValue = self.loadOp.toVulkanValue(),
			};
		}
	};

	textures: []const AttachmentInfo = &.{},
	depthTexture: ?AttachmentInfo = null,
	stencilTexture: ?AttachmentInfo = null,
	layers: u32 = 1,
	viewMask: u32 = 0,
	renderArea: c.VkRect2D,
};

pub fn beginRendering(self: CommandBuffer, options: BeginRenderingOptions) void {
	const textures = main.stackAllocator.alloc(c.VkRenderingAttachmentInfo, options.textures.len);
	defer main.stackAllocator.free(textures);
	for (0..options.textures.len) |i| {
		textures[i] = options.textures[i].toVulkan();
	}

	const depthTexture: ?c.VkRenderingAttachmentInfo = if (options.depthTexture) |d| d.toVulkan() else null;
	const stencilTexture: ?c.VkRenderingAttachmentInfo = if (options.stencilTexture) |s| s.toVulkan() else null;

	const renderingInfo: c.VkRenderingInfo = .{
		.sType = c.VK_STRUCTURE_TYPE_RENDERING_INFO,
		.renderArea = options.renderArea,
		.layerCount = options.layers,
		.viewMask = options.viewMask,
		.colorAttachmentCount = @intCast(textures.len),
		.pColorAttachments = textures.ptr,
		.pDepthAttachment = if (depthTexture) |*d| d else null,
		.pStencilAttachment = if (stencilTexture) |*s| s else null,
	};

	c.vkCmdBeginRendering(self.handle, &renderingInfo);
}

pub fn endRendering(self: CommandBuffer) void {
	c.vkCmdEndRendering(self.handle);
}

pub fn bindPipeline(self: CommandBuffer, pipeline: main.graphics.Pipeline) void {
	c.vkCmdBindPipeline(self.handle, c.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.graphicsPipeline);
	self.setViewport(.{
		.x = 0,
		.y = 0,
		.width = @floatFromInt(vulkan.SwapChain.extent.width),
		.height = @floatFromInt(vulkan.SwapChain.extent.height),
		.minDepth = 0,
		.maxDepth = 1,
	});
	self.setScissor(.{
		.offset = .{.x = 0, .y = 0},
		.extent = vulkan.SwapChain.extent,
	});
}

pub fn setViewport(self: CommandBuffer, viewport: c.VkViewport) void {
	c.vkCmdSetViewport(self.handle, 0, 1, &viewport);
}

pub fn setScissor(self: CommandBuffer, scissor: c.VkRect2D) void {
	c.vkCmdSetScissor(self.handle, 0, 1, &scissor);
}

pub fn drawIndexed(self: CommandBuffer, indexCount: u32, firstVertex: i32) void {
	c.vkCmdDrawIndexed(self.handle, indexCount, 1, 0, firstVertex, 0);
}

pub fn draw(self: CommandBuffer, vertexCount: u32, firstVertex: u32) void {
	c.vkCmdDraw(self.handle, vertexCount, 1, firstVertex, 0);
}

pub fn copyBuffer(self: CommandBuffer, dest: vulkan.Buffer, destOffset: usize, source: vulkan.Buffer, sourceOffset: usize, size: usize) void {
	const info: c.VkCopyBufferInfo2 = .{
		.sType = c.VK_STRUCTURE_TYPE_COPY_BUFFER_INFO_2,
		.dstBuffer = dest.handle,
		.srcBuffer = source.handle,
		.regionCount = 1,
		.pRegions = &.{
			.sType = c.VK_STRUCTURE_TYPE_BUFFER_COPY_2,
			.dstOffset = destOffset,
			.srcOffset = sourceOffset,
			.size = size,
		},
	};
	c.vkCmdCopyBuffer2(self.handle, &info);
}
