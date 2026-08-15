using UnityEditor;
using UnityEngine;

namespace Brod
{
    [CustomEditor(typeof(BuoyantBody))]
    public class BuoyantBodyEditor : Editor
    {
        private SerializedProperty _pointsProp;
        private bool _placing;

        private void OnEnable()
        {
            _pointsProp = serializedObject.FindProperty("_points");
        }

        public override void OnInspectorGUI()
        {
            DrawDefaultInspector();

            EditorGUILayout.Space();
            if (GUILayout.Button("Clear Points"))
            {
                serializedObject.Update();
                _pointsProp.ClearArray();
                serializedObject.ApplyModifiedProperties();
            }

            _placing = GUILayout.Toggle(_placing, "Place Points In Scene", "Button");
            if (_placing) SceneView.RepaintAll();
        }

        private void OnSceneGUI()
        {
            var body = (BuoyantBody)target;
            serializedObject.Update();

            for (int i = 0; i < _pointsProp.arraySize; i++)
            {
                var elem = _pointsProp.GetArrayElementAtIndex(i);
                Vector3 world = body.transform.TransformPoint(elem.vector3Value);

                EditorGUI.BeginChangeCheck();
                Vector3 moved = Handles.PositionHandle(world, body.transform.rotation);
                if (EditorGUI.EndChangeCheck())
                    elem.vector3Value = body.transform.InverseTransformPoint(moved);

                Handles.Label(world + Vector3.up * 0.3f, i.ToString());

                Handles.color = Color.red;
                if (Handles.Button(world + Vector3.right * 0.4f, Quaternion.identity, 0.08f, 0.12f, Handles.SphereHandleCap))
                {
                    _pointsProp.DeleteArrayElementAtIndex(i);
                    serializedObject.ApplyModifiedProperties();
                    return;
                }
                Handles.color = Color.white;
            }

            if (_placing)
            {
                Event e = Event.current;
                if (e.type == EventType.MouseDown && e.button == 0 && !e.alt)
                {
                    Ray ray = HandleUtility.GUIPointToWorldRay(e.mousePosition);
                    if (Physics.Raycast(ray, out RaycastHit hit))
                    {
                        int idx = _pointsProp.arraySize;
                        _pointsProp.InsertArrayElementAtIndex(idx);
                        _pointsProp.GetArrayElementAtIndex(idx).vector3Value =
                            body.transform.InverseTransformPoint(hit.point);
                        e.Use();
                    }
                }
                HandleUtility.AddDefaultControl(GUIUtility.GetControlID(FocusType.Passive));
            }

            serializedObject.ApplyModifiedProperties();
        }
    }
}
