using UnityEngine;
using Random = UnityEngine.Random;

public class OceanWaveController : MonoBehaviour
{
    public Material oceanMaterial;
    [Range(0, 1)]
    public float stormy = 360;

    public Vector4[] waveDirections = new Vector4[64];
    
    public float windDirection = 60;

    private void Start()
    {
        Initialize();
    }

    private void OnValidate()
    {
        Reinitialize();
    }

    private void Initialize()
    {
        float angle = Mathf.Lerp(360, 45, stormy) * Mathf.Deg2Rad;
        float initDir = windDirection * Mathf.Deg2Rad; 
        Vector4[] result = new Vector4[waveDirections.Length];
        for (int i = 0; i < waveDirections.Length; i++)
        {
            float a = Random.Range(0f, Mathf.PI * angle) + initDir;
            float x = Mathf.Cos(a);
            float y = Mathf.Sin(a);
            result[i] = new Vector4(x, y, 0f, 0f);
            waveDirections[i] = new Vector4(x, y, 0f, 0f);
        }
        oceanMaterial.SetVectorArray("_WaveDirs", result);
        oceanMaterial.SetFloat("_WaveLength", Mathf.Lerp(5, 30, stormy));
        oceanMaterial.SetFloat("_WaveStrength", Mathf.Lerp(.01f, 1.5f, stormy));
    }

    private void Reinitialize()
    {
        float angle = Mathf.Lerp(360, 45, stormy) * Mathf.Deg2Rad;
        float initDir = windDirection * Mathf.Deg2Rad; 
        Vector4[] result = new Vector4[waveDirections.Length];
        for (int i = 0; i < waveDirections.Length; i++)
        {
            float a = Mathf.Acos(waveDirections[i].x) * angle + initDir;
            float x = Mathf.Cos(a);
            float y = Mathf.Sin(a);
            result[i] = new Vector4(x, y, 0f, 0f);
        }
        oceanMaterial.SetVectorArray("_WaveDirs", result);
        oceanMaterial.SetFloat("_WaveLength", Mathf.Lerp(5, 30, stormy));
        oceanMaterial.SetFloat("_WaveStrength", Mathf.Lerp(.01f, 1.5f, stormy));
    }
}