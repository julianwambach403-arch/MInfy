// Sternenelf Toon – Anime-Shader für BONELAB (Universal Render Pipeline)
//
// * harte Licht/Schatten-Kante mit farbigem Schatten statt Plastik-Glanz
// * funktioniert auch ohne Echtzeit-Licht (BONELAB-Level sind meist gebacken):
//   Richtung kommt aus "_ToonLightDir", Helligkeit/Farbe aus den Light Probes
// * Randlicht, Haar-Glanzring (Kajiya-Kay, entlang der Strähne) und
//   funkelnde Sterne über die Emission
// * VR: Single-Pass-Instanced-Stereo (PC und Quest)
//
// Die schwarze Kontur ist im Modell selbst (Material "Outline"), nicht im Shader.
Shader "SternenElf/Toon"
{
    Properties
    {
        [MainTexture] _BaseMap ("Textur", 2D) = "white" {}
        [MainColor] _BaseColor ("Farbe", Color) = (1, 1, 1, 1)

        [Header(Toon Schatten)]
        _ShadeColor ("Schattenfarbe (wird multipliziert)", Color) = (0.55, 0.55, 0.85, 1)
        _ShadeThreshold ("Schattengrenze", Range(0, 1)) = 0.45
        _ShadeSoftness ("Weichheit der Kante", Range(0.001, 0.5)) = 0.04
        _ToonLightDir ("Lichtrichtung (Welt, wenn kein Echtzeitlicht)", Vector) = (0.35, 0.75, 0.55, 0)
        [ToggleUI] _UseMainLight ("Echtes Hauptlicht nutzen, falls vorhanden", Float) = 1
        _AmbientInfluence ("Einfluss Umgebungslicht (Light Probes)", Range(0, 1)) = 0.6
        _MinBrightness ("Mindesthelligkeit", Range(0, 1)) = 0.45

        [Header(Randlicht)]
        _RimColor ("Randlicht-Farbe", Color) = (0.55, 1, 0.95, 1)
        _RimPower ("Randlicht-Schärfe", Range(0.5, 10)) = 3.5
        _RimStrength ("Randlicht-Stärke", Range(0, 2)) = 0.3

        [Header(Haarglanz)]
        [Toggle(_HAIR_SPEC)] _HairSpec ("Glanzring für Haare", Float) = 0
        _HairSpecColor ("Glanzfarbe", Color) = (0.8, 1, 0.95, 1)
        _HairSpecShift ("Verschiebung", Range(-1, 1)) = 0.15
        _HairSpecExponent ("Schärfe", Range(1, 512)) = 120
        _HairSpecStrength ("Stärke", Range(0, 2)) = 0.45

        [Header(Leuchten)]
        [Toggle(_EMISSION)] _UseEmission ("Leuchten", Float) = 0
        _EmissionMap ("Leucht-Textur", 2D) = "black" {}
        [HDR] _EmissionColor ("Leuchtfarbe", Color) = (1, 1, 1, 1)
        _Twinkle ("Funkeln", Range(0, 1)) = 0
        _TwinkleSpeed ("Funkel-Tempo", Range(0, 10)) = 2

        [Enum(UnityEngine.Rendering.CullMode)] _Cull ("Cull", Float) = 2
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" "Queue" = "Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4 _BaseColor;
            half4 _ShadeColor;
            half _ShadeThreshold;
            half _ShadeSoftness;
            float4 _ToonLightDir;
            half _UseMainLight;
            half _AmbientInfluence;
            half _MinBrightness;
            half4 _RimColor;
            half _RimPower;
            half _RimStrength;
            half4 _HairSpecColor;
            half _HairSpecShift;
            half _HairSpecExponent;
            half _HairSpecStrength;
            float4 _EmissionMap_ST;
            half4 _EmissionColor;
            half _Twinkle;
            half _TwinkleSpeed;
            half _Cull;
        CBUFFER_END

        TEXTURE2D(_BaseMap);     SAMPLER(sampler_BaseMap);
        TEXTURE2D(_EmissionMap); SAMPLER(sampler_EmissionMap);
        ENDHLSL

        Pass
        {
            Name "ToonForward"
            Tags { "LightMode" = "UniversalForward" }
            Cull [_Cull]
            ZWrite On

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #pragma multi_compile_fog
            #pragma shader_feature_local _HAIR_SPEC
            #pragma shader_feature_local _EMISSION
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS   : TEXCOORD2;
                float4 tangentWS  : TEXCOORD3;
                half   fogFactor  : TEXCOORD4;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes input)
            {
                Varyings o = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                VertexPositionInputs pos = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs nrm = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                o.positionCS = pos.positionCS;
                o.positionWS = pos.positionWS;
                o.normalWS = nrm.normalWS;
                o.tangentWS = float4(nrm.tangentWS, input.tangentOS.w * GetOddNegativeScale());
                o.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                o.fogFactor = ComputeFogFactor(pos.positionCS.z);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

                half4 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv) * _BaseColor;
                float3 N = normalize(i.normalWS);
                float3 V = GetWorldSpaceNormalizeViewDir(i.positionWS);

                // Lichtrichtung: echtes Hauptlicht, sonst die feste Toon-Richtung
                Light mainLight = GetMainLight();
                half mainStrength = dot(mainLight.color, half3(0.299, 0.587, 0.114));
                half useMain = _UseMainLight * step(0.05, mainStrength);
                float3 L = normalize(lerp(normalize(_ToonLightDir.xyz), mainLight.direction, useMain));

                // Toon-Rampe: harte Kante, farbiger Schatten
                half halfLambert = dot(N, L) * 0.5 + 0.5;
                half ramp = smoothstep(_ShadeThreshold - _ShadeSoftness,
                                       _ShadeThreshold + _ShadeSoftness, halfLambert);
                half3 color = albedo.rgb * lerp(_ShadeColor.rgb, half3(1, 1, 1), ramp);

                // Umgebungslicht aus den Light Probes (färbt den Avatar passend zum Level)
                half3 ambient = SampleSH(N);
                half3 lighting = lerp(half3(1, 1, 1), ambient * 1.6, _AmbientInfluence);
                lighting = max(lighting, _MinBrightness.xxx);
                color *= lighting;

                // Randlicht
                half rim = pow(1.0h - saturate(dot(N, V)), _RimPower) * _RimStrength;
                color += rim * _RimColor.rgb * lerp(0.5h, 1.0h, ramp);

            #if defined(_HAIR_SPEC)
                // Kajiya-Kay entlang der Strähne (UV-v-Richtung = Bitangente)
                float3 T = normalize(i.tangentWS.xyz);
                float3 B = normalize(cross(N, T) * i.tangentWS.w);
                float3 Ts = normalize(B + N * _HairSpecShift);
                float3 H = normalize(L + V);
                half TdotH = dot(Ts, H);
                half sinTH = sqrt(saturate(1.0h - TdotH * TdotH));
                half spec = pow(sinTH, _HairSpecExponent);
                spec = smoothstep(0.35h, 0.55h, spec);              // Anime: harte Kante
                color += spec * _HairSpecColor.rgb * _HairSpecStrength * lerp(0.3h, 1.0h, ramp);
            #endif

            #if defined(_EMISSION)
                half3 emission = SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap, i.uv).rgb
                                 * _EmissionColor.rgb;
                float phase = dot(i.positionWS, float3(91.7, 57.3, 43.1));
                half twinkle = lerp(1.0h, 0.35h + 0.65h * (0.5h + 0.5h * sin(_Time.y * _TwinkleSpeed + phase)),
                                    _Twinkle);
                color += emission * twinkle;
            #endif

                color = MixFog(color, i.fogFactor);
                return half4(color, 1);
            }
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }
            ZWrite On
            ColorMask 0
            Cull [_Cull]

            HLSLPROGRAM
            #pragma vertex depthVert
            #pragma fragment depthFrag
            #pragma multi_compile_instancing

            struct DepthAttributes
            {
                float4 positionOS : POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct DepthVaryings
            {
                float4 positionCS : SV_POSITION;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            DepthVaryings depthVert(DepthAttributes input)
            {
                DepthVaryings o = (DepthVaryings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                o.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                return o;
            }

            half4 depthFrag(DepthVaryings i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                return 0;
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
            ZWrite On
            ColorMask 0
            Cull [_Cull]

            HLSLPROGRAM
            #pragma vertex shadowVert
            #pragma fragment shadowFrag
            #pragma multi_compile_instancing

            struct ShadowAttributes
            {
                float4 positionOS : POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct ShadowVaryings
            {
                float4 positionCS : SV_POSITION;
            };

            ShadowVaryings shadowVert(ShadowAttributes input)
            {
                ShadowVaryings o = (ShadowVaryings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                o.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                return o;
            }

            half4 shadowFrag(ShadowVaryings i) : SV_Target
            {
                return 0;
            }
            ENDHLSL
        }
    }

    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
