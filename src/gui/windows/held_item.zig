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
		.{.ratio = 1.0}, // X-axis: right aligned
		.{.ratio = 1.0}, // Y-axis: bottom aligned
	},
	.contentSize = Vec2f{128, 128},
	.isHud = true,
	.showTitleBar = false,
	.hasBackground = false,
	.hideIfMouseIsGrabbed = false,
	.closeable = false,
	.scale = 1.0,
};

// Animation variables
var heldItemTexture: ?Texture = null;
var animationTime: f32 = 0.0;
var lastAnimationUpdate: i64 = 0;

// Player action states
var isMining: bool = false;
var isPlacing: bool = false;
var isRunning: bool = false;
var miningProgress: f32 = 0.0;
var placingProgress: f32 = 0.0;

// Minecraft-style animation parameters
const miningSwingAngle: f32 = std.math.pi / 4.0; // Maximum swing angle during mining
const placingSwingAngle: f32 = std.math.pi / 6.0; // Maximum swing angle during placing
const runningBobAmplitude: f32 = 5.0; // Vertical bobbing amplitude while running
const runningBobFrequency: f32 = 8.0; // Bobbing frequency while running

pub fn init() void {
	// Initialization is done in onOpen
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

	// Get currently selected item
	const currentItem = Player.inventory.getItem(Player.selectedSlot);
	
	if (currentItem == .null) {
		heldItemTexture = null;
		return;
	}

	// Update item texture
	const newTexture = currentItem.getTexture();
	heldItemTexture = newTexture;

	// Detect player action states
	const forwardKey = main.KeyBoard.key("forward");
	const sprintKey = main.KeyBoard.key("sprint");
	isRunning = forwardKey.value > 0.0 and sprintKey.pressed and !Player.crouching;

	// Detect mining and placing actions (by checking timestamps)
	_ = main.timestamp(); // Use timestamp to update animation
	
	// If breaking block, set mining state
	if (main.game.nextBlockBreakTime != null) {
		isMining = true;
		miningProgress += 0.15; // Mining progress
		if (miningProgress > std.math.tau) {
			miningProgress = 0;
		}
	} else {
		isMining = false;
		miningProgress = 0;
	}

	// If placing block, set placing state
	if (main.game.nextBlockPlaceTime != null) {
		isPlacing = true;
		placingProgress += 0.2; // Placing progresses faster
		if (placingProgress > std.math.tau) {
			placingProgress = 0;
		}
	} else {
		isPlacing = false;
		placingProgress = 0;
	}

	// Update animation time
	animationTime += 0.016; // Assuming 60fps
}

pub fn render() void {
	if (heldItemTexture == null) return;

	const texture = heldItemTexture.?;
	
	// Calculate item display position (bottom-right corner with margin)
	const windowSize = main.Window.getWindowSize();
	const scale = gui.scale;
	
	// Base position: offset from bottom-right corner
	const margin: f32 = 80.0;
	const basePosX: f32 = (windowSize[0] / scale) - margin - 64.0;
	const basePosY: f32 = (windowSize[1] / scale) - margin - 64.0;
	
	// Apply animation effects
	var offsetX: f32 = 0;
	var offsetY: f32 = 0;
	var swingRotation: f32 = 0;
	
	if (isMining) {
		// Mining animation: Minecraft-style swinging motion
		// Use sine wave to simulate arm swinging
		const swingPhase = @sin(miningProgress);
		const swingAbs = @abs(swingPhase);
		
		// Main rotation: arc from bottom-right to top-left
		swingRotation = -miningSwingAngle * swingPhase;
		
		// Position offset: displacement during swing
		offsetX = 15.0 * swingPhase;
		offsetY = -10.0 * swingAbs;
		
		// Additional scaling effect (implemented by adjusting draw size)
	} else if (isPlacing) {
		// Placing animation: quick forward thrust
		const placePhase = @sin(placingProgress);
		const placeAbs = @abs(placePhase);
		
		// Smaller rotation angle
		swingRotation = placingSwingAngle * placePhase * 0.6;
		
		// Forward thrust effect
		offsetX = 12.0 * placePhase;
		offsetY = -6.0 * placeAbs;
	} else if (isRunning) {
		// Running animation: vertical bobbing and slight sway
		const bobPhase = @sin(animationTime * runningBobFrequency);
		
		// Vertical bobbing
		offsetY = runningBobAmplitude * bobPhase;
		
		// Slight horizontal sway
		offsetX = 3.0 * bobPhase;
		
		// Slight rotation
		swingRotation = 0.08 * bobPhase;
	} else {
		// Idle state: gentle breathing effect
		const idlePhase = @sin(animationTime * 1.5) * 0.5;
		const idleSway = @cos(animationTime * 1.2) * 0.3;
		
		// Gentle vertical floating
		offsetY = idlePhase;
		
		// Gentle horizontal sway
		offsetX = idleSway;
		
		// Minimal rotation
		swingRotation = idleSway * 0.03;
	}

	const finalPosX = basePosX + offsetX;
	const finalPosY = basePosY + offsetY;
	
	// Save current transform state
	const oldTranslation = draw.setTranslation(.{finalPosX, finalPosY});
	defer draw.restoreTranslation(oldTranslation);
	
	const oldScale = draw.setScale(1.0);
	defer draw.restoreScale(oldScale);
	
	// Draw item texture
	draw.setColor(0xffffffff);
	texture.bindTo(0);
	
	// Adjust item size based on animation state
	var itemSize: Vec2f = .{64, 64};
	if (isMining or isPlacing) {
		// Slightly enlarge during mining and placing
		const scale_phase = if (isMining) miningProgress else placingProgress;
		const sizeMultiplier = 1.0 + 0.1 * @sin(scale_phase);
		itemSize[0] = 64.0 * sizeMultiplier;
		itemSize[1] = 64.0 * sizeMultiplier;
	}
	
	// Draw item (centered)
	const drawPos: Vec2f = .{-itemSize[0] / 2.0, -itemSize[1] / 2.0};
	draw.boundImage(drawPos, itemSize);
	
	// Restore transform
	draw.restoreTranslation(oldTranslation);
	draw.restoreScale(oldScale);
}
