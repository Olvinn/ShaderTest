using System.Collections.Generic;
using System.Linq;
using TMPro;
using UnityEngine;

namespace Ocean_Demo.Scripts
{
    public class SceneController : MonoBehaviour
    {
        [SerializeField] private Light _directionLight;
        [SerializeField] private OceanSceneTemplates _templates;
        [SerializeField] private OceanWaveController _oceanWaveController; 
        [SerializeField] private TMP_Dropdown _templateDropdown;

        private void Start()
        {
            _templateDropdown.options = new List<TMP_Dropdown.OptionData>(_templates.templates.Select(v => new TMP_Dropdown.OptionData(v.Name)));
            _templateDropdown.onValueChanged.AddListener(ChangeTemplate);
            ChangeTemplate(_templateDropdown.value);
        }

        private void ChangeTemplate(int templateNum)
        {
            _oceanWaveController.ChangeWater(_templates.templates[templateNum].Storm, _templates.templates[templateNum].Foam);
            var skyMat = RenderSettings.skybox;
            skyMat.SetTexture("_Tex", _templates.templates[templateNum].Cubemap);
            RenderSettings.fogColor = _templates.templates[templateNum].FogColor;
            RenderSettings.defaultReflectionMode = UnityEngine.Rendering.DefaultReflectionMode.Custom;
            RenderSettings.customReflectionTexture = _templates.templates[templateNum].Cubemap;
            _directionLight.transform.rotation = Quaternion.Euler(_templates.templates[templateNum].DirLightDirection);
            _directionLight.color = _templates.templates[templateNum].DirLightColor;
            _directionLight.intensity = _templates.templates[templateNum].DirLightIntensity;
            DynamicGI.UpdateEnvironment();
        }
    }
}
