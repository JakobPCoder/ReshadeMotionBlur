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


// Includes
#include "ReShadeUI.fxh"
#include "ReShade.fxh"

// Defines

#ifndef SRGB_INPUT_COLOR
#define SRGB_INPUT_COLOR 1
#endif

#ifndef SRGB_OUTPUT_COLOR
#define SRGB_OUTPUT_COLOR 1
#endif

#define SATURATION_THRESHOLD 0.25

const static float3 lumCoeffGamma = float3(0.299, 0.587, 0.114);
const static float3 lumCoeffLinear = float3(0.2126, 0.7152, 0.0722);

uniform float frametime < source = "frametime"; >;

// UI

uniform bool HDR_DISPLAY_OUTPUT
<
	ui_category = "Motion Blur";
	//ui_category_closed = false;
	ui_label = "Real HDR input and display?";
	ui_tooltip =
		"If real HDR display and input is used, output clamping is turned off\n"
		"\nIt's also probably worth setting all gain and thresholding to zero, but depending on the setup it may still be required";
> = false;

uniform float  UI_BLUR_LENGTH < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.1; ui_max = 0.5; ui_step = 0.01;
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
	"Scale the contribution of gain to blurred pixels.\n"
	"\n0.0 is basically no gain, while 2.0 is heavily boosted highlights.";
    ui_category = "HDR Simulation";
> = 1.50;

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
    ui_max = 10.0;
    ui_step = 0.01;
	ui_type = "slider";
    ui_tooltip = 
	"This is used for rejecting neighbouring pixels if they are too bright,\n"
	"\nto avoid flickering in overly bright scens. 0.0 disables this function completely.";
    ui_category = "HDR Simulation";
> = 3.50;

uniform float UI_GAIN_REJECT_RANGE <
    ui_label = "HDR Gain Reject Range";
    ui_min = 0.01;
    ui_max = 10.0;
    ui_step = 0.01;
	ui_type = "slider";
    ui_tooltip = 
	"Distance to sample neighbor pixels for rejecting";
    ui_category = "HDR Simulation";
> = 3.50;

uniform float UI_GAIN_THRESHOLD <
    ui_label = "HDR Gain Threshold";
    ui_min = 0.0;
    ui_max = 1.0;
    ui_step = 0.01;
	ui_type = "slider";
    ui_tooltip = 
	"Pixels with luminance above this value will be boosted.";
    ui_category = "HDR Simulation";
> = 1.00;

uniform float UI_GAIN_THRESHOLD_SMOOTH <
    ui_label = "HDR Gain Smoothness";
    ui_min = 0.0;
    ui_max = 10.0;
    ui_step = 0.01;
	ui_type = "slider";
    ui_tooltip = 
	"Thresholding that smoothly interpolates between max and min value of luminance.";
    ui_category = "HDR Simulation";
> = 5.00;

//  Textures & Samplers
texture texColor : COLOR;
sampler samplerColor 
{ 
	Texture = texColor;
	
	#if SRGB_INPUT_COLOR
		SRGBTexture = true;
	#endif
	
	AddressU = Clamp; AddressV = Clamp; MipFilter = Linear; MinFilter = Linear; MagFilter = Linear; 
};

texture texMotionVectors          { Width = BUFFER_WIDTH;   Height = BUFFER_HEIGHT;   Format = RG16F; };
sampler SamplerMotionVectors2 { Texture = texMotionVectors; AddressU = Clamp; AddressV = Clamp; MipFilter = Point; MinFilter = Point; MagFilter = Point; };

