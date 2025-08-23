using System;
using UnityEngine;

namespace Ocean_Demo.Scripts
{
    [Serializable]
    public struct Template
    {
        public string Name;
        public float Storm;
        public float Foam;
        public Cubemap Cubemap;
        public Color FogColor;
        public Vector3 DirLightDirection;
        public float DirLightIntensity;
        public Color DirLightColor;
    }
    
    [CreateAssetMenu(menuName = "Ocean Scene Templates")]
    public class OceanSceneTemplates : ScriptableObject
    {
        public Template[] templates;
    }
}
