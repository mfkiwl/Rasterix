// Rasterix
// https://github.com/ToNi3141/Rasterix
// Copyright (c) 2023 ToNi3141

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

#define CATCH_CONFIG_MAIN  // This tells Catch to provide a main() - only do this in one cpp file
#include "3rdParty/catch.hpp"
#include <math.h>
#include <array>
#include <algorithm>

// Include common routines
#include <verilated.h>

// Include model header, generated from Verilating "top.v"
#include "VFunctionInterpolator.h"

void clk(VFunctionInterpolator* t)
{
    t->aclk = 0;
    t->eval();
    t->aclk = 1;
    t->eval();
}

void reset(VFunctionInterpolator* t)
{
    t->resetn = 0;
    clk(t);
    t->resetn = 1;
    clk(t);
}

float clamp(float v, float lo, float hi)
{
    if (v < lo)
        v = lo;
    if (v > hi)
        v = hi;
    return v;
}

float calculateLinearValue(const float start, const float end, const float z)
{
    float f = (end - z) / (end - start);
    return f; 
}

void generateLinearTable(VFunctionInterpolator* t, const float start, const float end)
{
    static constexpr std::size_t LUT_SIZE = 32;
    uint64_t table[LUT_SIZE];
    // The verilog code is not able to handle float values smaller than 1.0f.
    // So, if start is smaller than 1.0f, set the lower bound to 1.0f which will
    // the set x to 1. 
    const float startInc = start < 1.0f ? 1.0f : start;
    const float lutLowerBound = startInc;
    const float lutUpperBound = end;
    
    union Value {
        uint64_t axiVal;
        struct {
            int32_t a;
            int32_t b;
        } numbers;
        struct {
            float a;
            float b;
        } floats;
    };

    Value bounds;
    bounds.floats.a = lutLowerBound;
    bounds.floats.b = lutUpperBound;
    t->s_axis_tvalid = 1;
    t->s_axis_tlast = 0;
    t->s_axis_tdata = bounds.axiVal;
    clk(t);
    // printf("lowerBound %d, upperBound %d, bounds: 0x%llX\r\n", lutLowerBound, lutUpperBound, bounds.axiVal);
    for (int i = 0; i < (int)LUT_SIZE; i++)
    {
        float z = powf(2, i);

        float f = calculateLinearValue(start, end, powf(2, i));
        float fn = calculateLinearValue(start, end, powf(2, i + 1));

        float diff = fn - f; 
        float step = diff / 256.0f;

        Value lutEntry;
        lutEntry.numbers.a = static_cast<int32_t>(step * powf(2, 30));
        lutEntry.numbers.b = static_cast<int32_t>(f * powf(2, 30));

        // printf("%d z: %f f: %f fn: %f step: %f axi: 0x%llX\r\n", i, z, f, fn, step, lutEntry.axiVal);

        t->s_axis_tlast = (i + 1 < (int)LUT_SIZE) ? 0 : 1;
        t->s_axis_tdata = lutEntry.axiVal;
        clk(t);
    }
    t->s_axis_tlast = 0;
    t->s_axis_tvalid = 0;
}

TEST_CASE("Check interpolation of the values", "[FunctionInterpolator]")
{
    const float start = 0;
    const float end = 100000;
    VFunctionInterpolator* top = new VFunctionInterpolator();
    reset(top);
    generateLinearTable(top, start, end);

    uint32_t pipelineSteps = 0;
    static constexpr float STEPS = 0.1;
    static constexpr float PIPELINE_STEPS = 4;
    for (float i = start; i < (end + 200); i += STEPS)
    {
        top->x = *((uint32_t*)&i);
        clk(top);

        pipelineSteps++;
        if (pipelineSteps >= PIPELINE_STEPS)
        {
            const float ref = clamp(calculateLinearValue(start, end, i - (PIPELINE_STEPS * STEPS)), 0.0f, 1.0f);
            const float actual = (float)(top->fx) / powf(2, 22);
            //printf("i: %f, ref %f, actual: %f\r\n", i, ref, actual);
            REQUIRE(ref == Approx(actual).margin(0.005));
            
            REQUIRE(actual <= 1.0f);
            REQUIRE(actual >= 0.0f);
        }
    }

    // Destroy model
    delete top;
}

