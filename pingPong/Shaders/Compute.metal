#include <metal_stdlib>

using namespace metal;

#include "Noise.h"

struct Uniforms {
    float timer;
    float noiseScale;
};

constexpr sampler linear_sampler(coord::normalized,
                                 address::repeat,
                                 min_filter::linear,
                                 mag_filter::linear);

void kernel pingPong (texture2d<float, access::sample> input [[ texture(0) ]],
                      texture2d<float, access::write> output [[ texture(1) ]],
                      constant Uniforms &uniforms [[ buffer(0) ]],
                      uint2 gid [[ thread_position_in_grid ]])
{
    float2 resolution = float2(input.get_width(), input.get_height());
    float2 texCoord = float2(gid) / resolution;
    
    // Using the RG32Float texture format
    float2 prevOffsetVal = input.sample(linear_sampler, texCoord).rg;
    
    float2 noiseCoord = uniforms.noiseScale * (texCoord + prevOffsetVal);
    
    // Add a slider to control this parameter
    float2 noiseOffset = 0.0002f * curlSnoise(noiseCoord);
    
    output.write(float4(prevOffsetVal.rg + noiseOffset, 0.0, 1.0), gid);
}


void kernel render (texture2d<float, access::sample> source_image      [[ texture(0) ]],
                    texture2d<float, access::write>  current_drawable  [[ texture(1) ]],
                    texture2d<float, access::sample> offset            [[ texture(2) ]],
                    uint2 gid [[ thread_position_in_grid ]])
{
    float2 resolution (current_drawable.get_width(), current_drawable.get_height());
    float2 st = float2(gid) / resolution;
    
    // Using the RG32Float texture format
    float2 offset_value = offset.sample(linear_sampler, st).rg;
        
    // Change texture names to source_image, drawable and offset?
    // Or offset_value, source_image and current_drawable?
    
    // Lookup the color value for this pixel by applying the offset to the texture coordinates
    float3 color = source_image.sample(linear_sampler, st + offset_value).rgb;
    current_drawable.write(float4(color, 1.0), gid);
}
