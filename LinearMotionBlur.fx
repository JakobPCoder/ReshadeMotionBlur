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
> = 0.32;

uniform int  UI_BLUR_SAMPLES_MAX < __UNIFORM_SLIDER_INT1
	ui_min = 3; ui_max = 64; ui_step = 1;
	ui_tooltip = "";
	ui_label = "Samples";
	ui_category = "Motion Blur";
> = 48;

uniform float UI_GAIN_SCALE <
    ui_label = "HDR Gain Scale";
    ui_min = 0.0;
    ui_max = 10.0;
    ui_step = 0.01;
	ui_type = "slider";
    ui_tooltip = 
	"Scale the contribution of HDR gain to blurred pixels.\n"
	"\n0.0 is basically LDR, while 2.0 is heavily boosted highlights.";
    ui_category = "HDR Simulation";
> = 2.0;

uniform float UI_GAIN_POWER <
    ui_label = "HDR Gain Power";
    ui_min = 0.1;
    ui_max = 10.0;
    ui_step = 0.01;
	ui_type = "slider";
    ui_tooltip = 
	"Power used to shift the curve of the gain more towards the highlights";
    ui_category = "HDR Simulation";
> = 1.00;

uniform float UI_GAIN_REJECT <
    ui_label = "HDR Gain Reject";
    ui_min = 0.0;
    ui_max = 3.0;
    ui_step = 0.01;
	ui_type = "slider";
    ui_tooltip = 
	"This is used for rejecting neighbouring pixels if they are too bright,\n"
	"\nto avoid flickering in overly bright scens. 0.0 disables it.";
    ui_category = "HDR Simulation";
> = 2.35;

uniform float UI_GAIN_REJECT_RANGE <
    ui_label = "HDR Gain Reject Range";
    ui_min = 0.5;
    ui_max = 10;
    ui_step = 0.01;
	ui_type = "slider";
    ui_tooltip = 
	"Distance for sampling neighbour pixels for rejecting if too bright";
    ui_category = "HDR Simulation";
> = 4.0;

uniform float UI_GAIN_THRESHOLD <
    ui_label = "HDR Gain Threshold";
    ui_min = 0.5;
    ui_max = 1.0;
    ui_step = 0.01;
	ui_type = "slider";
    ui_tooltip = 
	"Threshold value for the HDR gain. Pixels with luminance above this value will be boosted.";
    ui_category = "HDR Simulation";
> = 1.00;

uniform float UI_GAIN_THRESHOLD_SMOOTH <
    ui_label = "HDR Gain Smoothness";
    ui_min = 0.0;
    ui_max = 1.0;
    ui_step = 0.01;
	ui_type = "slider";
    ui_tooltip = 
	"Smoothness value for the thresholding. 0.0 is no smoothness, 1.0 is max.";
    ui_category = "HDR Simulation";
> = 1.00;

uniform float UI_GAIN_SATURATION <
    ui_label = "HDR Gain Saturation";
    ui_min = 0.0;
    ui_max = 5.0;
    ui_step = 0.01;
	ui_type = "slider";
    ui_tooltip = 
	"Defines how much saturation we are preserving on gain.";
    ui_category = "HDR Simulation";
> = 1.5;

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

	float4 BlurredSample = maxSample;
	float luminance = dot(BlurredSample.rgb, float3(0.299, 0.587, 0.114));
	
	float4 finalcolor = summedSamples;

	// rejection function 
	float reject = 1.0;
	if (UI_GAIN_REJECT > 0.0)
	{
		float2 texCoordOffset = sampleDist * (UI_BLUR_SAMPLES_MAX * UI_GAIN_REJECT_RANGE);
		float2 neighborOffsets[9] = {
			float2(-1.0, -1.0), float2(0.0, -1.0), float2(1.0, -1.0),
			float2(-1.0, 0.0), float2(0.0, 0.0), float2(1.0, 0.0),
			float2(-1.0, 1.0), float2(0.0, 1.0), float2(1.0, 1.0)
		};
		float neighborLuminance = 0.0;
		float totalWeight = 0.0;
		for (int i = 0; i < 9; i++)
		{
			float2 neighborTexCoord = texcoord - texCoordOffset.xy + neighborOffsets[i] * texCoordOffset;
			float neighborLum = dot(tex2D(samplerColor, neighborTexCoord).rgb, float3(0.299, 0.587, 0.114));
			float lumDiff = luminance - neighborLum;
			float weight = exp(-(length(neighborOffsets[i]) / (UI_BLUR_SAMPLES_MAX * UI_GAIN_REJECT_RANGE)));
			neighborLuminance += lumDiff * weight;
			totalWeight += weight;
		}
		neighborLuminance /= totalWeight;
		float luminanceDiff = abs(luminance - neighborLuminance);
		float rejectThreshold = smoothstep((1.0 - UI_GAIN_REJECT), 1.0, luminanceDiff - UI_GAIN_THRESHOLD);
		reject = 1.0 - smoothstep(0.0, 1.0, rejectThreshold * UI_GAIN_REJECT);
	}
	
	float gain = pow(smoothstep(UI_GAIN_THRESHOLD - UI_GAIN_THRESHOLD_SMOOTH, UI_GAIN_THRESHOLD, luminance), UI_GAIN_POWER * UI_GAIN_POWER) * (luminance * UI_GAIN_SCALE);
	gain = saturate(gain * reject);

	finalcolor = summedSamples * (1.0 - gain) + BlurredSample * gain;
		
	float maxVal = max(max(finalcolor.r, finalcolor.g), finalcolor.b);
	float scale = 1.0 / max(maxVal, 1.0);

	finalcolor *= scale;

	float maxDiff = max(max(abs(finalcolor.r - BlurredSample.r), abs(finalcolor.g - BlurredSample.g)), abs(finalcolor.b - BlurredSample.b));
	float gainFactor = smoothstep(0.25, 1.0, maxDiff);

		if (gain > 0.0) {
			float3 lumCoeff = float3(0.299, 0.587, 0.114);
			float luma = dot(BlurredSample.rgb, lumCoeff);
			float3 gray = float3(luma, luma, luma);
			float3 color = lerp(gray, BlurredSample.rgb, UI_GAIN_SATURATION);
			finalcolor.rgb = lerp(finalcolor.rgb, color, gainFactor);
		}
		
	return clamp(finalcolor, 0.0, 1.0);
}

technique LinearMotionBlur
{
    pass PassBlurThatShit
    {
        VertexShader = PostProcessVS;
        PixelShader = BlurPS;
    }
}
