#
# CMAKE file for GOA - this is just a draft/poc CMake file
#
set(CMAKE_OSX_ARCHITECTURES x86_64)
set(CMAKE_OSX_SYSROOT /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk)
cmake_minimum_required(VERSION 2.8)


project(m68ksim)

set(CMAKE_ASM_SOURCE_FILE_EXTENSION .s)
set(CMAKE_SOURCE_DIR ./src)
set(CMAKE_BINARY_DIR ./bin)
set(EXECUTABLE_OUTPUT_PATH ${CMAKE_BINARY_DIR})
set(LIBRARY_OUTPUT_PATH ./lib)


set(CMAKE_BUILD_TYPE Debug)

include_directories("${PROJECT_SOURCE_DIR}")


# sim core 
list(APPEND srcsim_lib src/simhelpers.cpp src/strutil.cpp src/simulator.c src/m68kcpu.c src/m68kdasm.c)
list(APPEND srcsim_lib dep/AmigaHunkParser/amiga_hunk_parser.c)

# generated src
list(APPEND srcsim_gen src/m68kops.c src/m68kopac.c src/m68kopdm.c src/m68kopnz.c)
#console app
list(APPEND srcsim_con src/sim.cpp)
# generator
list(APPEND srcgen src/m68kmake.c)

# assembler source
list(APPEND srcasm src/polyfill.s)

list(APPEND imguisrc dep/imgui/imgui.cpp)
list(APPEND imguisrc dep/imgui/imgui_widgets.cpp)
list(APPEND imguisrc dep/imgui/imgui_draw.cpp)
list(APPEND imguisrc dep/imgui/imgui_demo.cpp)
list(APPEND imguisrc dep/ImGuiColorTextEdit/TextEditor.cpp)


add_library(imgui STATIC ${imguisrc})
target_include_directories(imgui PUBLIC dep/imgui)


add_executable(generator ${srcgen})
add_executable(sim ${srcsim_con} ${srcsim_lib} ${srcsim_gen})


set_property(TARGET imgui PROPERTY CXX_STANDARD 11)

set_property(TARGET sim PROPERTY CXX_STANDARD 11)


target_include_directories(generator PUBLIC ./include)
target_include_directories(sim PRIVATE /usr/local/include)
target_include_directories(sim PRIVATE dep/AmigaHunkParser)


add_custom_command(
		TARGET ${srcsim_gen}
		COMMAND generator
		WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}/src
		DEPENDS generator)

add_custom_command(
		OUTPUT polyfill.exe
		WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}		
		COMMAND vasmm68k_mot -phxass -m68060 -Fhunk -linedebug -o ${CMAKE_CURRENT_BINARY_DIR}/polyfill.o ${srcasm}
		COMMAND vlink -o ${CMAKE_CURRENT_BINARY_DIR}/polyfill.exe ${CMAKE_CURRENT_BINARY_DIR}/polyfill.o
		DEPENDS ${srcasm}
		VERBATIM)

add_custom_target(dummy DEPENDS polyfill.exe)

#
# Debugger UI
#
list(APPEND uisrc src/ui/main.cpp)
list(APPEND uisrc src/ui/app.cpp)
list(APPEND uisrc src/ui/expsolver.cpp)
list(APPEND uisrc src/ui/tokenizer.cpp)
list(APPEND uisrc dep/imgui/examples/imgui_impl_glfw.cpp)
list(APPEND uisrc dep/imgui/examples/imgui_impl_opengl3.cpp)
list(APPEND uisrc dep/imgui/examples/libs/gl3w/GL/gl3w.c)
#list(APPEND uisrc dep/AmigaHunkParser/amiga_hunk_parser.c)


set(CMAKE_LIBRARY_PATH ${CMAKE_LIBRARY_PATH} /usr/local/lib)
find_library(COCOA_FRAMEWORK Cocoa)
find_library(IOKIT_FRAMEWORK IOKit)
find_library(CORE_FRAMEWORK CoreFoundation)
find_library(CORE_VIDEO_FRAMEWORK CoreVideo)
find_library(OPENGL_FRAMEWORK OpenGL)
find_library(GLFW NAMES libglfw3.a PATHS)

message(STATUS "Cocoa Framework path: ${COCOA_FRAMEWORK}")
message(STATUS "OpenGL Framework path: ${OPENGL_FRAMEWORK}")
message(STATUS "GLFW library path: ${GLFW}")
message(STATUS "OSX Architectures: ${CMAKE_OSX_ARCHITECTURES}")

target_link_libraries(generator ${COCOA_FRAMEWORK} ${IOKIT_FRAMEWORK} ${CORE_VIDEO_FRAMEWORK} ${OPENGL_FRAMEWORK} ${CORE_FRAMEWORK} ${GLFW})
target_link_libraries(sim ${COCOA_FRAMEWORK} ${IOKIT_FRAMEWORK} ${CORE_VIDEO_FRAMEWORK} ${OPENGL_FRAMEWORK} ${CORE_FRAMEWORK} ${GLFW})


add_executable(dbgui ${uisrc} ${srcsim_lib} ${srcsim_gen})
target_link_libraries(dbgui imgui ${COCOA_FRAMEWORK} ${IOKIT_FRAMEWORK} ${CORE_VIDEO_FRAMEWORK} ${OPENGL_FRAMEWORK} ${CORE_FRAMEWORK} ${GLFW})
target_include_directories(dbgui PRIVATE /usr/local/include)
target_include_directories(dbgui PRIVATE dep/imgui/examples)
target_include_directories(dbgui PRIVATE dep/imgui/examples/libs/gl3w)
target_include_directories(dbgui PRIVATE dep/AmigaHunkParser)
target_include_directories(dbgui PRIVATE dep/ImGuiColorTextEdit)

set_property(TARGET dbgui PROPERTY CXX_STANDARD 11)
