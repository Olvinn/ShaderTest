using System;
using System.Linq;
using System.Runtime.InteropServices;
using UnityEngine;

namespace Brod.Scripts
{
    [Serializable]
    public struct WaveSource
    {
        public Vector2 posWS;      // world-space XZ (Y ignored)
        public float radius;       // meters
        public float amplitude;    // meters
        public float wavelength;   // meters
        public float speed;        // m/s (phase speed)
        public float decay;        // 0..1 (how quickly fades with distance)
    }
    
    //[ExecuteInEditMode]
    public class BrodWaterController : MonoBehaviour
    {
        public BrodSettings settings;
        
        public Material[] oceanMaterials;
        public GameObject tilePrefab;

        public Vector4[] ShapeWavesReady;
        private Vector4[] shapeWaves;
        
        private BrodConnector _brodConnector;

        private WaveSource[] Sources = Array.Empty<WaveSource>();
        private ComputeBuffer _sourcesBuffer;
        private Camera _camera;
        private Vector2 _viewerPos;

        private void Awake()
        {
            shapeWaves = WavesGenerator.
                GetShapeWaves(swellHeight: settings.SwellHeight, windSpeed: settings.WindSpeed, fetch: settings.Fetch, 
                    storm: settings.Storm);
            
            UpdateWaves();
            BuildOcean();
            
            _camera = Camera.main;
        }

        private void Start()
        {
            BindLocalDetailsToMaterials();
            
            RecreateSourcesBuffer();
            
            _brodConnector = new BrodConnector(settings.WaterComputeShader, settings.DetailsMapSizeWS, settings.Cascades);
            _brodConnector.InitializeRenderTexture(settings.DetailsMapResolution);
            
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
            
            _brodConnector?.UpdateFoamTexture(ShapeWavesReady, _sourcesBuffer, settings.FoamLifetime, Time.time, Time.fixedDeltaTime);
        }

        private void OnValidate()
        {
            return;
            
            RecreateSourcesBuffer();
            
            _brodConnector = new BrodConnector(settings.WaterComputeShader, settings.DetailsMapSizeWS, settings.Cascades);
            _brodConnector.InitializeRenderTexture(settings.DetailsMapResolution);
            
            shapeWaves = WavesGenerator.GetShapeWaves(swellHeight: settings.SwellHeight, windSpeed: settings.WindSpeed, 
                fetch: settings.Fetch, storm: settings.Storm);
            
            if (Application.isPlaying == false)
            {
                RecreateSourcesBuffer();
                BindLocalDetailsToMaterials();
            }
            
            if (_brodConnector == null) return;
            if (ShapeWavesReady == null) return;
            
            _brodConnector.UpdateSquareCenter(new Vector2(_camera.transform.position.x , _camera.transform.position.z));
            _brodConnector.UpdateFoamTexture(ShapeWavesReady, _sourcesBuffer, settings.FoamLifetime, Time.time, Time.fixedDeltaTime);
            
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

        private void BuildOcean()
        {
            for (var i = 0; i < 100; i++)
            for (var j = 0; j < 100; j++)
            {
                var tile = Instantiate(tilePrefab, transform);
                tile.transform.position = new Vector3(i * 100 - 5000, 0, j * 100 - 5000);
            }
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
            return new Vector4(shapeWaves[i].x, shapeWaves[i].y, shapeWaves[i].z, shapeWaves[i].w); 
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
                mat.SetVector("_MapSizeWS", new Vector4(settings.DetailsMapSizeWS.x, 0, settings.DetailsMapSizeWS.y, 0));
                mat.SetTexture("_LocalWaterDetails", _brodConnector.GetDetailsRT(0));
            }

            BindLocalDetailsToMaterials();
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
                m.SetTexture("_LocalWaterDetailsA", _brodConnector.GetDetailsRT(0));
                m.SetTexture("_LocalWaterDetailsB", _brodConnector.GetDetailsRT(1));
                m.SetTexture("_LocalWaterDetailsC", _brodConnector.GetDetailsRT(2));
                m.SetTexture("_LocalWaterDetailsD", _brodConnector.GetDetailsRT(3));
            }
        }
    }
}
