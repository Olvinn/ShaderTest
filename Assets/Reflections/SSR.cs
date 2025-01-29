using UnityEngine;

[ExecuteInEditMode]
public class SSR : MonoBehaviour
{
    public Material ssrMaterial;

    private void OnRenderImage(RenderTexture source, RenderTexture destination)
    {
        if (ssrMaterial != null)
        {
            Graphics.Blit(source, destination, ssrMaterial);
        }
        else
        {
            Graphics.Blit(source, destination);
        }
    }
}
