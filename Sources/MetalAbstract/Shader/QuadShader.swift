//
//  File.swift
//  
//
//  Created by Noah Pikielny on 6/27/23.
//

import Foundation

extension MetalAbstract {
    public static let quadVerts = """
#include <metal_stdlib>
using namespace metal;

constant float2 verts[] = {
    float2(-1, -1),
    float2(1, -1),
    float2(1, 1),
    
    float2(-1, -1),
    float2(1, 1),
    float2(-1, 1)
};

struct Vert {
    float4 position [[position]];
    float2 uv;
};

[[vertex]]
Vert copyVert(uint vid [[vertex_id]]) {
    Vert vert;
    float2 textureVert = verts[vid];

    vert.position = float4(textureVert, 0, 1);
    vert.uv = textureVert * 0.5 + 0.5;
    vert.uv = float2(vert.uv.x, 1 - vert.uv.y);
    return vert;
}

[[fragment]]
float4 uvFrag(Vert in [[stage_in]]) {
    return float4(in.uv, 0, 1);
}

"""
}
