Shader "Custom/ScreenSpaceReflection"
{
    Properties
    {
        _ReflectionIntensity ("Reflection Intensity", Range(0, 1)) = 0.5
        _MaxSteps ("Max Ray Steps", Range(10, 128)) = 64
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            struct appdata_t
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            sampler2D _MainTex;
            sampler2D _CameraDepthTexture;
            sampler2D _CameraNormalsTexture;
            float4 _MainTex_TexelSize;
            float _ReflectionIntensity;
            int _MaxSteps;

            v2f vert (appdata_t v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                float depth = tex2D(_CameraDepthTexture, i.uv).r;
                float3 normal = tex2D(_CameraNormalsTexture, i.uv).rgb * 2 - 1;
                float3 viewDir = normalize(float3(i.uv * 2 - 1, depth));
                float3 reflectDir = reflect(viewDir, normal);

                float3 rayPos = viewDir;
                float3 rayStep = reflectDir * (_MainTex_TexelSize.x * 2);

                bool founded = false;

                float3 color = tex2D(_MainTex, i.uv).rgb;
                return float4(normal, 1.0);
                for (int j = 0; j < _MaxSteps; j++)
                {
                    rayPos += rayStep;
                    float2 screenUV = rayPos.xy * 0.5 + 0.5;
                    float sampledDepth = tex2D(_CameraDepthTexture, screenUV).r;

                    if (sampledDepth < rayPos.z && !founded)
                    {
                        float3 reflectionColor = tex2D(_MainTex, screenUV).rgb;
                        color = lerp(color, reflectionColor, _ReflectionIntensity);
                        founded = true;
                    }
                }

                return float4(color, 1.0);
            }
            ENDCG
        }
    }
}
