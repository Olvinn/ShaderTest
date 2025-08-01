using UnityEngine;

namespace Ocean_Demo.Scripts
{
    [RequireComponent(typeof(Rigidbody))]
    public class BuoyantPoint : MonoBehaviour
    {
        [SerializeField] OceanWaveController _WaveController;

        public float buoyancyForce;
        public bool torque = true;
        
        private Rigidbody _rb;
        private Vector3 _initialPosition;
    
        void Start()
        {
            _rb = GetComponent<Rigidbody>();
            _initialPosition = transform.position;
        }

        void FixedUpdate()
        {
            Vector3 waveNormal;
            Vector3 waveOffset = GerstnerDisplace(_initialPosition, out waveNormal);
            float waterHeight = waveOffset.y;

            Vector3 position = _rb.position;

            float depth = waterHeight - position.y;

            if (depth > 0f)
            {
                Vector3 force = Vector3.up * (depth * buoyancyForce);
                _rb.AddForce(force, ForceMode.Force);

                Vector3 drag = -_rb.linearVelocity;
                _rb.AddForce(drag, ForceMode.Force);
            }

            if (!torque) return;
            
            Quaternion targetRotation = Quaternion.LookRotation(Vector3.Cross(transform.right, waveNormal), waveNormal);
            Quaternion delta = targetRotation * Quaternion.Inverse(_rb.rotation);
            delta.ToAngleAxis(out float angle, out Vector3 axis);

            if (angle > 180f) angle -= 360f;
            if (Mathf.Abs(angle) > 0.01f)
                _rb.AddTorque(axis * angle);
        }
        
        // void Update()
        // {
        //     Vector3 normal = new Vector3();
        //     var offset =  GerstnerDisplace(_initialPosition, out normal);
        //     transform.position = offset;
        //     transform.up = normal;
        // }
        
        private void WaveDistribution(int i, ref float waveLength, ref float waveAmplitude)
        {
            waveLength = _WaveController.waveLength / Mathf.Pow(_WaveController.waveLengthDistribution, i);
            waveAmplitude = _WaveController.waveStrength / Mathf.Pow(_WaveController.waveStrengthDistribution, i);
        }
        
        private Vector3 GerstnerDisplace(Vector3 worldPos, out Vector3 normal)
        {
            Vector3 totalOffset = Vector3.zero;
            Vector3 tangentX = new Vector3(1, 0, 0); 
            Vector3 tangentZ = new Vector3(0, 0, 1); 
    
            for (int i = 0; i < _WaveController.waveDirections.Length; i++)
            {
                Vector2 dir = new Vector2(_WaveController.waveDirections[i].x, _WaveController.waveDirections[i].y);
                float wavelength = 0;
                float amplitude = 0;
                WaveDistribution(i, ref wavelength, ref amplitude);
                float k = Mathf.PI / wavelength;
                float speed = Mathf.Sqrt(9.81f * k);
                float phase = k * Vector2.Dot(dir, new Vector2(worldPos.x, worldPos.z)) - speed * Time.time;

                float sinP = Mathf.Sin(phase);
                float cosP = Mathf.Cos(phase);

                float Qi = _WaveController.waveSteepness / (k * amplitude * _WaveController.waveDirections.Length);

                totalOffset.x += Qi * dir.x * amplitude * cosP;
                totalOffset.z += Qi * dir.y * amplitude * cosP;
                totalOffset.y += amplitude * sinP;
                
                if (i > 8) continue;

                Vector2 dPhase_dXZ = k * dir;

                float dYdX = amplitude * cosP * dPhase_dXZ.x;
                float dYdZ = amplitude * cosP * dPhase_dXZ.y;

                float dXdX = -Qi * dir.x * amplitude * sinP * dPhase_dXZ.x;
                float dZdX = -Qi * dir.y * amplitude * sinP * dPhase_dXZ.x;

                float dXdZ = -Qi * dir.x * amplitude * sinP * dPhase_dXZ.y;
                float dZdZ = -Qi * dir.y * amplitude * sinP * dPhase_dXZ.y;

                tangentX += new Vector3(dXdX, dYdX, dZdX);
                tangentZ += new Vector3(dXdZ, dYdZ, dZdZ);
            }

            normal = Vector3.Normalize(Vector3.Cross(tangentZ, tangentX));

            return totalOffset;
        }
    }
}
