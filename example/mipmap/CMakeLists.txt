add_executable(mipmap main.cpp)

target_link_libraries(mipmap PRIVATE runner)

if (RIX_BUILD_RPPICO)
    # create map/bin/hex/uf2 file in addition to ELF.
    pico_add_extra_outputs(mipmap)
endif()

