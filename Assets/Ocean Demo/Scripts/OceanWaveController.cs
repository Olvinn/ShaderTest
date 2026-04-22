using System;
using System.Linq;
using System.Runtime.InteropServices;
using UnityEngine;

namespace Ocean_Demo.Scripts
{
    [Serializable]
    public struct WavesParams
    {
        public float longWavesA, longWavesL, longWavesS;
        public float mediumWavesA, mediumWavesL, mediumWavesS;
        public float secondaryWavesA, secondaryWavesL, secondaryWavesS;
        public float shortWavesA, shortWavesL, shortWavesS;
    }
    
    [ExecuteInEditMode]
    public class OceanWaveController : MonoBehaviour
    {
        public Material[] oceanMaterials;

        [Range(1, 360)] public float minAngle = 45;

        public WavesParams wavesParams;
        public Vector4[] waveDirections = new Vector4[64];
        public Vector4[] waveDirectionsReady = new Vector4[64];
        public float windDirection = 60;

        // === NEW: compute-based local details ===
        public ComputeShader WaterDetailsCompute;
        [Tooltip("Resolution of the local details texture.")]
        public int LocalDetailsResolution = 512;
        [Tooltip("World-space quad that the local map covers (center + size).")]
        public Vector2 LocalMapCenterWS = Vector2.zero;
        public Vector2 LocalMapSizeWS = new Vector2(64, 64); // meters

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

        private float _storm = .1f, _foam, _transparency = 100;
        private Camera _camera;

        private void Awake()
        {
            waveDirections = new Vector4[]
            {
                // ── Primary swell ────────────────────────────────────────────
                // Long wavelength, tight angular spread, most visual energy
                new Vector4( 0.00f, 1.40f, 78.0f, 1),
                new Vector4( 0.05f, 1.20f, 72.0f, 1),
                new Vector4(-0.04f, 1.10f, 68.0f, 1),
                new Vector4( 0.09f, 1.30f, 65.0f, 1),
                new Vector4(-0.07f, 0.95f, 60.0f, 1),
                new Vector4( 0.03f, 1.05f, 57.0f, 1),
                new Vector4(-0.11f, 0.85f, 52.0f, 1),
                new Vector4( 0.13f, 0.90f, 48.0f, 1),
                new Vector4(-0.06f, 0.75f, 45.0f, 1),
                new Vector4( 0.08f, 0.80f, 43.0f, 1),
                new Vector4(-0.15f, 0.70f, 40.0f, 1),
                new Vector4( 0.10f, 0.65f, 38.0f, 1),
                new Vector4(-0.09f, 0.60f, 36.0f, 1),
                new Vector4( 0.14f, 0.55f, 34.0f, 1),
                new Vector4(-0.12f, 0.50f, 32.0f, 1),
                new Vector4( 0.07f, 0.45f, 30.0f, 1),

                // ── Wind waves ───────────────────────────────────────────────
                // Medium wavelength, widening directional cone as size drops
                new Vector4( 0.22f, 0.42f, 28.0f, 1),
                new Vector4(-0.18f, 0.38f, 26.0f, 1),
                new Vector4( 0.30f, 0.35f, 24.0f, 1),
                new Vector4(-0.25f, 0.32f, 22.0f, 1),
                new Vector4( 0.17f, 0.30f, 20.0f, 1),
                new Vector4(-0.20f, 0.28f, 19.0f, 1),
                new Vector4( 0.35f, 0.25f, 18.0f, 1),
                new Vector4(-0.28f, 0.24f, 17.0f, 1),
                new Vector4( 0.15f, 0.22f, 16.0f, 1),
                new Vector4(-0.32f, 0.20f, 15.0f, 1),
                new Vector4( 0.40f, 0.18f, 14.0f, 1),
                new Vector4(-0.22f, 0.17f, 13.5f, 1),
                new Vector4( 0.28f, 0.15f, 13.0f, 1),
                new Vector4(-0.35f, 0.14f, 12.0f, 1),
                new Vector4( 0.19f, 0.13f, 11.0f, 1),
                new Vector4(-0.42f, 0.12f, 10.5f, 1),
                new Vector4( 0.45f, 0.11f, 10.0f, 1),
                new Vector4(-0.38f, 0.10f,  9.5f, 1),
                new Vector4( 0.33f, 0.09f,  9.0f, 1),
                new Vector4(-0.47f, 0.09f,  8.5f, 1),
                new Vector4( 0.50f, 0.08f,  8.0f, 1),
                new Vector4(-0.43f, 0.08f,  7.5f, 1),
                new Vector4( 0.38f, 0.07f,  7.0f, 1),
                new Vector4(-0.50f, 0.07f,  6.5f, 1),

                // ── Cross swell ──────────────────────────────────────────────
                // Secondary swell system ~90° off-wind, longer & calmer
                new Vector4( 0.90f, 0.55f, 55.0f, 1),
                new Vector4( 0.95f, 0.45f, 50.0f, 1),
                new Vector4( 0.85f, 0.40f, 45.0f, 1),
                new Vector4( 1.00f, 0.35f, 40.0f, 1),
                new Vector4( 0.80f, 0.30f, 35.0f, 1),
                new Vector4( 1.05f, 0.25f, 32.0f, 1),
                new Vector4( 0.92f, 0.22f, 30.0f, 1),
                new Vector4( 1.10f, 0.20f, 28.0f, 1),

                // ── Chop ─────────────────────────────────────────────────────
                // Short wavelength, fully spread, tiny amplitude — surface texture
                new Vector4( 0.55f, 0.06f,  6.0f, 1),
                new Vector4(-0.60f, 0.05f,  5.5f, 1),
                new Vector4( 0.70f, 0.05f,  5.0f, 1),
                new Vector4(-0.65f, 0.04f,  4.5f, 1),
                new Vector4( 0.80f, 0.04f,  4.0f, 1),
                new Vector4(-0.75f, 0.04f,  3.8f, 1),
                new Vector4( 0.90f, 0.03f,  3.5f, 1),
                new Vector4(-0.85f, 0.03f,  3.2f, 1),
                new Vector4( 0.60f, 0.03f,  3.0f, 1),
                new Vector4(-0.70f, 0.03f,  2.8f, 1),
                new Vector4( 0.95f, 0.02f,  2.5f, 1),
                new Vector4(-0.80f, 0.02f,  2.3f, 1),
                new Vector4( 0.50f, 0.02f,  2.1f, 1),
                new Vector4(-0.55f, 0.02f,  2.0f, 1),
                new Vector4( 0.75f, 0.02f,  1.8f, 1),
                new Vector4(-0.90f, 0.02f,  1.6f, 1),
            };
            
            InitLocalDetailsTargets();
            InitCompute();
        }

