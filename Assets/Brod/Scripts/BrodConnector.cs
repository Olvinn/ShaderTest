using System;
using UnityEngine;

namespace Brod
{
    public struct Cascade
    {
        public RenderTexture current => pingPong ? detailsMapTwo : detailsMapOne;
        public RenderTexture detailsMapOne, detailsMapTwo;
        public bool pingPong;
        public Vector2 mapCenterWS, mapSizeWS;
        public float lastUpdateTime;
    }
    
    public class BrodConnector : IDisposable
    {
        private int _wavesKernel, _offsetKernel;
        private uint _tgx, _tgy, _tgz;
        
        private Cascade[] _cascades;
        private int _cascadesCount;
        private ComputeShader _waterDetailsCompute;
        private ComputeBuffer _waveBuffer;

        public BrodConnector(ComputeShader waterDetailsCompute, Vector2 squareWS, int cascades, int wavesCount)
        {
            _waterDetailsCompute = waterDetailsCompute;
            _cascadesCount = cascades;
            _cascades = new Cascade[_cascadesCount];
            for (var i = 0; i < _cascadesCount; i++)
            {
                _cascades[i] = new Cascade()
                {
                    pingPong = false,
                    mapSizeWS = squareWS / ((i + 1) * (i + 1))
                };
            }

            _waveBuffer = new ComputeBuffer(
                    wavesCount,
                    sizeof(float) * 4);
            
            _wavesKernel = _waterDetailsCompute.FindKernel("Waves");
            _offsetKernel = _waterDetailsCompute.FindKernel("Offset");
            
            _waterDetailsCompute.GetKernelThreadGroupSizes(_wavesKernel, out _tgx, out _tgy, out _tgz);
        }

        public void UpdateSquareCenter(Vector2 newCenter)
        {
            for (var i = 0; i < _cascadesCount; i++)
            {
                var offset = newCenter - _cascades[i].mapCenterWS;
                if (offset.magnitude > _cascades[i].mapSizeWS.x * .1f)
                {
                    _cascades[i].mapCenterWS = newCenter;
                    ApplyOffset(offset, i);
                }
            }
        }
        
        public void UpdateFoamTexture(Vector4[] waves, ComputeBuffer secondaryWaveSourcesBuffer, float foamLifetime, float time, int cascadeInd)
        {
            if (cascadeInd < 0 || cascadeInd >= _cascadesCount) return;
            
            var cascade =  _cascades[cascadeInd];
            
            if (_waterDetailsCompute == null || cascade.detailsMapOne == null) return;
            
            int gx = Mathf.CeilToInt(cascade.detailsMapOne.width / (float)_tgx);
            int gy = Mathf.CeilToInt(cascade.detailsMapOne.height / (float)_tgy);

            _waveBuffer.SetData(waves);
                
            _waterDetailsCompute.SetVector("_MapCenterWS", cascade.mapCenterWS);
            _waterDetailsCompute.SetVector("_MapSizeWS", cascade.mapSizeWS);
            _waterDetailsCompute.SetFloat("_Time", time);
            _waterDetailsCompute.SetFloat("_dt", time - cascade.lastUpdateTime);
            _waterDetailsCompute.SetInt("_NumSources", Mathf.Max(0, waves.Length));
            _waterDetailsCompute.SetFloat("_Damping", 0.985f);
            _waterDetailsCompute.SetFloat("_FoamLifetime", foamLifetime);
            _waterDetailsCompute.SetInts("_Resolution", cascade.detailsMapOne.width, cascade.detailsMapOne.height);
            _waterDetailsCompute.SetBuffer(_wavesKernel, "_Sources", secondaryWaveSourcesBuffer);
            _waterDetailsCompute.SetTexture(_wavesKernel, "_LocalWavesRW", cascade.current);
            _waterDetailsCompute.SetBuffer(_wavesKernel, "_ShapeWaves", _waveBuffer);
            _waterDetailsCompute.Dispatch(_wavesKernel, gx, gy, 1);
            
            _cascades[cascadeInd].lastUpdateTime = time;
        }

        public void InitializeRenderTexture(int resolution)
        {
            for (var i = 0; i < _cascadesCount; i++)
            {
                if (_cascades[i].detailsMapOne != null && (_cascades[i].detailsMapOne.width == resolution || _cascades[i].detailsMapOne.height == resolution)) return;

                _cascades[i].detailsMapOne?.Release();
                _cascades[i].detailsMapTwo?.Release();

                _cascades[i].detailsMapOne = new RenderTexture(resolution, resolution, 0, RenderTextureFormat.ARGBHalf)
                {
                    enableRandomWrite = true,
                    wrapMode = TextureWrapMode.Clamp,
                    filterMode = FilterMode.Bilinear,
                    name = $"LocalWaterDetailsOne_{i}",
                    autoGenerateMips = true
                };
                _cascades[i].detailsMapOne.Create();

                _cascades[i].detailsMapTwo = new RenderTexture(resolution, resolution, 0, RenderTextureFormat.ARGBHalf)
                {
                    enableRandomWrite = true,
                    wrapMode = TextureWrapMode.Clamp,
                    filterMode = FilterMode.Bilinear,
                    name = $"LocalWaterDetailsTwo_{i}",
                    autoGenerateMips = true
                };
                _cascades[i].detailsMapTwo.Create();
            }
        }

        public Cascade GetCascade(int cascade)
        {
            cascade = Mathf.Clamp(cascade, 0, _cascadesCount);
            return _cascades[cascade];
        }

        private void ApplyOffset(Vector2 offset, int cascade)
        {
            if (_waterDetailsCompute == null || _cascades[cascade].detailsMapOne == null) return;

            _cascades[cascade].pingPong = !_cascades[cascade].pingPong;
            
            int gx = Mathf.CeilToInt(_cascades[cascade].detailsMapOne.width / (float)_tgx);
            int gy = Mathf.CeilToInt(_cascades[cascade].detailsMapOne.height / (float)_tgy);

            _waterDetailsCompute.SetVector("_MapCenterWS", _cascades[cascade].mapCenterWS);
            _waterDetailsCompute.SetVector("_DS", offset);
            _waterDetailsCompute.SetVector("_MapSizeWS", _cascades[cascade].mapSizeWS);
            _waterDetailsCompute.SetInts("_Resolution", _cascades[cascade].detailsMapOne.width, _cascades[cascade].detailsMapOne.height);
            _waterDetailsCompute.SetTexture(_offsetKernel, "_LocalWavesR",
                _cascades[cascade].pingPong ? _cascades[cascade].detailsMapOne : _cascades[cascade].detailsMapTwo);
            _waterDetailsCompute.SetTexture(_offsetKernel, "_LocalWavesW",
                _cascades[cascade].pingPong ? _cascades[cascade].detailsMapTwo : _cascades[cascade].detailsMapOne);
            _waterDetailsCompute.Dispatch(_offsetKernel, gx, gy, 1);
        }

        public void Dispose()
        {
            for (var i =  0; i < _cascadesCount; i++)
            {
                _cascades[i].detailsMapOne?.Release();
                _cascades[i].detailsMapTwo?.Release();
            }
        }
    }
}