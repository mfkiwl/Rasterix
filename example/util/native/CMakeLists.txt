add_library(runner INTERFACE)

target_link_libraries(runner INTERFACE gl spdlog::spdlog ft60x span threadrunner)

target_include_directories(runner INTERFACE .)
