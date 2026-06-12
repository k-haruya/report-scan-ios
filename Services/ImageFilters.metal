//
//  ImageFilters.metal
//  ReportScan
//
//  Metal CI Kernels for document scan image processing
//  Migrated from Core Image Kernel Language (CIKL) to Metal
//

#include <CoreImage/CoreImage.h>

using namespace metal;

extern "C" {
    namespace coreimage {

        // Adaptive Thresholding with darkFloor + saturation check
        // pixel: DivisionNorm後の画像
        // blurred: 局所背景推定（BoxBlur）
        // original: DivisionNorm後の画像（darkFloor判定用）
        float4 adaptiveThreshold(sample_t pixel, sample_t blurred, sample_t original,
                                  float offset, float strength, float darkFloor) {
            float brightness = dot(pixel.rgb, float3(0.299, 0.587, 0.114));
            float background = dot(blurred.rgb, float3(0.299, 0.587, 0.114));
            float threshold = background - offset;

            float origBrightness = dot(original.rgb, float3(0.299, 0.587, 0.114));
            float origMaxC = max(max(original.r, original.g), original.b);
            float origMinC = min(min(original.r, original.g), original.b);
            float origSat = origMaxC > 0.01 ? (origMaxC - origMinC) / origMaxC : 0.0;

            float textMask = (brightness < threshold || (origBrightness < darkFloor && origSat < 0.3)) ? 1.0 : 0.0;

            float3 result = mix(pixel.rgb, float3(1.0 - textMask), strength);
            return float4(result, 1.0);
        }

        // Division Normalization (背景除算)
        float4 divisionNormalize(sample_t original, sample_t background) {
            float minBg = 0.01;
            float r = background.r > minBg ? original.r / background.r : original.r;
            float g = background.g > minBg ? original.g / background.g : original.g;
            float b = background.b > minBg ? original.b / background.b : original.b;
            return float4(clamp(r, 0.0f, 1.0f), clamp(g, 0.0f, 1.0f), clamp(b, 0.0f, 1.0f), 1.0);
        }

        // Color Preservation (ハイブリッド方式)
        // processed: 二値化後の画像
        // colorRef: 元画像（色抽出用）
        // divNormRef: DivNorm後の画像（彩度判定用）
        float4 colorPreserve(sample_t processed, sample_t colorRef, sample_t divNormRef,
                              float satThreshold, float preservation, float boost) {
            float maxD = max(max(divNormRef.r, divNormRef.g), divNormRef.b);
            float minD = min(min(divNormRef.r, divNormRef.g), divNormRef.b);
            float saturation = maxD > 0.01 ? (maxD - minD) / maxD : 0.0;

            if (saturation > satThreshold) {
                float blendFactor = preservation * smoothstep(satThreshold, satThreshold + 0.1, saturation);

                float refLuma = dot(colorRef.rgb, float3(0.299, 0.587, 0.114));
                float3 chromaRatio = refLuma > 0.01 ? colorRef.rgb / refLuma : float3(1.0);
                float3 boostedChroma = mix(float3(1.0), chromaRatio, boost);

                float processedLuma = dot(processed.rgb, float3(0.299, 0.587, 0.114));
                float lumaFloor = refLuma * 0.5;
                float effectiveLuma = max(processedLuma, lumaFloor);

                float3 colorized = effectiveLuma * boostedChroma;
                colorized = clamp(colorized, 0.0f, 1.0f);

                float3 result = mix(processed.rgb, colorized, blendFactor);
                return float4(result, 1.0);
            }

            return processed;
        }
    }
}
