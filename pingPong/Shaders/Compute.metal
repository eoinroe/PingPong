#include <metal_stdlib>

using namespace metal;

#include "Noise.h"

struct Uniforms {
    float noiseScale;
    float noiseOffset;
    float2 resolution;
};

constexpr sampler linear_sampler(coord::normalized,
                                 address::repeat,
                                 filter::linear);

void kernel pingPong (texture2d<float, access::sample> input [[ texture(0) ]],
                      texture2d<float, access::write> output [[ texture(1) ]],
                      constant Uniforms &uniforms [[ buffer(0) ]],
                      uint2 gid [[ thread_position_in_grid ]])
{
    float2 texCoord = float2(gid) / uniforms.resolution;
    
    // Using the RG32Float texture format
    float2 prevOffsetVal = input.sample(linear_sampler, texCoord).rg;
    
    // These parameters are controlled by sliders
    float2 noiseCoord = uniforms.noiseScale * (texCoord + prevOffsetVal);
    float2 noiseOffset = uniforms.noiseOffset * curlSnoise(noiseCoord);
    
    output.write(float4(prevOffsetVal.rg + noiseOffset, 0.0, 1.0), gid);
}


void kernel render (texture2d<float, access::sample> source_image      [[ texture(0) ]],
                    texture2d<float, access::write>  current_drawable  [[ texture(1) ]],
                    texture2d<float, access::sample> offset_value      [[ texture(2) ]],
                    uint2 gid [[ thread_position_in_grid ]])
{
    float2 resolution (current_drawable.get_width(), current_drawable.get_height());
    float2 st = float2(gid) / resolution;
    
    // Using the RG32Float texture format
    float2 offset = offset_value.sample(linear_sampler, st).rg;
    
    // Lookup the color value for this pixel by applying the offset to the texture coordinates
    float3 color = source_image.sample(linear_sampler, st + offset).rgb;
    current_drawable.write(float4(color, 1.0), gid);
}

void kernel reset(texture2d<float, access::write> tex0 [[ texture(0) ]],
                  texture2d<float, access::write> tex1 [[ texture(1) ]],
                  uint2 gid [[ thread_position_in_grid ]])
{
    tex0.write(float4(0.0), gid);
    tex1.write(float4(0.0), gid);
}
