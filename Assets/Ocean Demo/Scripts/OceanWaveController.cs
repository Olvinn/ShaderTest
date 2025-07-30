using UnityEngine;
using Random = UnityEngine.Random;

namespace Ocean_Demo.Scripts
{
    public class OceanWaveController : MonoBehaviour
    {
        public Material[] oceanMaterials;
    
        [Range(0, 1)]
        public float stormy = 360;
    
        public float waveLength, waveStrength, waveLengthDistribution, waveStrengthDistribution, waveSteepness;

        public Vector4[] waveDirections = new Vector4[64];
    
        public float windDirection = 60;

        private void Start()
        {
            Initialize();

            var mat = oceanMaterials[0];
            waveLength = mat.GetFloat("_WaveLength");
            waveStrength = mat.GetFloat("_WaveStrength");
            waveLengthDistribution = mat.GetFloat("_WaveLengthDistribution");
            waveStrengthDistribution = mat.GetFloat("_WaveStrengthDistribution");
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

            WriteToMaterials(stormy, result);
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
        
            WriteToMaterials(stormy, result);
        }

        private void WriteToMaterials(float storm, Vector4[] waves)
        {
            foreach (var mat in oceanMaterials)
            {
                mat.SetVectorArray("_WaveDirs", waves);
                mat.SetFloat("_WaveLength", Mathf.Lerp(5, 30, storm));
                mat.SetFloat("_WaveStrength", Mathf.Lerp(.01f, 1.5f, storm));
                mat.SetFloat("_WaveSteepness", Mathf.Lerp(3f, 6f, storm));
            }
            
            var material = oceanMaterials[0];
            waveLength = material.GetFloat("_WaveLength");
            waveStrength = material.GetFloat("_WaveStrength");
            waveLengthDistribution = material.GetFloat("_WaveLengthDistribution");
            waveStrengthDistribution = material.GetFloat("_WaveStrengthDistribution");
        }
    }
}