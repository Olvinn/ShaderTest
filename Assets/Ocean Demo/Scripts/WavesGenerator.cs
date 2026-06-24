using System;
using UnityEngine;
using Random = System.Random;

namespace Ocean_Demo.Scripts
{
    public static class WavesGenerator
    {
        const float G          = 9.81f;
        const float TWO_PI     = Mathf.PI * 2f;
        const float LAMBDA_MIN = 1f;
        const float LAMBDA_MAX = 200f;

        /// <summary>
        /// x: angle (rad), y: amplitude (m), z: wavelength (m), w: steepness
        /// steepness = Q / (k * amp) — NOT a 0..1 value
        /// Folding occurs when steepness * k * amp >= 1 per wave
        /// </summary>
        /// <param name="swellHeight">Dominant wave amplitude in meters. 1=calm, 3=moderate, 6=storm</param>
        /// <param name="windSpeed">Moves spectral peak. 8=short chop, 13=swell, 18=long swell</param>
        /// <param name="fetch">Wind travel distance. 50k=coastal, 250k=open ocean</param>
        /// <param name="storm">0..1 — controls Q directly. 0=no foam, 0.5=moderate, 1=heavy breaking</param>
        public static Vector4[] GetShapeWaves(
            float swellHeight = 3f,
            float windSpeed   = 13f,
            float fetch       = 250000f,
            float storm       = 0.5f,
            int   seed        = 42)
        {
            var rng   = new Random(seed);
            var waves = new Vector4[128]; 

            float omegaPeak = 22f * Mathf.Pow((G * G) / (windSpeed * fetch), 1f / 3f);
            float omegaMin  = Mathf.Sqrt(G * TWO_PI / LAMBDA_MAX); // ω at 200m
            float omegaMax  = Mathf.Sqrt(G * TWO_PI / LAMBDA_MIN); // ω at 3m
            float dOmega    = (omegaMax - omegaMin) / 128f;

            float peakEnergy = JONSWAP(omegaPeak, omegaPeak);
            float normFactor = swellHeight
                             / Mathf.Max(Mathf.Sqrt(2f * peakEnergy * dOmega), 0.0001f);

            for(int i = 0; i < 128; i++)
            {
                float t      = (i + (float)rng.NextDouble()) / 128f;
                float omega  = omegaMin + t * (omegaMax - omegaMin);
                float k      = omega * omega / G;
                float lambda = TWO_PI / k;

                float energy = JONSWAP(omega, omegaPeak);
                float amp    = Mathf.Sqrt(2f * energy * dOmega) * normFactor;
                amp          = Mathf.Max(amp, 0.001f);

                float lambdaT   = Mathf.InverseLerp(LAMBDA_MAX, LAMBDA_MIN, lambda);
                float spreadRad = Mathf.Lerp(0.17f, Mathf.PI * 0.9f, lambdaT * lambdaT);
                float angle     = (float)(rng.NextDouble() * 2.0 - 1.0) * spreadRad;

                float steepScale = Mathf.Lerp(0.5f, 1.0f,
                                               Mathf.InverseLerp(LAMBDA_MIN, LAMBDA_MAX, lambda));
                float Q          = steepScale;

                float steepness  = Q / Mathf.Max(k * amp, 0.001f) * storm;

                waves[i] = new Vector4(angle, amp, lambda, steepness);
            }

            Array.Sort(waves, (a, b) => b.z.CompareTo(a.z));
            return waves;
        }

        private static float JONSWAP(float omega, float omegaPeak, float gamma = 3.3f)
        {
            const float alpha = 0.0081f;
            const float beta  = 1.25f;
            float sigma = omega <= omegaPeak ? 0.07f : 0.09f;
            float r     = Mathf.Exp(
                            -(omega - omegaPeak) * (omega - omegaPeak)
                            / (2f * sigma * sigma * omegaPeak * omegaPeak));
            return Mathf.Max(0f,
                (alpha * G * G / Mathf.Pow(omega, 5f))
                * Mathf.Exp(-beta * Mathf.Pow(omegaPeak / omega, 4f))
                * Mathf.Pow(gamma, r));
        }
    }
}