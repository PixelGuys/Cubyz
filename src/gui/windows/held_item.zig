const std = @import("std");

const main = @import("main");
const graphics = main.graphics;
const draw = graphics.draw;
const Texture = graphics.Texture;
const Vec2f = main.vec.Vec2f;
const Player = main.game.Player;

const gui = @import("../gui.zig");

pub var window = gui.GuiWindow{
	.relativePosition = .{
		.{.ratio = 1.0}, // X轴：靠右
		.{.ratio = 1.0}, // Y轴：靠下
	},
	.contentSize = Vec2f{128, 128},
	.isHud = true,
	.showTitleBar = false,
	.hasBackground = false,
	.hideIfMouseIsGrabbed = false,
	.closeable = false,
	.scale = 1.0,
};

// 动画相关变量
var heldItemTexture: ?Texture = null;
var animationTime: f32 = 0.0;
var lastAnimationUpdate: i64 = 0;

// 玩家动作状态
var isMining: bool = false;
var isPlacing: bool = false;
var isRunning: bool = false;
var miningProgress: f32 = 0.0;
var placingProgress: f32 = 0.0;

// Minecraft风格的动画参数
const miningSwingAngle: f32 = std.math.pi / 4.0; // 挖掘时的最大摆动角度
const placingSwingAngle: f32 = std.math.pi / 6.0; // 放置时的最大摆动角度
const runningBobAmplitude: f32 = 5.0; // 奔跑时的上下浮动幅度
const runningBobFrequency: f32 = 8.0; // 奔跑时的浮动频率

pub fn init() void {
	// 初始化在onOpen中完成
}

pub fn deinit() void {
	if (heldItemTexture) |texture| {
		texture.deinit();
		heldItemTexture = null;
	}
}

pub fn onOpen() void {
	window.rootComponent = null;
	gui.updateWindowPositions();
}

pub fn onClose() void {
	if (window.rootComponent) |*comp| {
		comp.deinit();
	}
}

pub fn update() void {
	Player.mutex.lock();
	defer Player.mutex.unlock();

	// 获取当前选中的物品
	const currentItem = Player.inventory.getItem(Player.selectedSlot);
	
	if (currentItem == .null) {
		heldItemTexture = null;
		return;
	}

	// 更新物品纹理
	const newTexture = currentItem.getTexture();
	heldItemTexture = newTexture;

	// 检测玩家动作状态
	const forwardKey = main.KeyBoard.key("forward");
	const sprintKey = main.KeyBoard.key("sprint");
	isRunning = forwardKey.value > 0.0 and sprintKey.pressed and !Player.crouching;

	// 检测挖掘和放置动作（通过检查时间戳）
	_ = main.timestamp(); // 使用时间戳更新动画
	
	// 如果正在破坏方块，设置挖掘状态
	if (main.game.nextBlockBreakTime != null) {
		isMining = true;
		miningProgress += 0.15; // 挖掘进度
		if (miningProgress > std.math.tau) {
			miningProgress = 0;
		}
	} else {
		isMining = false;
		miningProgress = 0;
	}

	// 如果正在放置方块，设置放置状态
	if (main.game.nextBlockPlaceTime != null) {
		isPlacing = true;
		placingProgress += 0.2; // 放置进度更快
		if (placingProgress > std.math.tau) {
			placingProgress = 0;
		}
	} else {
		isPlacing = false;
		placingProgress = 0;
	}

	// 更新动画时间
	animationTime += 0.016; // 假设60fps
}

pub fn render() void {
	if (heldItemTexture == null) return;

	const texture = heldItemTexture.?;
	
	// 计算物品显示位置（右下角，距离边缘一定距离）
	const windowSize = main.Window.getWindowSize();
	const scale = gui.scale;
	
	// 基础位置：右下角偏移
	const margin: f32 = 80.0;
	const basePosX: f32 = (windowSize[0] / scale) - margin - 64.0;
	const basePosY: f32 = (windowSize[1] / scale) - margin - 64.0;
	
	// 应用动画效果
	var offsetX: f32 = 0;
	var offsetY: f32 = 0;
	var swingRotation: f32 = 0;
	
	if (isMining) {
		// 挖掘动画：类似Minecraft的挥动效果
		// 使用正弦波模拟手臂挥动
		const swingPhase = @sin(miningProgress);
		const swingAbs = @abs(swingPhase);
		
		// 主要旋转：从右下到左上的弧线
		swingRotation = -miningSwingAngle * swingPhase;
		
		// 位置偏移：挥动时的位移
		offsetX = 15.0 * swingPhase;
		offsetY = -10.0 * swingAbs;
		
		// 额外的缩放效果（通过调整绘制大小实现）
	} else if (isPlacing) {
		// 放置动画：快速前推效果
		const placePhase = @sin(placingProgress);
		const placeAbs = @abs(placePhase);
		
		// 较小的旋转角度
		swingRotation = placingSwingAngle * placePhase * 0.6;
		
		// 向前推进的效果
		offsetX = 12.0 * placePhase;
		offsetY = -6.0 * placeAbs;
	} else if (isRunning) {
		// 奔跑动画：上下浮动和轻微摇摆
		const bobPhase = @sin(animationTime * runningBobFrequency);
		
		// 上下浮动
		offsetY = runningBobAmplitude * bobPhase;
		
		// 轻微的左右摇摆
		offsetX = 3.0 * bobPhase;
		
		// 轻微旋转
		swingRotation = 0.08 * bobPhase;
	} else {
		// 空闲状态：轻微的呼吸效果
		const idlePhase = @sin(animationTime * 1.5) * 0.5;
		const idleSway = @cos(animationTime * 1.2) * 0.3;
		
		// 轻微的上下浮动
		offsetY = idlePhase;
		
		// 轻微的左右摇摆
		offsetX = idleSway;
		
		// 极小的旋转
		swingRotation = idleSway * 0.03;
	}

	const finalPosX = basePosX + offsetX;
	const finalPosY = basePosY + offsetY;
	
	// 保存当前的变换状态
	const oldTranslation = draw.setTranslation(.{finalPosX, finalPosY});
	defer draw.restoreTranslation(oldTranslation);
	
	const oldScale = draw.setScale(1.0);
	defer draw.restoreScale(oldScale);
	
	// 绘制物品纹理
	draw.setColor(0xffffffff);
	texture.bindTo(0);
	
	// 根据动画状态调整物品大小
	var itemSize: Vec2f = .{64, 64};
	if (isMining or isPlacing) {
		// 挖掘和放置时稍微放大
		const scale_phase = if (isMining) miningProgress else placingProgress;
		const sizeMultiplier = 1.0 + 0.1 * @sin(scale_phase);
		itemSize[0] = 64.0 * sizeMultiplier;
		itemSize[1] = 64.0 * sizeMultiplier;
	}
	
	// 绘制物品（居中绘制）
	const drawPos: Vec2f = .{-itemSize[0] / 2.0, -itemSize[1] / 2.0};
	draw.boundImage(drawPos, itemSize);
	
	// 恢复变换
	draw.restoreTranslation(oldTranslation);
	draw.restoreScale(oldScale);
}
