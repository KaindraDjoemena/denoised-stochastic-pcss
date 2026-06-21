cmake_minimum_required(VERSION 3.15)
project(App)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_subdirectory(extern/Bolero)

add_executable(App src/main.cpp)

target_link_libraries(App PRIVATE Bolero)

target_include_directories(App PRIVATE src)