// used for text rendering
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

// used for rendering graphics and windows
#include <glad/gl.h>
// NOTE(blackedout): glad is currently not used on macOS, so use Vulkan header from the Vulkan-Headers repository instead
#ifdef __MACH__
#include <vulkan/vulkan.h>
#include <vulkan/vulkan_beta.h>
#else
#include <glad/vulkan.h>
#endif
#include <GLFW/glfw3.h>

// used for exporting and reading images to/from files
#include <stb/stb_image.h>
#include <stb/stb_image_write.h>
