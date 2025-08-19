using TMPro;
using UnityEngine;

namespace Ocean_Demo.Scripts
{
    public class SceneController : MonoBehaviour
    {
        [SerializeField] private OceanWaveController _oceanWaveController; 
        [SerializeField] private TMP_Dropdown _templateDropdown;

        private void Start()
        {
            _templateDropdown.onValueChanged.AddListener(ChangeTemplate);
            ChangeTemplate(_templateDropdown.value);
        }

        private void ChangeTemplate(int templateNum)
        {
            switch (templateNum)
            {
                case 0:
                    _oceanWaveController.ChangeWater(0);
                    break;
                case 1:
                    _oceanWaveController.ChangeWater(.15f);
                    break;
                case 2:
                    _oceanWaveController.ChangeWater(1f);
                    break;
            }
        }
    }
}
