using System;
using UnityEngine;

namespace Brod.Scripts
{
    public class BrodConnector : IDisposable
    {
        private Vector2 _mapCenterWS, _mapSizeWS;
        private int _wavesKernel, _offsetKernel;
        private uint _tgx, _tgy, _tgz;
        
        private RenderTexture _detailsMapOne, _detailsMapTwo;
        private bool _pingPong;
        private ComputeShader _waterDetailsCompute;

        public BrodConnector(ComputeShader waterDetailsCompute, Vector2 squareWS)
        {
            _waterDetailsCompute = waterDetailsCompute;
            _mapSizeWS = squareWS;
            
            _wavesKernel = _waterDetailsCompute.FindKernel("Waves");
            _offsetKernel = _waterDetailsCompute.FindKernel("Offset");
            
            _waterDetailsCompute.GetKernelThreadGroupSizes(_wavesKernel, out _tgx, out _tgy, out _tgz);
        }

        public void UpdateSquareCenter(Vector2 newCenter)
        {
            var offset = newCenter - _mapCenterWS;
            _mapCenterWS = newCenter;
            ApplyOffset(offset);
        }
        
        public void UpdateFoamTexture(Vector4[] waves, ComputeBuffer secondaryWaveSourcesBuffer, float foamLifetime, float time, float dt)
        {
            if (_waterDetailsCompute == null || _detailsMapOne == null) return;

            int gx = Mathf.CeilToInt(_detailsMapOne.width / (float)_tgx);
            int gy = Mathf.CeilToInt(_detailsMapOne.height / (float)_tgy);
            
            ComputeBuffer waveBuffer =
                new ComputeBuffer(
                    waves.Length,
                    sizeof(float) * 4);
            
            waveBuffer.SetData(waves);
            
            _waterDetailsCompute.SetFloat("_Time", time);
            _waterDetailsCompute.SetFloat("_dt", dt);
            _waterDetailsCompute.SetInt("_NumSources", Mathf.Max(0, waves.Length));
            _waterDetailsCompute.SetFloat("_Damping", 0.985f);
            _waterDetailsCompute.SetFloat("_FoamLifetime", foamLifetime);
            _waterDetailsCompute.SetBuffer(_wavesKernel, "_Sources", secondaryWaveSourcesBuffer);
            _waterDetailsCompute.SetTexture(_wavesKernel, "_LocalWavesRW", _pingPong ? _detailsMapTwo : _detailsMapOne);
            _waterDetailsCompute.SetBuffer(_wavesKernel, "_ShapeWaves", waveBuffer);
            _waterDetailsCompute.Dispatch(_wavesKernel, gx, gy, 1);
        }

        public void InitializeRenderTexture(int resolution)
        {
            if (_detailsMapOne && (_detailsMapOne.width == resolution || _detailsMapOne.height == resolution)) return;
            
            if (_detailsMapOne) _detailsMapOne.Release();
            
            _detailsMapOne = null;

            _detailsMapOne = new RenderTexture(resolution, resolution, 0, RenderTextureFormat.ARGBHalf)
                {
                    enableRandomWrite = true,
                    wrapMode = TextureWrapMode.Clamp,
                    filterMode = FilterMode.Bilinear,
                    name = "LocalWaterDetails",
                    autoGenerateMips = true
                };
            _detailsMapOne.Create();
            
            _detailsMapTwo = new RenderTexture(resolution, resolution, 0, RenderTextureFormat.ARGBHalf)
            {
                enableRandomWrite = true,
                wrapMode = TextureWrapMode.Clamp,
                filterMode = FilterMode.Bilinear,
                name = "LocalWaterDetails",
                autoGenerateMips = true
            };
            _detailsMapOne.Create();
        }

        public RenderTexture GetDetailsRT()
        {
            return _pingPong ? _detailsMapTwo : _detailsMapOne;
        }

        private void ApplyOffset(Vector2 offset)
        {
            if (_waterDetailsCompute == null || _detailsMapOne == null) return;

            _pingPong = !_pingPong;

            int gx = Mathf.CeilToInt(_detailsMapOne.width / (float)_tgx);
            int gy = Mathf.CeilToInt(_detailsMapOne.height / (float)_tgy);

            _waterDetailsCompute.SetInts("_Resolution", _detailsMapOne.width, _detailsMapOne.height);
            _waterDetailsCompute.SetVector("_MapCenterWS", _mapCenterWS);
            _waterDetailsCompute.SetVector("_MapSizeWS", _mapSizeWS);
            _waterDetailsCompute.SetVector("_DS", offset);
            _waterDetailsCompute.SetTexture(_offsetKernel, "_LocalWavesR", _pingPong ? _detailsMapOne : _detailsMapTwo);
            _waterDetailsCompute.SetTexture(_offsetKernel, "_LocalWavesW", _pingPong ? _detailsMapTwo : _detailsMapOne);
            _waterDetailsCompute.Dispatch(_offsetKernel, gx, gy, 1);
        }

        public void Dispose()
        {
            _detailsMapOne?.Release();
        }
    }
}