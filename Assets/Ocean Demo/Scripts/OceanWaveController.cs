using UnityEngine;
using Random = UnityEngine.Random;

namespace Ocean_Demo.Scripts
{
    [ExecuteInEditMode]
    public class OceanWaveController : MonoBehaviour
    {
        public Shader tesselationShader, noTesselationShader;
        
        public Material[] oceanMaterials;
    
        [Range(0, 1)]
        public float stormy = 360;
    
        public float waveLength, waveStrength, waveLengthDistribution, waveStrengthDistribution, waveSteepness;

        public Vector4[] waveDirections = new Vector4[64];
        public Vector4[] waveDirectionsReady = new Vector4[64];
    
        public float windDirection = 60;
        
        void Awake()
        {
            Settings.Instance.onSettingsChanged += OnSettingsChanged;
        }
        
        private void OnDestroy()
        {
            if (Settings.Instance != null)
                Settings.Instance.onSettingsChanged -= OnSettingsChanged;
        }

        private void OnSettingsChanged(SettingsProperty data)
        {
            if (data.Name == "Tesselation")
            {
                if (data.BoolValue)
                {
                    foreach (var mat in oceanMaterials)
                        mat.shader = tesselationShader;
                }
                else
                {
                    foreach (var mat in oceanMaterials)
                        mat.shader = noTesselationShader;
                }
            }
            else if (data.Name == "SSR")
            {
                if (data.BoolValue)
                {
                    foreach (var mat in oceanMaterials)
                        mat.EnableKeyword("SSR");
                }
                else
                {
                    foreach (var mat in oceanMaterials)
                        mat.DisableKeyword("SSR");
                }
            }
        }

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
            waveDirectionsReady = new Vector4[waveDirections.Length];
            for (int i = 0; i < waveDirections.Length; i++)
            {
                float a = Random.Range(0f, Mathf.PI * angle) + initDir;
                float x = Mathf.Cos(a);
                float y = Mathf.Sin(a);
                waveDirectionsReady[i] = new Vector4(x, y, 0f, 0f);
                waveDirections[i] = new Vector4(x, y, 0f, 0f);
            }

            WriteToMaterials(stormy, waveDirectionsReady);
        }

        private void Reinitialize()
        {
            float angle = Mathf.Lerp(360, 45, stormy) * Mathf.Deg2Rad;
            float initDir = windDirection * Mathf.Deg2Rad; 
            waveDirectionsReady = new Vector4[waveDirections.Length];
            for (int i = 0; i < waveDirections.Length; i++)
            {
                float a = Mathf.Acos(waveDirections[i].x) * angle + initDir;
                float x = Mathf.Cos(a);
                float y = Mathf.Sin(a);
                waveDirectionsReady[i] = new Vector4(x, y, 0f, 0f);
            }
        
            WriteToMaterials(stormy, waveDirectionsReady);
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