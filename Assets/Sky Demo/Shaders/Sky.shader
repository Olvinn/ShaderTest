Shader "Custom/Sky"
{
    Properties
    {
        _observerAltitude ("Altitude (km)", Float) = 0
    }

    SubShader
    {
        Tags
        {
            "Queue"="Background"
            "RenderType"="Background"
            "PreviewType"="Skybox"
        }

        Cull Off
        ZWrite Off
        ZTest Less

        Pass
        {
            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            
            #define RAYLEIGH_SCALE_HEIGHT 8 
            #define PRIMARY_STEPS 24
            #define VIEW_DISTANCE 200
            #define ATMOSPHERE_HEIGHT 100
            #define REYLEIGH_BETA float3(0.0058, 0.0135, 0.0331)
            #define MIE_SCALE_HEIGHT 1.2
            #define MIE_G .5

            struct Attributes
            {
                float4 positionOS : POSITION;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float3 positionWS : TEXCOORD1;
            };

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                float _observerAltitude;
            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                return OUT;
            }
            
            float rayleighDensity(float h) 
            {
                return exp(-max(h, 0.0) / RAYLEIGH_SCALE_HEIGHT);
            }
            
            float rayleighPhase(float mu) 
            {
                return 3.0 / (16.0 * PI) * (1.0 + mu * mu);
            }
            float miePhase(float mu) 
            {
                float gg = MIE_G * MIE_G;
                float num = 3.0 * (1.0 - gg) * (1.0 + mu * mu);
                float den = 8.0 * PI * (2.0 + gg) * pow(max(1.0 + gg - 2.0 * MIE_G * mu, 1e-4), 1.5);
                return num / den;
            }

            float mieDensity(float h) 
            {
                return exp(-max(h, 0.0) / MIE_SCALE_HEIGHT);
            }

            float4 frag(Varyings IN) : SV_Target
            {
                Light ld = GetMainLight();
                float3 viewDir = normalize(IN.positionWS - _WorldSpaceCameraPos);
                float3 skyDir = normalize(float3(viewDir.x, max(viewDir.y, 0), viewDir.z));
                float stepSize = VIEW_DISTANCE / float(PRIMARY_STEPS);
                float phase = rayleighPhase(dot(skyDir, ld.direction));
                float m_phase = miePhase(dot(skyDir, ld.direction));
                
                float viewOpticalDepth = 0;
                float3 scattering = 0;
                
                float viewODR = 0.0;
                float viewODM = 0.0;
                float viewODO = 0.0;

                float3 sumR = 0;
                float3 sumM = 0;
                float3 sumO = 0;

                for (int i = 0; i < PRIMARY_STEPS; i++) 
                {
                    float t = (float(i) + 0.5) * stepSize;
                    float h = _observerAltitude + t * skyDir.y;
                  
                    if (h < 0.0) break;
                    if (h > ATMOSPHERE_HEIGHT) break;

                    float dR = rayleighDensity(h);
                    float dM = mieDensity(h);
                    //float dO = ozoneDensity(h);
                  
                    viewODR += dR * stepSize;
                    viewODM += dM * stepSize;
                    //viewODO += dO * stepSize;

                    float3 tau = viewODR * REYLEIGH_BETA
                        + viewODM * REYLEIGH_BETA
                        ;//+ BETA_OZONE_ABS * viewODO;
                    float3 transmittance = exp(-tau);

                    sumR += dR * transmittance * stepSize;
                    sumM += dM * transmittance * stepSize;
                    //sumO += dO * transmittance * stepSize;
                }
                
                scattering = ld.color * (
                  phase * sumR * REYLEIGH_BETA +
                  m_phase * sumM * REYLEIGH_BETA +
                  sumO * REYLEIGH_BETA
                );
                float horizon = smoothstep(-0.12, 0.05, skyDir.y);
                float3 color = lerp(0, scattering, horizon);
                //color = ACESFilm(color);
                
                return float4(color, 1);
            }
            ENDHLSL
        }
    }
}
