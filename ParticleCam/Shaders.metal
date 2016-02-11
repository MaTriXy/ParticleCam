//
//  Particles.metal
//  MetalParticles
//
//  Created by Simon Gladman on 17/01/2015.
//  Copyright (c) 2015 Simon Gladman. All rights reserved.
//
//  Thanks to: http://memkite.com/blog/2014/12/15/data-parallel-programming-with-metal-and-swift-for-iphoneipad-gpu/
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.

//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>

#include <metal_stdlib>
using namespace metal;

float rand(int x, int y, int z);

// Generate a random float in the range [0.0f, 1.0f] using x, y, and z (based on the xor128 algorithm)
float rand(int x, int y, int z)
{
    int seed = x + y * 57 + z * 241;
    seed= (seed<< 13) ^ seed;
    return (( 1.0 - ( (seed * (seed * seed * 15731 + 789221) + 1376312589) & 2147483647) / 1073741824.0f) + 1.0f) / 2.0f;
}

kernel void darkenShader(texture2d<float, access::read> inTexture [[texture(0)]],
                          texture2d<float, access::write> outTexture [[texture(1)]],
                          uint2 gid [[thread_position_in_grid]])
{
    const float4 thisColor = inTexture.read(gid);
    
    outTexture.write(thisColor * 0.9, gid);
}

kernel void particleRendererShader(texture2d<float, access::write> outTexture [[texture(0)]],
                                   
                                   texture2d<float, access::read> cameraTexture [[texture(1)]],
                                   
                                   const device float4 *inParticles [[ buffer(0) ]],
                                   device float4 *outParticles [[ buffer(1) ]],
               
                                   constant float3 &particleColor [[ buffer(3) ]],
                                   
                                   constant float &imageWidth [[ buffer(4) ]],
                                   constant float &imageHeight [[ buffer(5) ]],
                                   
                                   uint id [[thread_position_in_grid]])
{
    const float4 inParticle = inParticles[id];
 
    const uint type = id % 3;
    const float typeTweak = 2 + type;
    
    const uint2 particlePositionA(inParticle.x, inParticle.y);

    const uint2 northIndex(particlePositionA.x, particlePositionA.y - 1);
    const uint2 southIndex(particlePositionA.x, particlePositionA.y + 1);
    const uint2 westIndex(particlePositionA.x - 1, particlePositionA.y);
    const uint2 eastIndex(particlePositionA.x + 1, particlePositionA.y);
    
    const float cameraPixelValue = 1 - cameraTexture.read(particlePositionA).r;
    
    const float3 northPixel = 1 - cameraTexture.read(northIndex).rgb;
    const float3 southPixel = 1 - cameraTexture.read(southIndex).rgb;
    const float3 westPixel = 1 - cameraTexture.read(westIndex).rgb;
    const float3 eastPixel = 1 - cameraTexture.read(eastIndex).rgb;

    const float northLuma = dot(northPixel, float3(0.2126, 0.7152, 0.0722));
    const float southLuma = dot(southPixel, float3(0.2126, 0.7152, 0.0722));
    const float eastLuma = dot(eastPixel, float3(0.2126, 0.7152, 0.0722));
    const float westLuma = dot(westPixel, float3(0.2126, 0.7152, 0.0722));
    
    const float horizontalModifier = (westLuma + eastLuma);
    
    const float verticalModifier = (northLuma + southLuma) ;
    
    if (particlePositionA.x > 1 && particlePositionA.y > 1 && particlePositionA.x < imageWidth - 1 && particlePositionA.y < imageHeight - 1)
    {
        const float4 colors[] = {
            float4(1, 1, 0 , 1.0),
            float4(0, 1, 1, 1.0),
            float4(1, 0, 1, 1.0)};
        
        const float4 outColor = colors[type];
        
        outTexture.write(outColor, particlePositionA);
    }
    else
    {
        inParticle.z = rand(inParticle.w, inParticle.x, inParticle.y) * 2.0 - 1.0;
        inParticle.w = rand(inParticle.z, inParticle.y, inParticle.x) * 2.0 - 1.0;
        
        inParticle.x = rand(inParticle.x, inParticle.y, inParticle.z) * imageWidth;
        inParticle.y = rand(inParticle.y, inParticle.x, inParticle.w) * imageHeight;
    }
    
    if (abs(inParticle.z) < 0.05)
    {
        inParticle.z = rand(inParticle.w, inParticle.x, inParticle.y) * 0.5 - 0.25;
    }
    
    if (abs(inParticle.w) < 0.05)
    {
        inParticle.w = rand(inParticle.z, inParticle.y, inParticle.x) * 0.5 - 0.25;
    }

    const float speedLimit = 2.5;
    
    float newZ = inParticle.z * (1 + horizontalModifier * typeTweak);
    float newW = inParticle.w * (1 + verticalModifier * typeTweak);
    
    float speedSquared = newZ * newZ + newW * newW;
    
    if (speedSquared > speedLimit)
    {
        float scale = speedLimit / sqrt(speedSquared);
        
        newZ = newZ * scale;
        newW = newW * scale;
    }
    
    outParticles[id] = {
        inParticle.x + inParticle.z * cameraPixelValue,
        inParticle.y + inParticle.w * cameraPixelValue,
        newZ,
        newW
    };
}