//
//  RendererCBindings.m
//  shred_ios
//
//  Created by utku on 08/01/2023.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <MetalKit/MetalKit.h>

#import "shred_ios-Swift.h"

#import "RendererCBindings.h"

extern "C" {
    #include "mikktspace.h"
}

#include "ShaderTypes.h"
#include <vector>

struct ProcessablePrimitive {
    std::vector<UltimateVertexPrototype> vertices;
    std::vector<uint32_t> indices;
};

struct TangentCalculator {
    /// https://www.turais.de/using-mikktspace-in-your-project/

    SMikkTSpaceInterface iface{};
    SMikkTSpaceContext context{};
    inline static ProcessablePrimitive primitive{};

    TangentCalculator() {
        iface.m_getNumFaces = get_num_faces;
        iface.m_getNumVerticesOfFace = get_num_vertices_of_face;

        iface.m_getNormal = get_normal;
        iface.m_getPosition = get_position;
        iface.m_getTexCoord = get_tex_coords;
        iface.m_setTSpaceBasic = set_tspace_basic;

        context.m_pInterface = &iface;
    }

    void calc(GenericPrimitive *mesh){
        primitive.vertices = std::vector<UltimateVertexPrototype>();
        primitive.indices = std::vector<uint32_t>();
        for (UltimateVertex* vertex in mesh.vertices){
            primitive.vertices.push_back([vertex toPrototype]);
        }
        for (NSNumber* index in mesh.indices){
            primitive.indices.push_back(index.unsignedIntValue);
        }
        genTangSpaceDefault(&this->context);
    }

    static int get_num_faces(const SMikkTSpaceContext *context){
        int indices = primitive.indices.size() / 3ul;
        return indices;
    }
    static int get_num_vertices_of_face(const SMikkTSpaceContext *context, int iFace){
        return 3;
    }
    static void get_position(const SMikkTSpaceContext *context, float outpos[],
                             int iFace, int iVert){
        auto& index = primitive.indices[iFace * 3 + iVert];
        auto& vertex = primitive.vertices[index];
        outpos[0] = vertex.position[0];
        outpos[1] = vertex.position[1];
        outpos[2] = vertex.position[2];
    }

    static void get_normal(const SMikkTSpaceContext *context, float outnormal[],
                           int iFace, int iVert){
        auto& index = primitive.indices[iFace * 3 + iVert];
        auto& vertex = primitive.vertices[index];
        outnormal[0] = vertex.normal[0];
        outnormal[1] = vertex.normal[1];
        outnormal[2] = vertex.normal[2];
    }

    static void get_tex_coords(const SMikkTSpaceContext *context, float outuv[],
                               int iFace, int iVert){
        auto& index = primitive.indices[iFace * 3 + iVert];
        auto& vertex = primitive.vertices[index];
        outuv[0] = vertex.texcoord_0[0];
        outuv[1] = vertex.texcoord_0[1];
    }

    static void set_tspace_basic(const SMikkTSpaceContext *context,
                                 const float tangentu[],
                                 float fSign, int iFace, int iVert){
        auto& vertex = primitive.vertices[primitive.indices[iFace * 3 + iVert]];
        simd_float3 tangent = simd_make_float3(tangentu[0], tangentu[1], tangentu[2]);
        if (fSign < 0){
            tangent *= 4;
        }
        vertex.tangent = tangent;
    }

};


@implementation RendererCBindings

+ (void)calculate:(GenericPrimitive *)forPrimitive {
    TangentCalculator calculator{};
    calculator.calc(forPrimitive);
    
    uint32_t index = 0;
    for (UltimateVertex* vertex in forPrimitive.vertices){
        vertex.tangent = calculator.primitive.vertices[index].tangent;
//        [vertex fromPrototypeWithPrototype:calculator.primitive.vertices[index]];
        index++;
    }
}

@end
