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
list(APPEND srcsim src/sim.cpp src/simulator.c src/m68kcpu.c src/m68kdasm.c)
# generated src
list(APPEND srcsim_gen src/m68kops.c src/m68kopac.c src/m68kopdm.c src/m68kopnz.c)

# generator
list(APPEND srcgen src/m68kmake.c)

list(APPEND srcasm src/hello.s)



add_executable(generator ${srcgen})
add_executable(sim ${srcsim} ${srcsim_gen})

target_include_directories(generator PUBLIC ./include)
target_include_directories(sim PRIVATE /usr/local/include)


add_custom_command(
		TARGET ${srcsim_gen}
		COMMAND generator
		WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}/src
		DEPENDS generator)

add_custom_command(
		OUTPUT hello.bin
		WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}		
		COMMAND vasmm68k_mot -phxass -m68060 -Fbin -o ${CMAKE_CURRENT_BINARY_DIR}/hello.bin ${srcasm}
		DEPENDS ${srcasm}
		VERBATIM)

add_custom_target(dummy DEPENDS hello.bin)


set(CMAKE_LIBRARY_PATH ${CMAKE_LIBRARY_PATH} /usr/local/lib)
find_library(COCOA_FRAMEWORK Cocoa)
find_library(IOKIT_FRAMEWORK IOKit)
find_library(CORE_FRAMEWORK CoreFoundation)
find_library(CORE_VIDEO_FRAMEWORK CoreVideo)
find_library(OPENGL_FRAMEWORK OpenGL)

if (GOA_BUILD_GLFW)
	#
	# If we want to specify options to GLFW's configuration, e.g. build as shared library:
	# set(BUILD_SHARED_LIBS ON CACHE BOOL "Build GLFW as shared library")
	# Then maybe this should be moved into a CMakeLists.txt in "deps/" instead so any options
	# wont affect the rest of GOA.
	#
	add_subdirectory(deps/glfw)
	set(GLFW glfw)
else()
	find_library(GLFW NAMES libglfw3.a PATHS)
endif()

message(STATUS "Cocoa Framework path: ${COCOA_FRAMEWORK}")
message(STATUS "OpenGL Framework path: ${OPENGL_FRAMEWORK}")
message(STATUS "GLFW library path: ${GLFW}")
message(STATUS "OSX Architectures: ${CMAKE_OSX_ARCHITECTURES}")

target_link_libraries(generator ${COCOA_FRAMEWORK} ${IOKIT_FRAMEWORK} ${CORE_VIDEO_FRAMEWORK} ${OPENGL_FRAMEWORK} ${CORE_FRAMEWORK} ${GLFW})
target_link_libraries(sim ${COCOA_FRAMEWORK} ${IOKIT_FRAMEWORK} ${CORE_VIDEO_FRAMEWORK} ${OPENGL_FRAMEWORK} ${CORE_FRAMEWORK} ${GLFW})
