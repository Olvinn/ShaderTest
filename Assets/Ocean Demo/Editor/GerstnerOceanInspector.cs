using UnityEditor;
using UnityEngine;

public class GerstnerOceanInspector : ShaderGUI
{
    public override void OnGUI(MaterialEditor materialEditor, MaterialProperty[] properties)
    {
        Material mat = materialEditor.target as Material;

        bool tessellation = mat.IsKeywordEnabled("TESSELATION");

        foreach (var prop in properties)
        {
            if (prop.name == "_TessFactor")
            {
                tessellation = EditorGUILayout.Toggle("Tessellation", tessellation);
                if (!tessellation)
                    continue;
            }

            materialEditor.ShaderProperty(prop, prop.displayName);
        }

        materialEditor.RenderQueueField();
        
        if (tessellation)
            mat.EnableKeyword("TESSELATION");
        else
            mat.DisableKeyword("TESSELATION");
    }
}
