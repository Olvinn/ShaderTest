using UnityEditor;
using UnityEngine;

public class GerstnerOceanInspector : ShaderGUI
{
    public override void OnGUI(MaterialEditor materialEditor, MaterialProperty[] properties)
    {
        Material mat = materialEditor.target as Material;

        bool ssr = mat.IsKeywordEnabled("SSR");

        foreach (var prop in properties)
        {
            if (prop.name == "_SSRSteps")
            {
                ssr = EditorGUILayout.Toggle("SSR", ssr);
                if (!ssr)
                    continue;
                else
                    EditorGUI.indentLevel++;
            }
            else if (prop.name == "_SSRThickness")
            {
                if (!ssr)
                    continue;
                else
                    EditorGUI.indentLevel++;
            }
            else if (prop.name == "_SSRStepSize")
            {
                if (!ssr)
                    continue;
                else
                    EditorGUI.indentLevel++;
            }

            materialEditor.ShaderProperty(prop, prop.displayName);
            if (EditorGUI.indentLevel > 0)
                EditorGUI.indentLevel--;
        }

        materialEditor.RenderQueueField();
        
        if (ssr)
            mat.EnableKeyword("SSR");
        else
            mat.DisableKeyword("SSR");
    }
}
