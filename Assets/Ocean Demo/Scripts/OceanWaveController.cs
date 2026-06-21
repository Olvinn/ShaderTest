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
        public Material[] oceanMaterials;

        public Vector4[] shapeWaves;
        public Vector4[] shapeWavesReady = new Vector4[64];
        public float windDirection = 60;

        // === NEW: compute-based local details ===
        public ComputeShader WaterDetailsCompute;
        [Tooltip("Resolution of the local details texture.")]
        public int LocalDetailsResolution = 512;
        [Tooltip("World-space quad that the local map covers (center + size).")]
        public Vector2 LocalMapCenterWS = Vector2.zero;
        public Vector2 LocalMapSizeWS = new Vector2(64, 64); // meters

        private RenderTexture WaterDetailsRT; //Serialized for debug

        [StructLayout(LayoutKind.Sequential)]
        public struct WaveSource
        {
            public Vector2 posWS;      // world-space XZ (Y ignored)
            public float radius;       // meters
            public float amplitude;    // meters
            public float wavelength;   // meters
            public float speed;        // m/s (phase speed)
            public float decay;        // 0..1 (how quickly fades with distance)
        }

        // Runtime container
        public WaveSource[] Sources = Array.Empty<WaveSource>();
        public float targetStorm = .1f;
        
        private ComputeBuffer _sourcesBuffer;
        private int _wavesKernel;
        private uint _tgx, _tgy, _tgz;

        private float _storm, _foam;
        private Camera _camera;

        private void Awake()
        {
            shapeWaves = WavesGenerator.GetShapeWaves();
            
            _camera = Camera.main;
            
            InitLocalDetailsTargets();
            InitCompute();
        }

        private void Start()
        {
            BindLocalDetailsToMaterials();
            UpdateWaves();
            WriteToMaterials(shapeWavesReady);
        }

        private void FixedUpdate()
        {
            LocalMapCenterWS = new Vector2(_camera.transform.position.x , _camera.transform.position.z);
            ProcessingWaterCalculations();
            var storm = Mathf.MoveTowards(this._storm, targetStorm, Time.deltaTime / 30);
            if (!Mathf.Approximately(storm, this._storm))
            {
                this._storm = storm;
                UpdateWaves();
                WriteToMaterials(shapeWavesReady);
            }
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
            WriteToMaterials(shapeWavesReady);
        }

        private void OnDestroy()
        {
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

        private void UpdateWaves()
        {
            shapeWavesReady = new Vector4[shapeWaves.Length];
            for (int i = 0; i < shapeWaves.Length; i++)
                shapeWavesReady[i] = ScaleWave(i);
        }

        private Vector4 ScaleWave(int i)
        {
            var AdW = Vector2.Dot(new Vector2(Mathf.Cos(windDirection), Mathf.Sin(windDirection)),
                new Vector2(Mathf.Cos(shapeWaves[i].x), Mathf.Sin(shapeWaves[i].x)));
            var s = Mathf.Sign(AdW);
            AdW = Mathf.Pow(AdW, 10);
            AdW -= s > 0 ? 0 : Mathf.PI * 2;
            return new Vector4(shapeWaves[i].x, shapeWaves[i].y * _storm * s * AdW, shapeWaves[i].z, shapeWaves[i].w);
        }

        private void WriteToMaterials(Vector4[] waves)
        {
            ComputeBuffer shapeWaveBuffer =
                new ComputeBuffer(
                    shapeWavesReady.Length,
                    sizeof(float) * 4);

            shapeWaveBuffer.SetData(waves);
            
            foreach (var mat in oceanMaterials)
            {
                mat.SetBuffer("_ShapeWaves", shapeWaveBuffer);
                mat.SetVector("_MapCenterWS", new Vector4(LocalMapCenterWS.x, 0, LocalMapCenterWS.y, 0));
                mat.SetVector("_MapSizeWS", new Vector4(LocalMapSizeWS.x, 0, LocalMapSizeWS.y, 0));
                mat.SetTexture("_LocalWaterDetails", WaterDetailsRT);
            }
        }

        private void InitLocalDetailsTargets()
        {
            if (WaterDetailsRT) WaterDetailsRT.Release();
            WaterDetailsRT = null;

            WaterDetailsRT = new RenderTexture(LocalDetailsResolution, LocalDetailsResolution, 0, RenderTextureFormat.ARGBHalf);
            WaterDetailsRT.enableRandomWrite = true;
            WaterDetailsRT.wrapMode = TextureWrapMode.Clamp;
            WaterDetailsRT.filterMode = FilterMode.Bilinear;
            WaterDetailsRT.name = "LocalWaterDetails";
            WaterDetailsRT.Create();
        }

        private void InitCompute()
        {
            if (WaterDetailsCompute == null) return;

            _wavesKernel = WaterDetailsCompute.FindKernel("Waves");
            WaterDetailsCompute.GetKernelThreadGroupSizes(_wavesKernel, out _tgx, out _tgy, out _tgz);

            RecreateSourcesBuffer();

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
                    wavelength = 3.5f, speed = 2.0f, decay = 2.0f } };
            }
            
            _sourcesBuffer.SetData(Sources);
        }

        private void BindLocalDetailsToMaterials()
        {
            foreach (var m in oceanMaterials)
            {
                m.SetTexture("_LocalWaterDetails", WaterDetailsRT);
            }
        }

        private void ReleaseLocalDetails()
        {
            _sourcesBuffer?.Dispose();
            _sourcesBuffer = null;

            if (WaterDetailsRT != null)
            {
                WaterDetailsRT.Release();
                WaterDetailsRT = null;
            }
        }

        private void ProcessingWaterCalculations()
        {
            if (WaterDetailsCompute == null || WaterDetailsRT == null) return;

            WaterDetailsCompute.SetFloat("_Time", Time.time);
            WaterDetailsCompute.SetFloat("_dt", Time.fixedDeltaTime);
            WaterDetailsCompute.SetVector("_MapCenterWS", new Vector4(LocalMapCenterWS.x, 0, LocalMapCenterWS.y, 0));
            WaterDetailsCompute.SetVector("_MapSizeWS", new Vector4(LocalMapSizeWS.x, 0, LocalMapSizeWS.y, 0));
            WaterDetailsCompute.SetInt("_NumSources", Mathf.Max(0, Sources.Length));
            WaterDetailsCompute.SetFloat("_Damping", 0.985f);

            WaterDetailsCompute.SetBuffer(_wavesKernel, "_Sources", _sourcesBuffer);
            WaterDetailsCompute.SetTexture(_wavesKernel, "_LocalWavesRW", WaterDetailsRT);

            int gx = Mathf.CeilToInt(LocalDetailsResolution / (float)_tgx);
            int gy = Mathf.CeilToInt(LocalDetailsResolution / (float)_tgy);
            
            
            ComputeBuffer waveBuffer =
                new ComputeBuffer(
                    shapeWavesReady.Length,
                    sizeof(float) * 4);
            
            waveBuffer.SetData(shapeWavesReady);
            
            WaterDetailsCompute.SetBuffer(_wavesKernel, "_ShapeWaves", waveBuffer);
            WaterDetailsCompute.Dispatch(_wavesKernel, gx, gy, 1);
        }
    }
}
