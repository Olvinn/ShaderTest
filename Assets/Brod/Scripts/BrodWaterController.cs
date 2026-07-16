using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using UnityEngine;

namespace Brod
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
    
    public class BrodWaterController : MonoBehaviour
    {
        public BrodSettings settings;
        
        public Material[] oceanMaterials;
        public MeshGenerator tilePrefab;

        public Vector4[] ShapeWavesReady;
        private Vector4[] shapeWaves;
        private float _displacementRadius;
        
        private BrodConnector _brodConnector;

        private WaveSource[] Sources = Array.Empty<WaveSource>();
        private ComputeBuffer _sourcesBuffer;
        private Camera _camera;
        private Vector2 _viewerPos;
        
        private List<MeshGenerator> _tilesPool = new ();
        private int _updateCounter;

        private void Awake()
        {
            shapeWaves = WavesGenerator.
                GetShapeWaves(swellHeight: settings.SwellHeight, windSpeed: settings.WindSpeed, fetch: settings.Fetch, 
                    storm: settings.Storm);
            
            UpdateWaves();
            _displacementRadius = GetDisplacementRadius(ShapeWavesReady);
            BuildOcean();
            
            _camera = Camera.main;
        }

        private void Start()
        {
            BindLocalDetailsToMaterials();
            
            RecreateSourcesBuffer();
            
            _brodConnector = new BrodConnector(settings.WaterComputeShader, settings.DetailsMapSizeWS, settings.Cascades, ShapeWavesReady.Length);
            _brodConnector.InitializeRenderTexture(settings.DetailsMapResolution);
            _brodConnector.UpdateWavesBuffer(ShapeWavesReady);
            
            WriteToMaterials();
        }

        private void FixedUpdate()
        {
            if (Vector3.Distance(_viewerPos, new Vector2(_camera.transform.position.x , _camera.transform.position.z)) > 1)
            {
                _viewerPos = new Vector2(_camera.transform.position.x , _camera.transform.position.z);
                _brodConnector?.UpdateSquareCenter(_viewerPos);
                WriteToMaterials();
            }

            _updateCounter++;
            _brodConnector?.UpdateFoamTexture(ShapeWavesReady, _sourcesBuffer, settings.FoamLifetime, Time.time, 3);
            if (_updateCounter % 2 == 0)
                _brodConnector?.UpdateFoamTexture(ShapeWavesReady, _sourcesBuffer, settings.FoamLifetime, Time.time, 2);
            else if (_updateCounter % 3 == 0)
                _brodConnector?.UpdateFoamTexture(ShapeWavesReady, _sourcesBuffer, settings.FoamLifetime, Time.time, 1);
            else if (_updateCounter % 5 == 0)
                _brodConnector?.UpdateFoamTexture(ShapeWavesReady, _sourcesBuffer, settings.FoamLifetime, Time.time, 0);
        }

        private void OnDestroy()
        {
            _brodConnector?.Dispose();
            ClearSources();
            if (_tilesPool == null) return;
            for (var i = 0; i < _tilesPool.Count; i++)
                DestroyImmediate(_tilesPool[i].gameObject);
            _tilesPool.Clear();
        }
        
        private float GetDisplacementRadius(Vector4[] waves)
        {
            float maxVert  = 0f;
            float maxHoriz = 0f;

            foreach(var w in waves)
            {
                float amp       = w.y;
                float steepness = w.w;

                maxVert += amp;

                maxHoriz += steepness * amp;
            }

            return Mathf.Max(maxVert, maxHoriz);
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
            if (_tilesPool is { Count: > 0 }) return;
            
            _tilesPool = new List<MeshGenerator>();
            
            for (var i = 0; i < 100; i++)
            for (var j = 0; j < 100; j++)
            {
                var tile = Instantiate(tilePrefab, transform); 
                tile.transform.position = new Vector3(i * 200 - 10000, 0, j * 200 - 10000);
                tile.CreateMesh(detalization: 2, size: 200);
                _tilesPool.Add(tile);
                tile.UpdateAABB(_displacementRadius);
            }
        }

        private void UpdateWaves()
        {
            if (ShapeWavesReady == null || ShapeWavesReady.Length != shapeWaves.Length)
                ShapeWavesReady = new Vector4[shapeWaves.Length];
            for (var i = 0; i < shapeWaves.Length; i++)
                ShapeWavesReady[i] = ScaleWave(i);
        }

        private Vector4 ScaleWave(int i)
        {
            return new Vector4(shapeWaves[i].x, shapeWaves[i].y, shapeWaves[i].z, shapeWaves[i].w); 
        }

        private void WriteToMaterials()
        {
            foreach (var mat in oceanMaterials)
            {
                mat.SetTexture("_LocalWaterDetails", _brodConnector.GetCascade(0).current);
                mat.SetFloat("_MaxDisp", _displacementRadius);
            }

            BindLocalDetailsToMaterials();
        }

        private void RecreateSourcesBuffer()
        {
            _sourcesBuffer?.Dispose();
            var count = Mathf.Max(1, Sources.Length);
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
                m.SetTexture("_LocalWaterDetailsA", _brodConnector.GetCascade(0).current);
                m.SetVector("_MapCenterWSA", _brodConnector.GetCascade(0).mapCenterWS);
                m.SetVector("_MapSizeWSA", _brodConnector.GetCascade(0).mapSizeWS);
                
                m.SetTexture("_LocalWaterDetailsB", _brodConnector.GetCascade(1).current);
                m.SetVector("_MapCenterWSB", _brodConnector.GetCascade(1).mapCenterWS);
                m.SetVector("_MapSizeWSB", _brodConnector.GetCascade(1).mapSizeWS);
                
                m.SetTexture("_LocalWaterDetailsC", _brodConnector.GetCascade(2).current);
                m.SetVector("_MapCenterWSC", _brodConnector.GetCascade(2).mapCenterWS);
                m.SetVector("_MapSizeWSC", _brodConnector.GetCascade(2).mapSizeWS);
                
                m.SetTexture("_LocalWaterDetailsD", _brodConnector.GetCascade(3).current);
                m.SetVector("_MapCenterWSD", _brodConnector.GetCascade(3).mapCenterWS);
                m.SetVector("_MapSizeWSD", _brodConnector.GetCascade(3).mapSizeWS);
            }
        }
    }
}
