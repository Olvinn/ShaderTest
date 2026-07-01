using System;
using UnityEngine;

namespace Brod.Scripts
{
    public class BrodConnector : IDisposable
    {
        private Vector2 _mapCenterWS, _mapSizeWS;
        private int _wavesKernel, _offsetKernel;
        private uint _tgx, _tgy, _tgz;
        
        private RenderTexture[] _detailsMapOne, _detailsMapTwo;
        private int _cascades;
        private bool _pingPong;
        private ComputeShader _waterDetailsCompute;

        public BrodConnector(ComputeShader waterDetailsCompute, Vector2 squareWS, int cascades)
        {
            _waterDetailsCompute = waterDetailsCompute;
            _mapSizeWS = squareWS;
            _cascades = cascades;
            
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
            
            for (var i = 0; i < _cascades; i++)
            {
                int gx = Mathf.CeilToInt(_detailsMapOne[i].width / (float)_tgx);
                int gy = Mathf.CeilToInt(_detailsMapOne[i].height / (float)_tgy);

                ComputeBuffer waveBuffer =
                    new ComputeBuffer(
                        waves.Length,
                        sizeof(float) * 4);

                waveBuffer.SetData(waves);
                
                _waterDetailsCompute.SetVector("_MapCenterWS", _mapCenterWS);
                _waterDetailsCompute.SetFloat("_Time", time);
                _waterDetailsCompute.SetFloat("_dt", dt);
                _waterDetailsCompute.SetInt("_NumSources", Mathf.Max(0, waves.Length));
                _waterDetailsCompute.SetFloat("_Damping", 0.985f);
                _waterDetailsCompute.SetFloat("_FoamLifetime", foamLifetime);
                _waterDetailsCompute.SetInts("_Resolution", _detailsMapOne[i].width, _detailsMapOne[i].height);
                _waterDetailsCompute.SetVector("_MapSizeWS", _mapSizeWS * Mathf.Pow(2, i));
                _waterDetailsCompute.SetFloat("_Time", time);
                _waterDetailsCompute.SetBuffer(_wavesKernel, "_Sources", secondaryWaveSourcesBuffer);
                _waterDetailsCompute.SetTexture(_wavesKernel, "_LocalWavesRW",
                    _pingPong ? _detailsMapTwo[i] : _detailsMapOne[i]);
                _waterDetailsCompute.SetBuffer(_wavesKernel, "_ShapeWaves", waveBuffer);
                _waterDetailsCompute.Dispatch(_wavesKernel, gx, gy, 1);
            }
        }

        public void InitializeRenderTexture(int resolution)
        {
            for (var i = 0; i < _cascades; i++)
            {
                _detailsMapOne ??= new RenderTexture[_cascades];
                _detailsMapTwo ??= new RenderTexture[_cascades];
                
                if (_detailsMapOne[i] != null && (_detailsMapOne[i].width == resolution || _detailsMapOne[i].height == resolution)) return;
                if (_detailsMapTwo[i] != null && (_detailsMapTwo[i].width == resolution || _detailsMapTwo[i].height == resolution)) return;

                _detailsMapOne[i]?.Release();
                _detailsMapTwo[i]?.Release();

                _detailsMapOne[i] = new RenderTexture(resolution, resolution, 0, RenderTextureFormat.ARGBHalf)
                {
                    enableRandomWrite = true,
                    wrapMode = TextureWrapMode.Clamp,
                    filterMode = FilterMode.Bilinear,
                    name = $"LocalWaterDetailsOne_{i}",
                    autoGenerateMips = true
                };
                _detailsMapOne[i].Create();

                _detailsMapTwo[i] = new RenderTexture(resolution, resolution, 0, RenderTextureFormat.ARGBHalf)
                {
                    enableRandomWrite = true,
                    wrapMode = TextureWrapMode.Clamp,
                    filterMode = FilterMode.Bilinear,
                    name = $"LocalWaterDetailsTwo_{i}",
                    autoGenerateMips = true
                };
                _detailsMapTwo[i].Create();
            }
        }

        public RenderTexture GetDetailsRT(int cascade)
        {
            cascade = Mathf.Clamp(cascade, 0, _cascades);
            return _pingPong ? _detailsMapTwo[cascade] : _detailsMapOne[cascade];
        }

        private void ApplyOffset(Vector2 offset)
        {
            if (_waterDetailsCompute == null || _detailsMapOne == null) return;

            _pingPong = !_pingPong;
            
            for (var i =  0; i < _cascades; i++)
            {
                int gx = Mathf.CeilToInt(_detailsMapOne[i].width / (float)_tgx);
                int gy = Mathf.CeilToInt(_detailsMapOne[i].height / (float)_tgy);

                _waterDetailsCompute.SetVector("_MapCenterWS", _mapCenterWS);
                _waterDetailsCompute.SetVector("_DS", offset);
                _waterDetailsCompute.SetVector("_MapSizeWS", _mapSizeWS * Mathf.Pow(2, i));
                _waterDetailsCompute.SetInts("_Resolution", _detailsMapOne[i].width, _detailsMapOne[i].height);
                _waterDetailsCompute.SetTexture(_offsetKernel, "_LocalWavesR",
                    _pingPong ? _detailsMapOne[i] : _detailsMapTwo[i]);
                _waterDetailsCompute.SetTexture(_offsetKernel, "_LocalWavesW",
                    _pingPong ? _detailsMapTwo[i] : _detailsMapOne[i]);
                _waterDetailsCompute.Dispatch(_offsetKernel, gx, gy, 1);
            }
        }

        public void Dispose()
        {
            for (var i =  0; i < _cascades; i++)
            {
                _detailsMapOne[i]?.Release();
                _detailsMapTwo[i]?.Release();
            }
        }
    }
}