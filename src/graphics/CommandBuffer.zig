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

pub fn pipelineBarrier(self: CommandBuffer, options: struct { memoryBarriers: []const c.VkMemoryBarrier2 = &.{}, bufferMemoryBarriers: []const c.VkBufferMemoryBarrier2 = &.{}, imageMemoryBarriers: []const c.VkImageMemoryBarrier2 = &.{}, flags: c.VkDependencyFlagBits = 0 }) void {
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
