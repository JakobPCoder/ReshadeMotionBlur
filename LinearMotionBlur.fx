/** 
 - Reshade Linear Motion Blur 
 - First published 2022 - Copyright, Jakob Wapenhensch

# This work is licensed under the Creative Commons Attribution-NonCommercial 4.0 International (CC BY-NC 4.0) License
- https://creativecommons.org/licenses/by-nc/4.0/
- https://creativecommons.org/licenses/by-nc/4.0/legalcode

# Human-readable summary of the License and not a substitute for https://creativecommons.org/licenses/by-nc/4.0/legalcode:
You are free to:
- Share — copy and redistribute the material in any medium or format
- Adapt — remix, transform, and build upon the material
- The licensor cannot revoke these freedoms as long as you follow the license terms.

Under the following terms:
- Attribution — You must give appropriate credit, provide a link to the license, and indicate if changes were made. You may do so in any reasonable manner, but not in any way that suggests the licensor endorses you or your use.
- NonCommercial — You may not use the material for commercial purposes.
- No additional restrictions — You may not apply legal terms or technological measures that legally restrict others from doing anything the license permits.

Notices:
- You do not have to comply with the license for elements of the material in the public domain or where your use is permitted by an applicable exception or limitation.
- No warranties are given. The license may not give you all of the permissions necessary for your intended use. For example, other rights such as publicity, privacy, or moral rights may limit how you use the material.

 */


//  Includes
#include "ReShadeUI.fxh"
#include "ReShade.fxh"


//  Defines
uniform float frametime < source = "frametime"; >;


// UI
uniform float  UI_BLUR_LENGTH < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.1; ui_max = 1.0; ui_step = 0.01;
	ui_tooltip = "";
	ui_label = "Blur Length";
	ui_category = "Motion Blur";
> = 0.25;

uniform int  UI_BLUR_SAMPLES_MAX < __UNIFORM_SLIDER_INT1
	ui_min = 3; ui_max = 32; ui_step = 1;
	ui_tooltip = "";
	ui_label = "Samples";
	ui_category = "Motion Blur";
> = 5;

uniform float UI_TONEMAP_GAIN_SCALE <
    ui_label = "HDR Gain Scale";
    ui_min = 0.0;
    ui_max = 2.0;
    ui_step = 0.01;
	ui_type = "slider";
    ui_tooltip = 
	"Scale the contribution of HDR gain to blurred pixels.\n"
	"\n0.0 is basically LDR, while 2.0 is heavily boosted highlights.";
    ui_category = "Motion Blur";
> = 1.0;

uniform float UI_TONEMAP_GAIN_THRESHOLD <
    ui_label = "HDR Gain Threshold";
    ui_min = 0.5;
    ui_max = 1.0;
    ui_step = 0.01;
	ui_type = "slider";
    ui_tooltip = 
	"Threshold value for the HDR gain. Pixels with luminance above this value will be boosted.";
    ui_category = "Motion Blur";
> = 0.99;

uniform float UI_TONEMAP_GAIN_THRESHOLD_SMOOTH <
    ui_label = "HDR Gain Smoothness";
    ui_min = 0.0;
    ui_max = 0.5;
    ui_step = 0.01;
	ui_type = "slider";
    ui_tooltip = 
	"Smoothness value for the thresholding.";
    ui_category = "Motion Blur";
> = 0.49;

uniform bool UI_HQ_SAMPLING <
	ui_label = "High Quality Resampling";	
	ui_category = "Motion Blur";
> = false;

//  Textures & Samplers
texture2D texColor : COLOR;
sampler samplerColor { Texture = texColor; AddressU = Clamp; AddressV = Clamp; MipFilter = Linear; MinFilter = Linear; MagFilter = Linear; };

texture texMotionVectors          { Width = BUFFER_WIDTH;   Height = BUFFER_HEIGHT;   Format = RG16F; };
sampler SamplerMotionVectors2 { Texture = texMotionVectors; AddressU = Clamp; AddressV = Clamp; MipFilter = Point; MinFilter = Point; MagFilter = Point; };

// Passes

float4 BlurPS(float4 position : SV_Position, float2 texcoord : TEXCOORD ) : SV_Target
{	 
    float2 velocity = tex2D(SamplerMotionVectors2, texcoord).xy;
    float2 velocityTimed = velocity / frametime;
    float2 blurDist = velocityTimed * 50 * UI_BLUR_LENGTH;
    float2 sampleDist = blurDist / UI_BLUR_SAMPLES_MAX;
    int halfSamples = UI_BLUR_SAMPLES_MAX / 2;

    float4 summedSamples = 0.0;
    float4 currentSample = tex2D(samplerColor, texcoord);
    float4 maxSample = currentSample;
    for(int s = 0; s < UI_BLUR_SAMPLES_MAX; s++)
    {
        float4 sampled = tex2D(samplerColor, texcoord - sampleDist * (s - halfSamples));
        summedSamples += sampled / UI_BLUR_SAMPLES_MAX;
        maxSample.rgb = max(maxSample.rgb, sampled.rgb);
    }

    float4 tonemappedSample = maxSample;
    float luminance = dot(tonemappedSample.rgb, float3(0.2126, 0.7152, 0.0722));
    float exposure = log2(luminance * 4.0 + 1.0);

    // Apply tone mapping only to blurred pixels
	float3 blurredColor = tonemappedSample.rgb ;
	float3 tonemappedColor = blurredColor / (blurredColor + 1.0);
	tonemappedColor = clamp(tonemappedColor, 0.0, 1.0);
	float3 finalColor = lerp(tonemappedColor, tonemappedSample.rgb, smoothstep(UI_TONEMAP_GAIN_THRESHOLD - UI_TONEMAP_GAIN_THRESHOLD_SMOOTH, UI_TONEMAP_GAIN_THRESHOLD, tonemappedColor));
	tonemappedSample.rgb = lerp(blurredColor, finalColor, smoothstep(UI_TONEMAP_GAIN_THRESHOLD - UI_TONEMAP_GAIN_THRESHOLD_SMOOTH, UI_TONEMAP_GAIN_THRESHOLD, tonemappedColor));

	float4 finalcolor = lerp(summedSamples, float4(tonemappedSample.rgb, maxSample.a), smoothstep(UI_TONEMAP_GAIN_THRESHOLD - UI_TONEMAP_GAIN_THRESHOLD_SMOOTH, UI_TONEMAP_GAIN_THRESHOLD, luminance) * luminance * UI_TONEMAP_GAIN_SCALE);
	finalcolor = clamp(finalcolor, 0.0, 1.0);
    return finalcolor;
}

technique LinearMotionBlur
{
    pass PassBlurThatShit
    {
        VertexShader = PostProcessVS;
        PixelShader = BlurPS;
    }
}
