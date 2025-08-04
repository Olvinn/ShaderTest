using System;
using UnityEngine;
using UnityEngine.Rendering;

namespace Ocean_Demo.Scripts
{
    [ExecuteInEditMode]
    [RequireComponent(typeof(Camera))]
    
    public class SSREffect : MonoBehaviour
    {
        private Camera cam;
        public Material[] targetMaterials;
        public RenderTexture lastFrameColor;
        
        void OnEnable()
        {
            cam = GetComponent<Camera>();
            SetupRenderTexture();
            cam.depthTextureMode |= DepthTextureMode.Depth;
        }

        void OnDisable()
        {
            if (lastFrameColor != null)
                lastFrameColor.Release();
        }

        void SetupRenderTexture()
        {
            if (lastFrameColor == null || lastFrameColor.width != Screen.width || lastFrameColor.height != Screen.height)
            {
                if (lastFrameColor != null)
                    lastFrameColor.Release();

                lastFrameColor = new RenderTexture(Screen.width, Screen.height, 0, RenderTextureFormat.ARGB32);
                lastFrameColor.Create();
            }
        }
        
        void ClearLastFrameColor(RenderTexture lastFrameColor)
        {
            RenderTexture activeRT = RenderTexture.active;
            RenderTexture.active = lastFrameColor;
            GL.Clear(true, true, Color.clear);
            RenderTexture.active = activeRT;
        }

        private void OnPreRender()
        {
            Shader.SetGlobalMatrix("unity_CameraInvProjection", cam.projectionMatrix.inverse);
            Shader.SetGlobalMatrix("unity_CameraToWorld", cam.cameraToWorldMatrix);
        }

        void OnRenderImage(RenderTexture src, RenderTexture dest)
        { 
            ClearLastFrameColor(lastFrameColor);
            SetupRenderTexture();
            
            Graphics.Blit(src, lastFrameColor);

            Graphics.Blit(src, dest);

            foreach (var mat in targetMaterials)
            {
                if (mat != null)
                    mat.SetTexture("_LastFrameColor", lastFrameColor);
            }
        }
    }
}
