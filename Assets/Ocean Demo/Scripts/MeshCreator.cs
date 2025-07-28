using System.Collections.Generic;
using UnityEngine;

public class MeshCreator : MonoBehaviour
{
    [SerializeField] private bool _showGizmos;
    [SerializeField] private int _detalization;
    [SerializeField] private float _size;
    [SerializeField] private MeshFilter _meshFilter;

    private void OnValidate()
    {
        CreateMesh();
    }

    private void CreateMesh()
    {
        Mesh mesh = new Mesh();

        var d = _detalization;

        var vertices = new Vector3[d * d];
        var uv = new Vector2[d * d];
        float growth = _size / (_detalization - 1); // Optional for exact edge fit
        Vector3 offset = new Vector3(-_size * 0.5f, 0, -_size * 0.5f);

        for (int i = 0; i < d; i++)
            for (int j = 0; j < d; j++)
            {
                vertices[i * d + j] = new Vector3(i * growth, 0, j * growth) + offset;
                uv[i * d + j] = new Vector2((float)i / (d - 1), (float)j / (d - 1));
            }

        var triangles = new List<int>();
        for (int i = 0; i < d - 1; i++)
        {
            for (int j = 0; j < d - 1; j++)
            {
                triangles.Add(i + j * d);
                triangles.Add(i + j * d + 1);
                triangles.Add(i + j * d + d);
                triangles.Add(i + j * d + 1);
                triangles.Add(i + j * d + d + 1);
                triangles.Add(i + j * d + d);
            }
        } 

        mesh.vertices = vertices;
        mesh.triangles = triangles.ToArray();
        mesh.uv = uv;
        
        mesh.RecalculateNormals();
        mesh.RecalculateBounds();

        _meshFilter.mesh = mesh;
    }
}