// Pixel Shader
float4 BlurPS(float4 position : SV_Position, float2 texcoord : TEXCOORD ) : SV_Target
{	  
	float2 velocity = tex2D(SamplerMotionVectors2, texcoord).xy;
	float2 velocityTimed = velocity / frametime;
	float2 blurDist = velocityTimed * 50 * UI_BLUR_LENGTH;
	float2 sampleDist = blurDist / UI_BLUR_SAMPLES_MAX;
	int halfSamples = UI_BLUR_SAMPLES_MAX / 2;

	float4 summedSamples = 0;
	float4 color = tex2D(samplerColor, texcoord);
	for(int s = 0; s < UI_BLUR_SAMPLES_MAX; s++)
	{
		float4 sampled = tex2D(samplerColor, texcoord - sampleDist * (s - halfSamples));
		summedSamples += sampled / UI_BLUR_SAMPLES_MAX;
		color.rgb = max(color.rgb, sampled.rgb);
	}
	
	float luminance = 0.0;
	
	if (HDR_DISPLAY_OUTPUT)
		luminance = dot(color.rgb, lumCoeffLinear);
	else
		luminance = dot(color.rgb, lumCoeffGamma);
	
	float4 finalcolor = summedSamples;
	
	float gain = 0.0;
	// Gain Function
	if (HDR_DISPLAY_OUTPUT)
		gain = pow(smoothstep((UI_GAIN_THRESHOLD) - (UI_GAIN_THRESHOLD_SMOOTH), (UI_GAIN_THRESHOLD * 100), luminance), UI_GAIN_POWER) * (smoothstep(-(UI_GAIN_THRESHOLD_SMOOTH * 100), 1.0, luminance) * UI_GAIN_SCALE);	
	else
		gain = pow(smoothstep(UI_GAIN_THRESHOLD - UI_GAIN_THRESHOLD_SMOOTH, UI_GAIN_THRESHOLD, luminance), UI_GAIN_POWER) * (smoothstep(-UI_GAIN_THRESHOLD_SMOOTH, 1.0, luminance) * UI_GAIN_SCALE);
	// Rejection Function 
	float reject = 1.0;
	if (UI_GAIN_REJECT > 0.0)
	{
		float2 texCoordOffset = sampleDist * (UI_BLUR_SAMPLES_MAX * UI_GAIN_REJECT_RANGE);
		float neighborLuminance = 0.0;
		float luminanceRatio = 0.0;
		float totalWeight = 0.0;
		float neighborLum = 0.0;
		for (int i = 0; i < UI_BLUR_SAMPLES_MAX; i++)
		{
			float2 neighborTexCoord = texcoord - sampleDist * (i - halfSamples) * UI_GAIN_REJECT_RANGE;
			if (HDR_DISPLAY_OUTPUT)
				neighborLum = dot(tex2D(samplerColor, neighborTexCoord).rgb, lumCoeffLinear);
			else
				neighborLum = dot(tex2D(samplerColor, neighborTexCoord).rgb, lumCoeffGamma);
            		float luminanceDiff = neighborLum - luminance;
			float distanceWeight = exp(-(length(normalize(sampleDist * (i - halfSamples))) + luminanceDiff) / (UI_BLUR_SAMPLES_MAX * UI_GAIN_REJECT_RANGE));
			neighborLuminance += neighborLum * distanceWeight;
			totalWeight += distanceWeight;
			if (neighborLum > luminance) {
				luminanceRatio += luminance / neighborLum;
			} else {
				luminanceRatio += neighborLum / luminance;
			}
		}
		neighborLuminance /= totalWeight;
		float avgLuminanceRatio = luminanceRatio / UI_BLUR_SAMPLES_MAX;
		float rejectThreshold = smoothstep(0.0, gain, avgLuminanceRatio);
		reject = 1.0 - smoothstep(0.0, gain, rejectThreshold * UI_GAIN_REJECT);
	}

	gain = saturate(gain * reject);
	
	if (HDR_DISPLAY_OUTPUT)
		finalcolor *= 1.0 / max(dot(summedSamples.rgb, lumCoeffLinear), 1.0);
	else
		finalcolor *= 1.0 / max(dot(summedSamples.rgb, lumCoeffGamma), 1.0);
		
	finalcolor = summedSamples * (1.0 - gain) + color * gain;
	
	if (HDR_DISPLAY_OUTPUT)		 	
		return finalcolor;
	else 
		return clamp(finalcolor, 0.0, 1.0);
}

technique LinearMotionBlur
{
    pass PassBlurThatShit
    {
        VertexShader = PostProcessVS;
        PixelShader = BlurPS;
        
		#if SRGB_OUTPUT_COLOR
			SRGBWriteEnable = true;
		#endif
    }
}
