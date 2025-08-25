using System;
using System.Linq;
using System.Runtime.InteropServices;
using UnityEngine;
using Random = UnityEngine.Random;

namespace Ocean_Demo.Scripts
{
    [ExecuteInEditMode]
    public class OceanWaveController : MonoBehaviour
    {
        public Shader tesselationShader, noTesselationShader;
        public Material[] oceanMaterials;

        [Range(1, 360)] public float minAngle = 45;

        [HideInInspector] public float waveLength, waveStrength, waveLengthDistribution, waveStrengthDistribution, waveSteepness, steepnessSuppression;
        public Vector4[] waveDirections = new Vector4[64];
        public Vector4[] waveDirectionsReady = new Vector4[64];
        public float windDirection = 60;

        // === NEW: compute-based local details ===
        public ComputeShader WaterDetailsCompute;
        [Tooltip("Resolution of the local details texture.")]
        public int LocalDetailsResolution = 512;
        [Tooltip("World-space quad that the local map covers (center + size).")]
        public Vector2 LocalMapCenterWS = Vector2.zero;
        public Vector2 LocalMapSizeWS = new Vector2(128, 128); // meters

        public RenderTexture LocalWaterDetails;

        // Add, update & clear sources at runtime
        [StructLayout(LayoutKind.Sequential)]
        public struct WaveSource
        {
            public Vector2 posWS;      // world-space XZ (Y ignored)
            public float radius;       // meters
            public float amplitude;    // meters
            public float wavelength;   // meters
            public float speed;        // m/s (phase speed)
            public float decay;        // 0..1 (how quickly fades with distance)
            public float type;         // 0=radial, 1=directional wake
            public float angleDeg;     // for directional wake
        }

        // Runtime container
        public WaveSource[] Sources = Array.Empty<WaveSource>();
        
        private ComputeBuffer _sourcesBuffer;
        private int _kernel;
        private uint _tgx, _tgy, _tgz;

        private float _storm, _foam;
        private Camera _camera;

        private void Awake()
        {
            InitLocalDetailsTargets();
            InitCompute();
        }

        private void Start()
        {
            _camera = Camera.main;
            if (Settings.Instance != null)
                Settings.Instance.onSettingsChanged += OnSettingsChanged;

            Initialize();

            var mat = oceanMaterials[0];
            waveLength = mat.GetFloat("_WaveLength");
            waveStrength = mat.GetFloat("_WaveStrength");
            waveLengthDistribution = mat.GetFloat("_WaveLengthDistribution");
            waveStrengthDistribution = mat.GetFloat("_WaveStrengthDistribution");

            BindLocalDetailsToMaterials();
        }

        private void Update()
        {
            LocalMapCenterWS = new Vector2(_camera.transform.position.x , _camera.transform.position.z);
            ProcessingWaterCalculations();
            WriteToMaterials(_storm, waveDirectionsReady);
        }

        private void OnValidate()
        {
            if (Application.isPlaying == false)
            {
                InitLocalDetailsTargets();
                InitCompute();
                BindLocalDetailsToMaterials();
            }
            UpdateWaves();
        }

        private void OnDestroy()
        {
            if (Settings.Instance != null)
                Settings.Instance.onSettingsChanged -= OnSettingsChanged;

            ReleaseLocalDetails();
        }

        public int AddSource(WaveSource src)
        {
            var list = Sources.ToList();
            list.Add(src);
            Sources = list.ToArray();
            RecreateSourcesBuffer();
            return Sources.Length - 1;
        }

        public void UpdateSource(int index, WaveSource src)
        {
            if (index < 0 || index >= Sources.Length) return;
            Sources[index] = src;
            PushSourcesToGPU();
        }

        public void ClearSources()
        {
            Sources = Array.Empty<WaveSource>();
            RecreateSourcesBuffer();
        }

        public void ChangeWater(float storm, float foam)
        {
            _storm = storm;
            _foam = foam;
            UpdateWaves();
        }

        private void OnSettingsChanged(SettingsProperty data)
        {
            if (data.Name == "Tesselation")
            {
                if (data.BoolValue) oceanMaterials[0].shader = tesselationShader;
                else oceanMaterials[0].shader = noTesselationShader;
            }
            else if (data.Name == "SSR")
            {
                if (data.BoolValue) oceanMaterials[0].EnableKeyword("SSR");
                else oceanMaterials[0].DisableKeyword("SSR");
            }
            UpdateWaves();
        }

        private void Initialize()
        {
            float angle = minAngle;
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
            WriteToMaterials(_storm, waveDirectionsReady);
        }

        private void UpdateWaves()
        {
            float angle = minAngle;
            float initDir = windDirection * Mathf.Deg2Rad;
            waveDirectionsReady = new Vector4[waveDirections.Length];
            for (int i = 0; i < waveDirections.Length; i++)
            {
                float a = Mathf.Acos(waveDirections[i].x) * angle + initDir;
                float x = Mathf.Cos(a);
                float y = Mathf.Sin(a);
                waveDirectionsReady[i] = new Vector4(x, y, 0f, 0f);
            }
        }

