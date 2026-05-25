#define MAX_WAVES 128
#define G 9.81
#define TWO_PI 6.283185307179586

uniform float4 _WaveDirs[MAX_WAVES];

void GetWaveParams(float waveLength, out float k, out float omega)
{
    k     = TWO_PI / waveLength;
    omega = sqrt(G * k);
}

float3 GerstnerWave(float2 pos, float2 dir, float k, float amp,
                    float steepness, float speed, float time)
{
    float phase = k * dot(dir, pos) - speed * time;
    float sinP  = sin(phase);
    float cosP  = cos(phase);

    return float3(
        steepness * amp * dir.x * cosP,
        amp * sinP,
        steepness * amp * dir.y * cosP
    );
}

void GerstnerWaveNormal(float2 pos, float2 dir, float k, float amp,
                        float steepness, float speed, float time,
                        inout float3 normal, inout float2x2 J)
{    
    float phase = k * dot(dir, pos) - speed * time;
    float sinP  = sin(phase);
    float cosP  = cos(phase);

    normal.x += -dir.x * k * amp * cosP;
    normal.y -= steepness * amp * k * sinP;
    normal.z += -dir.y * k * amp * cosP;
    
    float common = -steepness * amp * k * sinP;

    J[0][0] += common * dir.x * dir.x; // dX'/dx
    J[0][1] += common * dir.x * dir.y; // dX'/dz
    J[1][0] += common * dir.y * dir.x; // dZ'/dx
    J[1][1] += common * dir.y * dir.y; // dZ'/dz
}

float3 GetGerstnerOffset(float2 worldXZ, float time, float4 _WaveDirs[MAX_WAVES],
                         int count)
{
    float3 offset = float3(0, 0, 0);

    for (int i = 0; i < count; i++)
    {
        float k, speed, steepness = _WaveDirs[i].w;
        GetWaveParams(_WaveDirs[i].z, k, speed);
        float a = _WaveDirs[i].x * TWO_PI;
        float x = cos(a);
        float y = sin(a);
        float2 dir = normalize(float2(x, y));
        offset += GerstnerWave(worldXZ, dir, k, _WaveDirs[i].y, steepness, speed, time);
    }

    return offset;
}

void G_GetNormalJacobian(float2 worldXZ, float time, int count,
                                float4 _WaveDirs[MAX_WAVES],
                                inout float3 normal, out float jacobianCoeff)
{   
    float2x2 J = float2x2(
        1.0, 0.0,
        0.0, 1.0
    );
    
    [loop]
    for (int i = 0; i < count; i++)
    {
        float k, speed, steepness = _WaveDirs[i].w;
        GetWaveParams(_WaveDirs[i].z, k, speed);
        float a = _WaveDirs[i].x * TWO_PI;
        float x = cos(a);
        float y = sin(a);
        float2 dir = normalize(float2(x, y));
        GerstnerWaveNormal(worldXZ, dir, k, _WaveDirs[i].y, steepness, speed, time,
                           normal, J);
    }
    
    normal = normalize(normal);
    float det = J[0][0] * J[1][1] - J[0][1] * J[1][0];
    jacobianCoeff = saturate(1.0 - det);
}