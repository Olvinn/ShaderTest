using UnityEngine;

namespace Brod.Scripts
{
    [CreateAssetMenu(fileName = "BrodSettings", menuName = "Brod/Brod Settings")]
    public class BrodSettings : ScriptableObject
    {
        [Header("Compute shader")]
        public ComputeShader WaterComputeShader;

        [Header("Details Map Parameters")] 
        public int DetailsMapResolution = 512;
        [Range(1, 4)] public int Cascades = 4; 
        public Vector2 DetailsMapSizeWS;
        public float FoamLifetime;
        
        [Header("Wave Parameters")]
        public float SwellHeight = 3;
        public float WindSpeed = 13, Fetch = 250000, Storm = .17f;
    }
}
