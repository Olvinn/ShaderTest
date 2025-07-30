Shader "Hidden/SimpleBloom"
{
    Properties
    {
        _Intensity ("Intensity", Float) = 1
        _MainTex ("Base", 2D) = "white" {}
        _BloomTex ("Bloom", 2D) = "black" {}
    }

    SubShader
    {
        Cull Off ZWrite Off ZTest Always

        Pass
        {
            CGPROGRAM
            #pragma vertex vert_img
            #pragma fragment frag
            #include "UnityCG.cginc"

            sampler2D _MainTex;
            float _Threshold;
            float _Intensity;

            fixed4 frag(v2f_img i) : SV_Target {
                float3 col = tex2D(_MainTex, i.uv).rgb;
                float luminance = dot(col, float3(0.2126, 0.7152, 0.0722));

                float bloomFactor = saturate((luminance - _Threshold) / (1 - _Threshold));
                float3 bloom = col * bloomFactor * _Intensity;

                return float4(bloom, 1);
            }
            ENDCG
        }

        Pass
        {
            CGPROGRAM
            #pragma vertex vert_img
            #pragma fragment frag
            #include "UnityCG.cginc"

            sampler2D _MainTex;

            fixed4 frag(v2f_img i) : SV_Target {
                float2 uv = i.uv;
                float2 offset = float2(1.5/_ScreenParams.x, 0);
                float3 sum = 0;
                sum += tex2D(_MainTex, uv - offset * 2).rgb * 0.05;
                sum += tex2D(_MainTex, uv - offset).rgb * 0.15;
                sum += tex2D(_MainTex, uv).rgb * 0.6;
                sum += tex2D(_MainTex, uv + offset).rgb * 0.15;
                sum += tex2D(_MainTex, uv + offset * 2).rgb * 0.05;
                return float4(sum, 1);
            }
            ENDCG
        }

        Pass
        { 
            CGPROGRAM
            #pragma vertex vert_img
            #pragma fragment frag
            #include "UnityCG.cginc"

            sampler2D _MainTex;

            fixed4 frag(v2f_img i) : SV_Target {
                float2 uv = i.uv;
                float2 offset = float2(0, 1.5/_ScreenParams.y);
                float3 sum = 0;
                sum += tex2D(_MainTex, uv - offset * 2).rgb * 0.05;
                sum += tex2D(_MainTex, uv - offset).rgb * 0.15;
                sum += tex2D(_MainTex, uv).rgb * 0.6;
                sum += tex2D(_MainTex, uv + offset).rgb * 0.15;
                sum += tex2D(_MainTex, uv + offset * 2).rgb * 0.05;
                return float4(sum, 1);
            }
            ENDCG
        }

        Pass
        { 
            CGPROGRAM
            #pragma vertex vert_img
            #pragma fragment frag
            #include "UnityCG.cginc"

            sampler2D _MainTex;
            sampler2D _BloomTex;

            fixed4 frag(v2f_img i) : SV_Target {
                float3 baseCol = tex2D(_MainTex, i.uv).rgb;
                float3 bloom = tex2D(_BloomTex, i.uv).rgb;
                return float4(baseCol + bloom, 1);
            }
            ENDCG
        }
    }
}