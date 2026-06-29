using System;
using System.Linq;
using System.Runtime.InteropServices;
using UnityEngine;

namespace Brod.Scripts
{
    [ExecuteInEditMode]
    public class BrodWaterController : MonoBehaviour
    {
        public Material[] oceanMaterials;

        public ComputeShader WaterDetailsCompute;
        [Tooltip("Resolution of the local details texture.")]
        public int LocalDetailsResolution = 512;
        public Vector3 LocalMapSizeWS;

        public float targetStorm = .1f, foamLifetime = 3;
        public float windDirection = 60;
        public float swellHeight = 3, windSpeed = 13, fetch = 250000, storm = .6f;
        
        private Vector4[] shapeWaves;
        public Vector4[] ShapeWavesReady;
        
        private BrodConnector _brodConnector;

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

        private WaveSource[] Sources = Array.Empty<WaveSource>();
        
        private ComputeBuffer _sourcesBuffer;

        private float _storm, _foam;
        private Camera _camera;
        private Vector2 _viewerPos;

        private void Awake()
        {
            shapeWaves = WavesGenerator.
                GetShapeWaves(swellHeight: swellHeight, windSpeed: windSpeed, fetch: fetch, storm: storm);
            
            UpdateWaves();
            
            _camera = Camera.main;
        }

        private void Start()
        {
            BindLocalDetailsToMaterials();
            
            RecreateSourcesBuffer();
            
            _brodConnector = new BrodConnector(WaterDetailsCompute, LocalMapSizeWS);
            _brodConnector.InitializeRenderTexture(LocalDetailsResolution);
            
            WriteToMaterials(ShapeWavesReady);
        }

        private void FixedUpdate()
        {
            if (Vector3.Distance(_viewerPos, new Vector2(_camera.transform.position.x , _camera.transform.position.z)) > 10)
            {
                _viewerPos = new Vector2(_camera.transform.position.x , _camera.transform.position.z);
                _brodConnector?.UpdateSquareCenter(_viewerPos);
                WriteToMaterials(ShapeWavesReady);
            }
            
            var storm = Mathf.MoveTowards(this._storm, targetStorm, Time.deltaTime / 30);
            if (!Mathf.Approximately(storm, this._storm))
            {
                this._storm = storm;
                UpdateWaves();
                WriteToMaterials(ShapeWavesReady);
            }
            _brodConnector?.UpdateFoamTexture(ShapeWavesReady, _sourcesBuffer, foamLifetime, Time.time, Time.fixedDeltaTime);
        }

        private void OnValidate()
        {
            return;
            
            RecreateSourcesBuffer();
            
            _brodConnector = new BrodConnector(WaterDetailsCompute, LocalMapSizeWS);
            _brodConnector.InitializeRenderTexture(LocalDetailsResolution);
            
            shapeWaves = WavesGenerator.
                GetShapeWaves(swellHeight: swellHeight, windSpeed: windSpeed, fetch: fetch, storm: storm);
            
            if (Application.isPlaying == false)
            {
                RecreateSourcesBuffer();
                BindLocalDetailsToMaterials();
            }
            
            if (_brodConnector == null) return;
            if (ShapeWavesReady == null) return;
            
            _brodConnector.UpdateSquareCenter(new Vector2(_camera.transform.position.x , _camera.transform.position.z));
            _brodConnector.UpdateFoamTexture(ShapeWavesReady, _sourcesBuffer, foamLifetime, Time.time, Time.fixedDeltaTime);
            
            UpdateWaves();
            
            WriteToMaterials(ShapeWavesReady);
        }

        private void OnDestroy()
        {
            _brodConnector?.Dispose();
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
        }

        public void ClearSources()
        {
            Sources = Array.Empty<WaveSource>();
            RecreateSourcesBuffer();
        }

        private void UpdateWaves()
        {
            if (ShapeWavesReady == null || ShapeWavesReady.Length != shapeWaves.Length)
                ShapeWavesReady = new Vector4[shapeWaves.Length];
            for (int i = 0; i < shapeWaves.Length; i++)
                ShapeWavesReady[i] = ScaleWave(i);
        }

        private Vector4 ScaleWave(int i)
        {
            var AdW = Vector2.Dot(new Vector2(Mathf.Cos(windDirection), Mathf.Sin(windDirection)),
                new Vector2(Mathf.Cos(shapeWaves[i].x), Mathf.Sin(shapeWaves[i].x)));
            var s = Mathf.Sign(AdW);
            AdW = Mathf.Pow(AdW, 10);
            AdW -= s > 0 ? 0 : Mathf.PI * 2;
            return new Vector4(shapeWaves[i].x, shapeWaves[i].y/* * _storm * s * AdW*/, shapeWaves[i].z, shapeWaves[i].w); 
        }

        private void WriteToMaterials(Vector4[] waves)
        {
            ComputeBuffer shapeWaveBuffer =
                new ComputeBuffer(
                    ShapeWavesReady.Length,
                    sizeof(float) * 4);

            shapeWaveBuffer.SetData(waves);
            
            foreach (var mat in oceanMaterials)
            {
                mat.SetBuffer("_ShapeWaves", shapeWaveBuffer);
                mat.SetVector("_MapCenterWS", new Vector4(_viewerPos.x, 0, _viewerPos.y, 0));
                mat.SetVector("_MapSizeWS", new Vector4(LocalMapSizeWS.x, 0, LocalMapSizeWS.y, 0));
                mat.SetTexture("_LocalWaterDetails", _brodConnector.GetDetailsRT());
            }
        }

        private void RecreateSourcesBuffer()
        {
            _sourcesBuffer?.Dispose();
            int count = Mathf.Max(1, Sources.Length);
            _sourcesBuffer = new ComputeBuffer(count, Marshal.SizeOf(typeof(WaveSource)), ComputeBufferType.Structured);
            
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
            if (_brodConnector == null) return;
            
            foreach (var m in oceanMaterials)
            {
                m.SetTexture("_LocalWaterDetails", _brodConnector.GetDetailsRT());
            }
        }
    }
}
