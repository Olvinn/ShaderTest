#define NAX_GERSTNER_WAVES 64
#pragma exclude_renderers d3d11 gles

struct WaveData
{
    float length;
    float amplitude;
};

struct WaveDetails
{
    float3 normal;
    float3 laplacian;
};

WaveData WaveDistribution(int i, float waveLengthKoeff, float waveLengthDistribution, float waveAmplitudeKoeff, float waveAmplitudeDistribution)
{
    WaveData r;
    r.length = waveLengthKoeff / pow(waveLengthDistribution, i);
    r.amplitude = waveAmplitudeKoeff / pow(waveAmplitudeDistribution, i);
    return r;
}

float3 GerstnerDisplace(float3 posOS,float baseSpeed, int maxWaves, float2 waveDirections[64],
    float waveLengthKoeff, float waveLengthDistribution, float waveAmplitudeKoeff, float waveAmplitudeDistribution,
    float waveSteepness, float steepnessSuppression)
{
    float3 totalOffset = float3(0, 0, 0);

    int max_waves = min(NAX_GERSTNER_WAVES, maxWaves);
                
    for (int i = 0; i < max_waves; i++)
    {
        float2 dir = waveDirections[i];
        WaveData wd = WaveDistribution(i, waveLengthKoeff, waveLengthDistribution, waveAmplitudeKoeff, waveAmplitudeDistribution);
        float wavelength = wd.length;
        float amplitude = wd.amplitude;
        float k = UNITY_PI / wavelength;
        float speed = sqrt(baseSpeed * k);
        float phase = k * dot(dir, posOS.xz) - speed * _Time.y;

        float sinP = sin(phase);
        float cosP = cos(phase);

        float Qi = waveSteepness * pow(steepnessSuppression, i) / (k * amplitude * NAX_GERSTNER_WAVES);

        totalOffset.x += Qi * dir.x * amplitude * cosP;
        totalOffset.z += Qi * dir.y * amplitude * cosP;
        totalOffset.y += amplitude * sinP;
    }
                
    return totalOffset;
}

WaveDetails GerstnerNormalsAndCurvature(float3 posOS,float baseSpeed, int maxWaves, float2 waveDirections[64],
    float waveLengthKoeff, float waveLengthDistribution, float waveAmplitudeKoeff, float waveAmplitudeDistribution,
    float waveSteepness, float steepnessSuppression)
{
    WaveDetails r;

    int max_waves = min(NAX_GERSTNER_WAVES, maxWaves);

    float3 tangentX = float3(1, 0, 0), tangentZ = float3(0, 0, 1);
    float laplacian = 0;
                
    for (int i = 0; i < max_waves; i++)
    {
        float2 dir = waveDirections[i];
        WaveData wd = WaveDistribution(i, waveLengthKoeff, waveLengthDistribution, waveAmplitudeKoeff, waveAmplitudeDistribution);
        float wavelength = wd.length;
        float amplitude = wd.amplitude;
        float k = UNITY_PI / wavelength;
        float speed = sqrt(baseSpeed * k);
        float phase = k * dot(dir, posOS.xz) - speed * _Time.y;

        float sinP = sin(phase);
        float cosP = cos(phase);

        float scale = pow(k, 2);
        float suppression = pow(.9, i);
        laplacian += amplitude * sin(phase) * scale * suppression;

        float Qi = waveSteepness * pow(steepnessSuppression, i) / (k * amplitude * NAX_GERSTNER_WAVES);
                    
        float2 dPhase_dXZ = k * dir;

        float dYdX = amplitude * cosP * dPhase_dXZ.x;
        float dYdZ = amplitude * cosP * dPhase_dXZ.y;

        float dXdX = -Qi * dir.x * amplitude * sinP * dPhase_dXZ.x;
        float dZdX = -Qi * dir.y * amplitude * sinP * dPhase_dXZ.x;

        float dXdZ = -Qi * dir.x * amplitude * sinP * dPhase_dXZ.y;
        float dZdZ = -Qi * dir.y * amplitude * sinP * dPhase_dXZ.y;

        tangentX += float3(dXdX, dYdX, dZdX);
        tangentZ += float3(dXdZ, dYdZ, dZdZ);
    }
    
    float3 normalOS = normalize(cross(tangentZ, tangentX));

    r.normal = normalOS;
    r.laplacian = laplacian;
    
    return r;
}