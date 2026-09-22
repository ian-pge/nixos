cmake_minimum_required(VERSION 3.25)
project(liquid_glass_client VERSION 0.2.0 LANGUAGES C CXX)
find_package(Qt6 6.11 REQUIRED COMPONENTS Quick Qml WaylandClient GuiPrivate)
find_package(PkgConfig REQUIRED)
pkg_check_modules(WAYLAND REQUIRED IMPORTED_TARGET wayland-client)
find_program(WAYLAND_SCANNER wayland-scanner REQUIRED)
set(PROTOCOL ${CMAKE_CURRENT_SOURCE_DIR}/../protocol/liquid-glass-v1.xml)
add_custom_command(OUTPUT liquid-glass-client.h liquid-glass-protocol.c
  COMMAND ${WAYLAND_SCANNER} client-header ${PROTOCOL} liquid-glass-client.h
  COMMAND ${WAYLAND_SCANNER} private-code ${PROTOCOL} liquid-glass-protocol.c
  DEPENDS ${PROTOCOL})
qt_standard_project_setup()
qt_add_library(glassclient SHARED)
qt_add_qml_module(glassclient URI Local.LiquidGlass VERSION 1.0
  OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/Local/LiquidGlass
  SOURCES glassshape.hpp glassshape.cpp liquid-glass-client.h liquid-glass-protocol.c)
target_include_directories(glassclient PRIVATE ${CMAKE_CURRENT_BINARY_DIR})
target_compile_features(glassclient PRIVATE cxx_std_20)
target_link_libraries(glassclient PRIVATE Qt6::Quick Qt6::WaylandClient Qt6::GuiPrivate PkgConfig::WAYLAND)
install(TARGETS glassclient glassclientplugin LIBRARY DESTINATION lib/qt-6/qml/Local/LiquidGlass)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/Local/LiquidGlass/qmldir
  ${CMAKE_CURRENT_BINARY_DIR}/Local/LiquidGlass/glassclient.qmltypes DESTINATION lib/qt-6/qml/Local/LiquidGlass)
