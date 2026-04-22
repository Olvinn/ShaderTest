#define MAX_WAVES 64
#define G 9.81

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
                        inout float3 normal, inout float laplacian)
{
    float phase = k * dot(dir, pos) - speed * time;
    float sinP  = sin(phase);
    float cosP  = cos(phase);

    normal.x += -dir.x * k * amp * cosP;
    normal.y -= steepness * amp * k * sinP;
    normal.z += -dir.y * k * amp * cosP;

    laplacian += amp * k * sinP * (1.0 - steepness * amp * k * sinP);
}

float3 GetGerstnerOffset(float2 worldXZ, float time, float4 _WaveDirs[MAX_WAVES],
                         int count)
{
    float3 offset = float3(0, 0, 0);

    for (int i = 0; i < count; i++)
    {
        float k, speed, steepness = _WaveDirs[i].w;
        GetWaveParams(_WaveDirs[i].z, k, speed);
        float a = acos(_WaveDirs[i].x % 1);
        float x = cos(a);
        float y = sin(a);
        float2 dir = normalize(float2(x, y));
        offset += GerstnerWave(worldXZ, dir, k, _WaveDirs[i].y, steepness, speed, time);
    }

    return offset;
}

void GetGerstnerNormalLaplacian(float2 worldXZ, float time, int count,
                                float4 _WaveDirs[MAX_WAVES],
                                inout float3 normal, out float laplacian)
{
    laplacian = 0.0;              

    for (int i = 0; i < count; i++)
    {
        float k, speed, steepness = _WaveDirs[i].w;
        GetWaveParams(_WaveDirs[i].z, k, speed);
        float a = acos(_WaveDirs[i].x % 1);
        float x = cos(a);
        float y = sin(a);
        float2 dir = normalize(float2(x, y));
        GerstnerWaveNormal(worldXZ, dir, k, _WaveDirs[i].y, steepness, speed, time,
                           normal, laplacian);
    }
    normal = normalize(normal);
}