using System;
using UnityEngine;

namespace Ocean_Demo.Scripts
{
    [ExecuteInEditMode]
    [RequireComponent(typeof(Camera))]
    public class BloomEffect : MonoBehaviour
    {
        public Shader bloomShader;
        private Material _bloomMat;

        [Range(0, 5)] public float intensity = 1.2f;
        [Range(1, 8)] public int blurIterations = 3;
        [Range(0, 1)] public float threshold = 0.8f;

        void Awake()
        {
            Settings.Instance.onSettingsChanged += OnSettingsChanged;
        }

        private void OnSettingsChanged(SettingsProperty data)
        {
            if (data.Name == "Bloom")
                enabled = data.BoolValue;
        }

        void OnRenderImage(RenderTexture src, RenderTexture dst)
        {
            if (_bloomMat == null)
                _bloomMat = new Material(bloomShader);

            _bloomMat.SetFloat("_Intensity", intensity);
            _bloomMat.SetFloat("_Threshold", threshold);

            int rtW = src.width / 2;
            int rtH = src.height / 2;

            RenderTexture brightPass = RenderTexture.GetTemporary(rtW, rtH, 0);
            RenderTexture blur1 = RenderTexture.GetTemporary(rtW, rtH, 0);
            RenderTexture blur2 = RenderTexture.GetTemporary(rtW, rtH, 0);

            // Bright pass
            Graphics.Blit(src, brightPass, _bloomMat, 0);

            // Blur horizontally and vertically
            for (int i = 0; i < blurIterations; i++)
            {
                Graphics.Blit(brightPass, blur1, _bloomMat, 1); // horizontal
                Graphics.Blit(blur1, brightPass, _bloomMat, 2); // vertical
            }

            // Composite back
            _bloomMat.SetTexture("_BloomTex", brightPass);
            Graphics.Blit(src, dst, _bloomMat, 3);

            RenderTexture.ReleaseTemporary(brightPass);
            RenderTexture.ReleaseTemporary(blur1);
            RenderTexture.ReleaseTemporary(blur2);
        }
    }
}