cmake_minimum_required(VERSION 3.5.0)
project(cardio_gemma4)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

add_library(cardio_gemma4 SHARED napi_init.cpp)
target_link_libraries(cardio_gemma4 PUBLIC libace_napi.z.so)
