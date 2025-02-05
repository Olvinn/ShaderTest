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

            #pragma target 5.0
            
            #pragma vertex vert
            #pragma hull hll
            #pragma domain dom
            #pragma fragment frag

            #include "Helper.cginc"

            #define NUM_WAVES 8

            static const float amplitudes[NUM_WAVES] = { 0.2, 0.2, 0.2, 0.05, 0.05, 0.07, 0.03, 0.2 }; 
            static const float wavelengths[NUM_WAVES] = { 4.1, 2.4, 1.6, 1.2, 1.3, 1.4, 1.5, 1.6 };  
            static const float speeds[NUM_WAVES] = { 3.1, 4.6, 6.3, 7.8, 6, 5, 4, 4.5 };       
            static const float2 directions[NUM_WAVES] = { 
                float2(1, 0), float2(0.5, 0.5), float2(0, 1), float2(-0.5, 0.5),
                float2(1, 1), float2(0.5, 1), float2(1, 0), float2(0.5, -0.5) 
            }; 

            sampler2D _Normal;
            float4 _Color;
            float _Ambient, _Fresnel, _Specular, _NormalPow;

            struct VertexData
            {
                float4 vertex : POSITION;
                float4 normal : NORMAL;
                float4 tangent : TANGENT;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2t {
                float3 worldPos : INTERNALTESSPOS;
                float3 normal : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float4 worldPos : TEXCOORD0;
                float3 normal : TEXCOORD1;
                float4 tangent : TEXCOORD2;
            };

            struct Interpolators
            {
                float3 normalWS                 : TEXCOORD0;
                float3 positionWS               : TEXCOORD1;
                float4 positionCS               : SV_POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            struct TessellationFactors
            {
                float edge[3] : SV_TessFactor;
                float inside : SV_InsideTessFactor;
                float3 bezierPoints[8] : BEZIERPOS;
            };

            // Call this macro to interpolate between a triangle patch, passing the field name
            #define BARYCENTRIC_INTERPOLATE(fieldName) \
		            patch[0].fieldName * barycentricCoordinates.x + \
		            patch[1].fieldName * barycentricCoordinates.y + \
		            patch[2].fieldName * barycentricCoordinates.z

            // The patch constant function runs once per triangle, or "patch"
            // It runs in parallel to the hull function
            TessellationFactors PatchConstantFunction(
                InputPatch<v2t, 3> patch) {
                UNITY_SETUP_INSTANCE_ID(patch[0]); // Set up instancing
                // Calculate tessellation factors
                TessellationFactors f;
                f.edge[0] = 1;
                f.edge[1] = 1;
                f.edge[2] = 1;
                f.inside = 1;
                return f;
            }

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

            v2t vert(VertexData i)
            {
                v2t o;
                o.worldPos = mul(unity_ObjectToWorld, i.vertex);
                // float displacement = getDisplacement(o.worldPos);
                // i.vertex.y = displacement;
                // o.pos = UnityObjectToClipPos(i.vertex);
	            o.normal = UnityObjectToWorldNormal(i.normal);
	            // o.tangent = half4(UnityObjectToWorldDir(i.tangent.xyz), i.tangent.w);
                return o;
            }

            // The hull function runs once per vertex. You can use it to modify vertex
            // data based on values in the entire triangle
            [domain("tri")] // Signal we're inputting triangles
            [outputcontrolpoints(3)] // Triangles have three points
            [outputtopology("triangle_cw")] // Signal we're outputting triangles
            [patchconstantfunc("PatchConstantFunction")] // Register the patch constant function
            [partitioning("integer")] // Select a partitioning mode: integer, fractional_odd, fractional_even or pow2
            v2t hll(InputPatch<v2t, 3> patch, // Input triangle
                uint id : SV_OutputControlPointID) // Vertex index on the triangle
            { 
                return patch[id];
            }

            // The domain function runs once per vertex in the final, tessellated mesh
            // Use it to reposition vertices and prepare for the fragment stage
            [domain("tri")] // Signal we're inputting triangles
            Interpolators dom(
                TessellationFactors factors, // The output of the patch constant function
                OutputPatch<v2t, 3> patch, // The Input triangle
                float3 barycentricCoordinates : SV_DomainLocation) { // The barycentric coordinates of the vertex on the triangle

                Interpolators output;

                // Setup instancing and stereo support (for VR)
                UNITY_SETUP_INSTANCE_ID(patch[0]);
                UNITY_TRANSFER_INSTANCE_ID(patch[0], output);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                float3 positionWS = BARYCENTRIC_INTERPOLATE(worldPos);
                float3 normalWS = BARYCENTRIC_INTERPOLATE(normal);

                output.positionCS = UnityWorldToClipPos(positionWS);
                output.normalWS = normalWS;
                output.positionWS = positionWS;

                return output;
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
