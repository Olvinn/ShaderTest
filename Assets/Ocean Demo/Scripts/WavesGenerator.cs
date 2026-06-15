using UnityEngine;

namespace Ocean_Demo.Scripts
{
    public static class WavesGenerator
    {
        /// <summary>
        /// Returns shape waves [5; 120] m length
        /// </summary>
        /// <returns>x: angle (rad), y: amplitude, z: length, w: steepness</returns>
        public static Vector4[] GetShapeWaves()
        {
            var result = new Vector4[128];
            //Big swells
            for (int i = 0; i < 64; i++)
            {
                var a = i * 360f / 64f + Random.Range(-5f, 5f);
                a *= Mathf.Deg2Rad;
                result[i] = new Vector4(a, Random.Range(.05f, .15f), Random.Range(30f, 120f), Random.Range(.75f, 2f));
            }
            
            //Secondary waves
            for (int i = 64; i < 96; i++)
            {
                var a = i * 360f / 32 + Random.Range(-10f, 10f);
                a *= Mathf.Deg2Rad;
                result[i] = new Vector4(a, Random.Range(.005f, .02f), Random.Range(5f, 30f), Random.Range(.75f, 1.25f));
            }
            
            //Secondary waves
            for (int i = 96; i < 128; i++)
            {
                var a = i * 360f / 32 + Random.Range(-10f, 10f);
                a *= Mathf.Deg2Rad;
                result[i] = new Vector4(a, Random.Range(.0005f, .001f), Random.Range(1f, 5f), Random.Range(1.5f, 3f));
            }

            return result;
        }
    }
}