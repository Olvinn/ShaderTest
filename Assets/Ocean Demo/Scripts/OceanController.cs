using UnityEngine;
using Random = UnityEngine.Random;

public class OceanWaveController : MonoBehaviour
{
    public Material oceanMaterial;

    public Vector4[] waveDirections = new Vector4[64];

    private void Start()
    {
        for (int i = 0; i < waveDirections.Length; i++)
        {
            float angle = Random.Range(0f, Mathf.PI);
            float x = Mathf.Cos(angle);
            float y = Mathf.Sin(angle);
            waveDirections[i] = new Vector4(x, y, 0f, 0f);
        }
    }

    void Update()
    {
        oceanMaterial.SetVectorArray("_WaveDirs", waveDirections);
    }
}