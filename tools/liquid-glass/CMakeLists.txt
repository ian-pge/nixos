cmake_minimum_required(VERSION 3.25)
project(liquid_glass VERSION 0.2.3 LANGUAGES C CXX)
find_package(PkgConfig REQUIRED)
pkg_check_modules(HYPRLAND REQUIRED IMPORTED_TARGET hyprland)
pkg_check_modules(GLES REQUIRED IMPORTED_TARGET glesv2 egl)
pkg_check_modules(WAYLAND REQUIRED IMPORTED_TARGET wayland-server)
find_program(WAYLAND_SCANNER wayland-scanner REQUIRED)
set(PROTOCOL ${CMAKE_CURRENT_SOURCE_DIR}/protocol/liquid-glass-v1.xml)
add_custom_command(OUTPUT liquid-glass-server.h liquid-glass-protocol.c
  COMMAND ${WAYLAND_SCANNER} server-header ${PROTOCOL} liquid-glass-server.h
  COMMAND ${WAYLAND_SCANNER} private-code ${PROTOCOL} liquid-glass-protocol.c
  DEPENDS ${PROTOCOL})
# Wayland objects outlive a render-plugin unload. Keep only the tiny inert
# transport resident; it contains no Hyprland hooks, rendering or GPU resources.
add_library(liquid-glass-wire SHARED src/wire.cpp liquid-glass-server.h liquid-glass-protocol.c)
target_compile_features(liquid-glass-wire PRIVATE cxx_std_20)
target_include_directories(liquid-glass-wire PRIVATE ${CMAKE_CURRENT_BINARY_DIR})
target_link_libraries(liquid-glass-wire PRIVATE PkgConfig::WAYLAND)
target_link_options(liquid-glass-wire PRIVATE "LINKER:-z,nodelete")

file(READ shaders/fullscreen.vert VERTEX)
file(READ shaders/seed.frag SEED)
file(READ shaders/distance.frag DISTANCE)
file(READ shaders/resolve.frag RESOLVE)
file(READ shaders/smooth.frag SMOOTH)
file(READ shaders/glass.frag GLASS)
file(READ shaders/analytic.frag ANALYTIC)
file(READ shaders/analytic.vert ANALYTIC_VERTEX)
configure_file(src/shaders.hpp.in generated/shaders.hpp @ONLY)
add_library(liquid-glass SHARED src/plugin.cpp)
target_compile_features(liquid-glass PRIVATE cxx_std_26)
target_compile_options(liquid-glass PRIVATE -Wall -Wextra -Wpedantic -fno-gnu-unique)
target_include_directories(liquid-glass PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/generated")
target_link_libraries(liquid-glass PRIVATE PkgConfig::HYPRLAND PkgConfig::GLES liquid-glass-wire)
install(TARGETS liquid-glass liquid-glass-wire LIBRARY DESTINATION lib)

# Explicit, offscreen hardware benchmark; never installed or run during Nix
# builds, and never adds timer queries to the live compositor's render loop.
option(LIQUID_GLASS_GPU_BENCH "Build the standalone shader GPU benchmark" OFF)
if(LIQUID_GLASS_GPU_BENCH)
  add_executable(glass-gpu-bench tests/gpu-bench.cpp)
  target_compile_features(glass-gpu-bench PRIVATE cxx_std_20)
  target_compile_options(glass-gpu-bench PRIVATE -O2 -Wall -Wextra -Wpedantic)
  target_link_libraries(glass-gpu-bench PRIVATE PkgConfig::GLES)
endif()

enable_testing()
find_program(GLSLANG glslangValidator REQUIRED)
foreach(shader fullscreen.vert seed.frag distance.frag resolve.frag smooth.frag glass.frag analytic.frag analytic.vert)
  add_test(NAME shader-${shader} COMMAND ${GLSLANG} ${CMAKE_CURRENT_SOURCE_DIR}/shaders/${shader})
endforeach()