        private void WriteToMaterials(float storm, Vector4[] waves)
        {
            foreach (var mat in oceanMaterials)
            {
                mat.SetVectorArray("_WaveDirs", waves);
                mat.SetFloat("_WaveLength", Mathf.Lerp(5, 30, storm));
                mat.SetFloat("_WaveStrength", Mathf.Lerp(.01f, 1.5f, storm));
                mat.SetFloat("_WaveSteepness", Mathf.Lerp(10f, 9f, storm));
                mat.SetFloat("_FoamAmount", _foam);
                mat.SetVector("_MapCenterWS", new Vector4(LocalMapCenterWS.x, 0, LocalMapCenterWS.y, 0));
                mat.SetVector("_MapSizeWS", new Vector4(LocalMapSizeWS.x, 0, LocalMapSizeWS.y, 0));
                mat.SetTexture("_LocalWaterDetails", LocalWaterDetails);
            }

            var material = oceanMaterials[0]; // LOD0
            waveLength = material.GetFloat("_WaveLength");
            waveStrength = material.GetFloat("_WaveStrength");
            waveLengthDistribution = material.GetFloat("_WaveLengthDistribution");
            waveStrengthDistribution = material.GetFloat("_WaveStrengthDistribution");
            steepnessSuppression = material.GetFloat("_SteepnessSuppression");
        }

        private void InitLocalDetailsTargets()
        {
            if (LocalWaterDetails != null &&
                (LocalWaterDetails.width != LocalDetailsResolution ||
                 LocalWaterDetails.height != LocalDetailsResolution))
            {
                LocalWaterDetails.Release();
                LocalWaterDetails = null;
            }

            if (LocalWaterDetails == null)
            {
                LocalWaterDetails = new RenderTexture(LocalDetailsResolution, LocalDetailsResolution, 0, RenderTextureFormat.ARGBHalf);
                LocalWaterDetails.enableRandomWrite = true;
                LocalWaterDetails.wrapMode = TextureWrapMode.Clamp;
                LocalWaterDetails.filterMode = FilterMode.Bilinear;
                LocalWaterDetails.name = "LocalWaterDetails";
                LocalWaterDetails.Create();
            }
        }

        private void InitCompute()
        {
            if (WaterDetailsCompute == null) return;

            _kernel = WaterDetailsCompute.FindKernel("CSMain");
            WaterDetailsCompute.GetKernelThreadGroupSizes(_kernel, out _tgx, out _tgy, out _tgz);

            RecreateSourcesBuffer();

            // Static params
            WaterDetailsCompute.SetInts("_Resolution", LocalDetailsResolution, LocalDetailsResolution);
        }

        private void RecreateSourcesBuffer()
        {
            _sourcesBuffer?.Dispose();
            int count = Mathf.Max(1, Sources.Length);
            _sourcesBuffer = new ComputeBuffer(count, Marshal.SizeOf(typeof(WaveSource)), ComputeBufferType.Structured);
            PushSourcesToGPU();
        }

        private void PushSourcesToGPU()
        {
            if (_sourcesBuffer == null) return;

            if (Sources.Length == 0)
            {
                Sources = new[] { new WaveSource { posWS = Vector2.zero, radius = 0, amplitude = 0,
                    wavelength = 3.5f, speed = 2.0f, decay = 2.0f, type = 0, angleDeg = 0 } };
            }
            
            _sourcesBuffer.SetData(Sources);
        }

        private void BindLocalDetailsToMaterials()
        {
            foreach (var m in oceanMaterials)
                m.SetTexture("_LocalWaterDetails", LocalWaterDetails);
        }

        private void ReleaseLocalDetails()
        {
            _sourcesBuffer?.Dispose();
            _sourcesBuffer = null;

            if (LocalWaterDetails != null)
            {
                LocalWaterDetails.Release();
                LocalWaterDetails = null;
            }
        }

        private void ProcessingWaterCalculations()
        {
            if (WaterDetailsCompute == null || LocalWaterDetails == null) return;

            WaterDetailsCompute.SetFloat("_Time", Time.time);
            WaterDetailsCompute.SetVector("_MapCenterWS", new Vector4(LocalMapCenterWS.x, 0, LocalMapCenterWS.y, 0));
            WaterDetailsCompute.SetVector("_MapSizeWS", new Vector4(LocalMapSizeWS.x, 0, LocalMapSizeWS.y, 0));
            WaterDetailsCompute.SetInt("_NumSources", Mathf.Max(0, Sources.Length));
            WaterDetailsCompute.SetFloat("_Damping", 0.985f);

            WaterDetailsCompute.SetBuffer(_kernel, "_Sources", _sourcesBuffer);
            WaterDetailsCompute.SetTexture(_kernel, "_LocalDetailsRW", LocalWaterDetails);

            int gx = Mathf.CeilToInt(LocalDetailsResolution / (float)_tgx);
            int gy = Mathf.CeilToInt(LocalDetailsResolution / (float)_tgy);
            WaterDetailsCompute.Dispatch(_kernel, gx, gy, 1);
        }
    }
}
