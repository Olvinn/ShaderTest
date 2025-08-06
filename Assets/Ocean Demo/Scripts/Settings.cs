using System;
using UnityEngine;

namespace Ocean_Demo.Scripts
{
    [Serializable]
    public struct SettingsProperty
    {
        public string Name;
        public bool BoolValue;
        public float FloatValue;
    }
    
    public class Settings : MonoBehaviour
    {
        public static Settings Instance;

        public SettingsProperty[] Properties;
        
        public event Action<SettingsProperty> onSettingsChanged;
        
        private SettingsProperty[] _savedProperties;

        private void Awake()
        {
            if (Instance == null)
                Instance = this;
            else
                Destroy(this);
        }

        private void Start()
        {
            _savedProperties = new SettingsProperty[Properties.Length];
            for (int i = 0; i < Properties.Length; i++)
                _savedProperties[i] = Properties[i];
        }

        private void Update()
        {
            if (Properties.Length == 0)
                return;
            
            if (Properties.Length != _savedProperties.Length)
                Start();
            
            for (int i = 0; i < Properties.Length; i++)
            {
                if (_savedProperties[i].BoolValue != Properties[i].BoolValue ||  !Mathf.Approximately(_savedProperties[i].FloatValue, Properties[i].FloatValue))
                {
                    onSettingsChanged?.Invoke(Properties[i]);
                    _savedProperties[i] =  Properties[i];
                }
            }
        }
    }
}
