using UnityEngine;
using Random = UnityEngine.Random;

public class OceanWaveController : MonoBehaviour
{
    public Material oceanMaterial;
    public float angle = 360;

    public Vector4[] waveDirections = new Vector4[128];

    private void Start()
    {
        for (int i = 0; i < waveDirections.Length; i++)
        {
            float angle = Random.Range(0f, Mathf.PI * this.angle * Mathf.Deg2Rad);
            float x = Mathf.Cos(angle);
            float y = Mathf.Sin(angle);
            waveDirections[i] = new Vector4(x, y, 0f, 0f);
        }
    }

    void Update()
    {
        oceanMaterial.SetVectorArray("_WaveDirs", waveDirections);
    }

    private void OnValidate()
    {
        for (int i = 0; i < waveDirections.Length; i++)
        {
            float angle = Random.Range(0f, Mathf.PI * this.angle * Mathf.Deg2Rad);
            float x = Mathf.Cos(angle);
            float y = Mathf.Sin(angle);
            waveDirections[i] = new Vector4(x, y, 0f, 0f);
        }
    }
}