        private void Start()
        {
            _camera = Camera.main;
            if (Settings.Instance != null)
                Settings.Instance.onSettingsChanged += OnSettingsChanged;

            var mat = oceanMaterials[0];

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

        public void ChangeWater(float storm, float foam, float transparency)
        {
            _storm = storm;
            _foam = foam;
            _transparency = transparency;
            UpdateWaves();
        }

        private void OnSettingsChanged(SettingsProperty data)
        {
            if (data.Name == "SSR")
            {
                if (data.BoolValue) oceanMaterials[0].EnableKeyword("SSR");
                else oceanMaterials[0].DisableKeyword("SSR");
            }
            UpdateWaves();
        }

        private void UpdateWaves()
        {
            waveDirectionsReady = new Vector4[waveDirections.Length];
            for (int i = 0; i < waveDirections.Length; i++)
                waveDirectionsReady[i] = LerpWave(i);
        }

        private Vector4 LerpWave(int i)
        {
            switch (i)
            {
                case < 16:
                    return new Vector4(waveDirections[i].x,
                        waveDirections[i].y * wavesParams.longWavesA * _storm, 
                        waveDirections[i].z * wavesParams.longWavesL,
                        waveDirections[i].w * wavesParams.longWavesS);
                case < (16 + 24):
                    return new Vector4(waveDirections[i].x,
                        waveDirections[i].y * wavesParams.mediumWavesA * _storm, 
                        waveDirections[i].z * wavesParams.mediumWavesL,
                        waveDirections[i].w * wavesParams.mediumWavesS);
                case < (16 + 24 + 8):
                    return new Vector4(waveDirections[i].x,
                        waveDirections[i].y * wavesParams.secondaryWavesA * _storm, 
                        waveDirections[i].z * wavesParams.secondaryWavesL,
                        waveDirections[i].w * wavesParams.secondaryWavesS);
                case < (64):
                    return new Vector4(waveDirections[i].x,
                        waveDirections[i].y * wavesParams.shortWavesA * _storm, 
                        waveDirections[i].z * wavesParams.shortWavesL,
                        waveDirections[i].w *  wavesParams.shortWavesS);
            }
            return new Vector4(waveDirections[i].x, waveDirections[i].y, waveDirections[i].z, waveDirections[i].w);
        }

        private void WriteToMaterials(float storm, Vector4[] waves)
        {
            foreach (var mat in oceanMaterials)
            {
                mat.SetVectorArray("_WaveDirs", waves);
                mat.SetFloat("_FoamAmount", _foam);
                mat.SetFloat("_Transparency", _transparency);
                mat.SetVector("_MapCenterWS", new Vector4(LocalMapCenterWS.x, 0, LocalMapCenterWS.y, 0));
                mat.SetVector("_MapSizeWS", new Vector4(LocalMapSizeWS.x, 0, LocalMapSizeWS.y, 0));
                mat.SetTexture("_LocalWaterDetails", LocalWaterDetails);
            }
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
