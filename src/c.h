// used for text rendering and layouting
#include <freetype/ftadvanc.h>
#include <freetype/ftbbox.h>
#include <freetype/ftbitmap.h>
#include <freetype/ftcolor.h>
#include <freetype/ftlcdfil.h>
#include <freetype/ftsizes.h>
#include <freetype/ftstroke.h>
#include <freetype/fttrigon.h>
#include <freetype/ftsynth.h>
#include <hb.h>
#include <hb-ft.h>

// used for rendering, windowing and inputs
#include <glad/gl.h>
// NOTE(blackedout): glad is currently not used on macOS, so use Vulkan header from the Vulkan-Headers repository instead
#ifdef __MACH__
#include <vulkan/vulkan.h>
#include <vulkan/vulkan_beta.h>
#else
#include <glad/vulkan.h>
#endif
#include <GLFW/glfw3.h>

// used for reading and writing image files
#include <stb/stb_image.h>
#include <stb/stb_image_write.h>
