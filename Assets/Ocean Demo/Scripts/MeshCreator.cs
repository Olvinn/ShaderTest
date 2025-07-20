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

        var verticies = new Vector3[d * d];
        var uv = new Vector2[d * d];
        Vector3 offset = new Vector3(-_detalization * _size * .5f + .5f * _size, 0, -_detalization * _size * .5f + .5f * _size);
        for (int i = 0; i < d; i++)
            for (int j = 0; j < d; j++)
            {
                verticies[i * d + j] = new Vector3(i * _size, 0, j * _size) + offset;
                uv[i * d + j] = new Vector3((float)i / d, (float)j / d);
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

        mesh.vertices = verticies;
        mesh.triangles = triangles.ToArray();
        mesh.uv = uv;
        
        mesh.RecalculateNormals();
        mesh.RecalculateBounds();

        _meshFilter.mesh = mesh;
    }

    private void OnDrawGizmos()
    {
        if (!_meshFilter || !_meshFilter.sharedMesh || !_showGizmos)
            return;
        Gizmos.color = Color.red;
        var s = transform.localScale;
        foreach (var vertex in _meshFilter.sharedMesh.vertices)
        {
            var pos = new Vector3(vertex.x * s.x, vertex.y * s.y, vertex.z * s.z);
            Gizmos.DrawSphere(transform.rotation * pos, .05f);
        }
    }
}