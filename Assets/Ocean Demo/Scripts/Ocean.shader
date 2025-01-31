Shader "Ocean"
{
     Properties
     {
         _Color ("Color", color) = (1,1,1,0)
         _Normal ("Normal", 2D) = "Normal" {}
         _Ambient ("Ambient", Range(0, 1)) = .5
         _Fresnel ("Fresnel", Range(0, 1)) = .03
         _Specular ("Specular", Range(0.01, 64)) = 16
         _NormalPow ("Normal Power", Range(0.01, 1)) = .7
     }
     SubShader
     {
         Pass
         {
            Tags { "RenderType" = "Opaque" }
            LOD 300
            
            CGPROGRAM
            
            #pragma vertex vert
            #pragma fragment frag

            #include "Helper.cginc"

            #define NUM_WAVES 4 

            static const float amplitudes[NUM_WAVES] = { 0.1, 0.1, 0.1, 0.05 }; 
            static const float wavelengths[NUM_WAVES] = { 4.1, 2.4, 1.6, 1.2 };  
            static const float speeds[NUM_WAVES] = { 3.1, 4.6, 6.3, 7.8 };       
            static const float2 directions[NUM_WAVES] = { 
                float2(1, 0), float2(0.5, 0.5), float2(0, 1), float2(-0.5, 0.5) 
            }; 

            sampler2D _Normal;
            float4 _Color;
            float _Ambient, _Fresnel, _Specular, _NormalPow;

            struct VertexData
            {
                float4 vertex : POSITION;
                float4 normal : NORMAL;
                float4 tangent : TANGENT;
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float4 worldPos : TEXCOORD0;
                float3 normal : TEXCOORD1;
                float4 tangent : TEXCOORD2;
            };

            float getDisplacement(float3 worldPos)
            {
                float displacement = 0.0;
                for (int j = 0; j < NUM_WAVES; j++)
                {
                    float k = 2.0 * UNITY_PI / wavelengths[j];
                    float w = speeds[j] * k;
                    float phase = w * _Time.x;  

                    float wave = sin(k * dot(worldPos.xz, normalize(directions[j])) + phase);

                    displacement += amplitudes[j] * wave;
                }
                return displacement;
            }

            v2f vert(VertexData i)
            {
                v2f o;
                o.worldPos = mul(unity_ObjectToWorld, i.vertex);
                float displacement = getDisplacement(o.worldPos);
                i.vertex.y += displacement;
                o.pos = UnityObjectToClipPos(i.vertex);
                i.normal.xyz = normalize(i.normal.xyz + float3(
                    displacement - getDisplacement(o.worldPos + float3(0.1, 0, 0)),
                    0,
                    displacement - getDisplacement(o.worldPos + float3(0, 0, 0.1))
                    ));
	            o.normal = UnityObjectToWorldNormal(i.normal);
	            o.tangent = half4(UnityObjectToWorldDir(i.tangent.xyz), i.tangent.w);
                return o;
            }
            
            fixed4 frag(v2f i) : SV_Target
            {
                float3 viewDir = normalize(_WorldSpaceCameraPos - i.worldPos.xyz);
                float3 normal = GetFullNormal(_Normal, i.worldPos, i.normal, i.tangent, _NormalPow, .2);
                
                float4 col = _Color * PhongDiffuse(normal);
                float fresnel = Fresnel(viewDir, normal, _Fresnel);
                col.rgb += fresnel * CubemapAmbient(viewDir, normal, _Ambient * 8);
                col.rgb += PhongSpecular(viewDir, normal, _Specular);
                
                return saturate(col); 
            }
            ENDCG
         }
     }
     FallBack "Diffuse"
}
