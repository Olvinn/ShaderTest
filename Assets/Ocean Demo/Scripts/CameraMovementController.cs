using UnityEngine;

namespace Ocean_Demo.Scripts
{
    public class CameraMovementController : MonoBehaviour
    {
        private Vector2 _angle;
        
        void Start()
        {
        
        }

        void LateUpdate()
        {
            _angle.x += -Input.GetAxis("Mouse Y");
            _angle.y += Input.GetAxis("Mouse X");
            _angle.x = Mathf.Clamp(_angle.x, -89.9f, 89.9f);
            transform.rotation = Quaternion.LookRotation(Quaternion.Euler(_angle.x, _angle.y, 0) * Vector3.forward, Vector3.up); 
            
            transform.position += transform.rotation * new Vector3(Input.GetAxis("Horizontal"), 0, Input.GetAxis("Vertical")) * (Time.deltaTime * 100f);
            transform.position = new Vector3(transform.position.x, Mathf.Clamp(transform.position.y, 5, 150), transform.position.z);
        }
    }
}
