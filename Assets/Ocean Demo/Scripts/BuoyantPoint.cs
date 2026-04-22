using UnityEngine;

namespace Ocean_Demo.Scripts
{
    [RequireComponent(typeof(Rigidbody))]
    public class BuoyantPoint : MonoBehaviour
    {
        [SerializeField] OceanWaveController _WaveController;
        [SerializeField] private ParticleSystem _splash;
        
        public float Radius = .25f;
        public float WaveAmplitude = .25f;
        public float WaveLength = .5f;
        
        public float buoyancyForce;
        public bool torque = true;
        
        public bool _inAir = false;
        private Rigidbody _rb;
        private int _waveSourceIndex;
        
        void Start()
        {
            _rb = GetComponent<Rigidbody>();
            
            var src = new OceanWaveController.WaveSource
            {
                posWS     = new Vector2(transform.position.x, transform.position.z),
                radius    = Radius,
                amplitude = WaveAmplitude,
                wavelength= WaveLength,
                speed     = 0f,
                decay     = 1.0f,
                type      = 0f,        // radial
                angleDeg  = 0f
            };
            _waveSourceIndex = _WaveController.AddSource(src);
        }
        
        void FixedUpdate()
        {
            Vector3 waveNormal = GetGerstnerNormal(
                new Vector2(_rb.position.x,  _rb.position.z),
                Time.time,
                _WaveController.waveDirectionsReady,
            32);
            Vector3 waveOffset = GetGerstnerOffset(
                new Vector2(_rb.position.x,  _rb.position.z),
                Time.time,
                _WaveController.waveDirectionsReady,
                64);
            
            //if (_rb.position.y > waveOffset.y) return;
        
            Vector3 position = _rb.position;
        
            float depth = waveOffset.y - position.y;
        
            if (depth >= 0f)
            {
                if (_inAir)
                {
                    if (_splash)
                        _splash.Play();
                    _inAir = false;
                }
                
                depth = Mathf.Clamp01(depth);
        
                Vector3 force = Vector3.up * (depth * buoyancyForce);
                _rb.AddForce(force, ForceMode.Force);
        
                Vector3 drag = -_rb.linearVelocity * Time.fixedDeltaTime;
                _rb.AddForce(drag, ForceMode.VelocityChange);
        
                if (torque)
                {
                    Quaternion targetRotation =
                        Quaternion.LookRotation(Vector3.Cross(transform.right, waveNormal), waveNormal);
                    Quaternion delta = targetRotation * Quaternion.Inverse(_rb.rotation);
                    delta.ToAngleAxis(out float angle, out Vector3 axis);
        
                    if (angle > 180f) angle -= 360f;
                    if (Mathf.Abs(angle) > 0.01f)
                        _rb.AddTorque(axis * angle);
        
                    Vector3 angDrag = -_rb.angularVelocity * Time.fixedDeltaTime;
                    _rb.AddTorque(angDrag, ForceMode.VelocityChange);
                }
            }
            else
                _inAir = true;
            
            _WaveController.UpdateSource(_waveSourceIndex, 
                new OceanWaveController.WaveSource
                {
                    posWS     = new Vector2(transform.position.x, transform.position.z),
                    radius    = Radius,
                    amplitude = WaveAmplitude,
                    wavelength= WaveLength,
                    speed = 2f,
                    decay = 1.7f,
                    type = 0f,          // directional
                    angleDeg  = 1f
                });
        }
        
        // void Update()
        // {
        //     Vector3 normal = new Vector3();
        //     var offset =  GetGerstnerOffset(new Vector2(transform.position.x, transform.position.z), Time.time,  out normal);
        //     transform.position = offset;
        //     transform.up = normal;
        // }
        
        void GetWaveParams(float waveLength, out float k, out float omega)
        {
            k     = Mathf.PI * 2 / waveLength;
            omega = Mathf.Sqrt(9.81f * k);
        }
        
        Vector3 GerstnerWave(Vector2 pos, Vector2 dir, float k, float amp,
            float steepness, float speed, float time)
        {
            float phase = k * Vector2.Dot(dir, pos) - speed * time;
            float sinP  = Mathf.Sin(phase);
            float cosP  = Mathf.Cos(phase);

            return new Vector3(
                steepness * amp * dir.x * cosP,
                amp * sinP,
                steepness * amp * dir.y * cosP
            );
        }

        Vector3 GerstnerWaveNormal(Vector2 pos, Vector2 dir, float k, float amp,
            float steepness, float speed, float time)
        {
            float phase = k * Vector2.Dot(dir, pos) - speed * time;
            float sinP  = Mathf.Sin(phase);
            float cosP  = Mathf.Cos(phase);

            Vector3 normal = Vector3.zero;
            normal.x += -dir.x * k * amp * cosP;
            normal.y -= steepness * amp * k * sinP;
            normal.z += -dir.y * k * amp * cosP;
            
            return normal;
        }
        
        Vector3 GetGerstnerOffset(Vector2 worldXZ, float time, Vector4[] _WaveDirs,
        int count)
        {
            Vector3 offset = new Vector3(0, 0, 0);

            for (int i = 0; i < count; i++)
            {
                float k, speed, steepness = _WaveDirs[i].w;
                GetWaveParams(_WaveDirs[i].z, out k, out speed);

                float a = Mathf.Acos(_WaveDirs[i].x % 1);
                float x = Mathf.Cos(a);
                float y = Mathf.Sin(a);
                Vector2 dir = (new Vector2(x, y)).normalized;
                offset += GerstnerWave(worldXZ, dir, k, _WaveDirs[i].y, steepness, speed, time);
            }

            return offset;
        }
        
        Vector3 GetGerstnerNormal(Vector2 worldXZ, float time, Vector4[] _WaveDirs, int count)
        {
            Vector3 normal    = new Vector3(0, 1, 0); 

            for (int i = 0; i < count; i++)
            {
                float k, speed, steepness = _WaveDirs[i].w;
                GetWaveParams(_WaveDirs[i].z, out k, out speed);

                float a = Mathf.Acos(_WaveDirs[i].x % 1);
                float x = Mathf.Cos(a);
                float y = Mathf.Sin(a);
                Vector2 dir = (new Vector2(x, y)).normalized;
                GerstnerWaveNormal(worldXZ, dir, k, _WaveDirs[i].y, steepness, speed, time);
            }
            
            return normal.normalized;
        }
    }
}
