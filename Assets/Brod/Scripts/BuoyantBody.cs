using UnityEngine;

namespace Brod
{
    [RequireComponent(typeof(Rigidbody))]
    public class BuoyantBody : MonoBehaviour
    {
        [SerializeField] private BrodWaterController _waterController;
        [SerializeField] private Vector3[] _points;
        [SerializeField] private float _forcePerPoint = 5000f;
        [SerializeField] private float _submersionDepth = 1f;
        [SerializeField] private int _wavesForPhysics = 24;
        [SerializeField] private float _linearDragInWater = 1.2f;
        [SerializeField] private float _angularDragInWater = 1.5f;
        [SerializeField] private float _linearDragInAir = 0.05f;
        [SerializeField] private float _angularDragInAir = 0.05f;

        private Rigidbody _rb;
        private const float G = 9.81f;

        private void Awake()
        {
            _rb = GetComponent<Rigidbody>();
        }

        private void FixedUpdate()
        {
            if (_waterController == null || _points == null || _points.Length == 0) return;

            Vector4[] waves = _waterController.ShapeWavesReady;
            if (waves == null || waves.Length == 0) return;

            int waveCount = Mathf.Min(_wavesForPhysics, waves.Length);
            float waterY = _waterController.transform.position.y;
            bool submerged = false;

            for (int i = 0; i < _points.Length; i++)
            {
                Vector3 point = transform.TransformPoint(_points[i]);
                float height = waterY + WaveHeight(point.x, point.z, waves, waveCount);
                float depth = height - point.y;
                if (depth <= 0f) continue;

                submerged = true;
                float force = _forcePerPoint * Mathf.Clamp01(depth / _submersionDepth);
                _rb.AddForceAtPosition(Vector3.up * force, point, ForceMode.Force);
            }

            _rb.linearDamping = submerged ? _linearDragInWater : _linearDragInAir;
            _rb.angularDamping = submerged ? _angularDragInWater : _angularDragInAir;
        }

        private float WaveHeight(float x, float z, Vector4[] waves, int count)
        {
            Vector2 pos = new Vector2(x, z);
            float height = 0f;
            for (int i = 0; i < count; i++)
            {
                Vector4 w = waves[i];
                float k = Mathf.PI * 2f / Mathf.Max(w.z, 1e-4f);
                float speed = Mathf.Sqrt(G * k);
                Vector2 dir = new Vector2(Mathf.Cos(w.x), Mathf.Sin(w.x));
                float phase = k * Vector2.Dot(dir, pos) - speed * Time.time;
                height += w.y * Mathf.Sin(phase);
            }
            return height;
        }

#if UNITY_EDITOR
        private void OnDrawGizmosSelected()
        {
            if (_points == null) return;
            Gizmos.color = Color.cyan;
            for (int i = 0; i < _points.Length; i++)
                Gizmos.DrawWireSphere(transform.TransformPoint(_points[i]), 0.15f);
        }
#endif
    }
}
