﻿Shader "Unlit/Reflection"
{

CGINCLUDE
#include "UnityCG.cginc"
#include "CGINC/VoxelLight.cginc"
#define _CameraDepthTexture _
#include "UnityDeferredLibrary.cginc"
#include "UnityStandardUtils.cginc"
#include "UnityGBuffer.cginc"
#include "UnityStandardBRDF.cginc"
#include "UnityPBSLighting.cginc"
#include "CGINC/Reflection.cginc"
#pragma multi_compile _ UNITY_HDR_ON
#pragma multi_compile _ EnableGTAO
#pragma target 5.0
#undef _CameraDepthTexture

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };
            float4x4 _InvVP;    //Inverse View Project Matrix
            float3 _Size;
            TextureCube<half4> _ReflectionProbe; SamplerState sampler_ReflectionProbe;
            Texture2D<half4> _CameraGBufferTexture0; SamplerState sampler_CameraGBufferTexture0;       //RGB Diffuse A AO
            Texture2D<half4> _CameraGBufferTexture1; SamplerState sampler_CameraGBufferTexture1;       //RGB Specular A Smoothness
            Texture2D<half3> _CameraGBufferTexture2; SamplerState sampler_CameraGBufferTexture2;       //RGB Normal
            Texture2D<float> _CameraDepthTexture; SamplerState sampler_CameraDepthTexture;
			Texture2D<float2> _AOROTexture; SamplerState sampler_AOROTexture;
            float2 _CameraClipDistance; //X: Near Y: Far - Near
            StructuredBuffer<uint> _ReflectionIndices;
            StructuredBuffer<ReflectionData> _ReflectionData;

            
ENDCG
    SubShader
    {
                    Cull off ZWrite off ZTest Always
            Blend one one
        Tags { "RenderType"="Opaque" }
        LOD 100
//Pass 0 Regular Projection
        Pass
        {

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = v.vertex;
                o.uv = v.uv;
                return o;
            }

            float3 frag (v2f i) : SV_Target
            {
                float depth = _CameraDepthTexture.Sample(sampler_CameraDepthTexture, i.uv);
                float4 worldPos = mul(_InvVP, float4(i.uv * 2 - 1, depth, 1));
                worldPos /= worldPos.w;
                float rate = saturate((LinearEyeDepth(depth) - _CameraClipDistance.x) / _CameraClipDistance.y);
                float3 uv = float3(i.uv, rate);
                uint3 intUV = uv * float3(XRES, YRES, ZRES);
                int index = DownDimension(intUV, uint2(XRES, YRES), MAXIMUM_PROBE + 1);
                int target = _ReflectionIndices[index];
                float3 normal = normalize(_CameraGBufferTexture2.Sample(sampler_CameraGBufferTexture2, i.uv).xyz * 2 - 1);
                float occlusion = _CameraGBufferTexture0.Sample(sampler_CameraGBufferTexture0, i.uv).w;
#if EnableGTAO
				float2 aoro = _AOROTexture.Sample(sampler_AOROTexture, i.uv);
				occlusion = min(occlusion, aoro.x);
#endif
                float3 eyeVec = normalize(worldPos.xyz - _WorldSpaceCameraPos);
                float3 finalColor = 0;
                float4 specular = _CameraGBufferTexture1.Sample(sampler_CameraGBufferTexture1, i.uv);
                
                Unity_GlossyEnvironmentData g = UnityGlossyEnvironmentSetup(specular.w, -eyeVec, normal, specular.xyz);
                half perceptualRoughness = g.roughness;
                perceptualRoughness = perceptualRoughness*(1.7 - 0.7*perceptualRoughness);
                float lod = perceptualRoughnessToMipmapLevel(perceptualRoughness);;
                half oneMinusReflectivity = 1 - SpecularStrength(specular.xyz);
                UnityGIInput d;
                d.worldPos = worldPos.xyz;
                d.worldViewDir = -eyeVec;
                UnityLight light;
                light.color = half3(0, 0, 0);
                light.dir = half3(0, 1, 0);
                UnityIndirect ind;
                ind.diffuse = 0;
                [loop]
                for(int a = 1; a < target; ++a)
                {
                    int currentIndex = _ReflectionIndices[index + a];
                    ReflectionData data = _ReflectionData[currentIndex];
                    float3 leftDown = data.position - data.maxExtent;
                    float3 cubemapUV = (worldPos.xyz - leftDown) / (data.maxExtent * 2);
                    if(abs(dot(cubemapUV - saturate(cubemapUV), 1)) > 1e-13) continue;
                   
                    d.probeHDR[0] = data.hdr;
                    if(data.boxProjection > 0)
                    {
                        d.probePosition[0]  = float4(data.position, 1);
                        d.boxMin[0].xyz     = leftDown;
                        d.boxMax[0].xyz     = (data.position + data.maxExtent);
                    }
                    ind.specular = MPipelineGI_IndirectSpecular(d, occlusion, g, data, currentIndex, lod);
                    half3 rgb = BRDF1_Unity_PBS (0, specular.xyz, oneMinusReflectivity, specular.w, normal, -eyeVec, light, ind).rgb;
                    float3 distanceToMin = saturate((abs(worldPos.xyz - data.position) - data.minExtent) / data.blendDistance);
                    finalColor = lerp(rgb * data.hdr.r, finalColor, max(distanceToMin.x, max(distanceToMin.y, distanceToMin.z)));
                }
#if EnableGTAO
				finalColor *= aoro.y;
#endif
                return finalColor;
            }
            ENDCG
        }
    }
}
