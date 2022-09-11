/** 
 * - Reshade Linear Motion Blur 
 * - First published 2022 - Copyright, Jakob Wapenhensch
 *
 * Linear Motion Blur is licensed under: Attribution-NonCommercial-NoDerivatives 4.0 International (CC BY-NC-ND 4.0)
 *
 * You are free to share, copy and redistribute the material in any medium or format.
 * The licensor cannot revoke those freedoms as long as you follow these license terms:
 *
 * - Attribution - 
 * You must give appropriate credit, provide a link to the license, and indicate if changes were made.
 * You may do so in any reasonable manner, but not in any way that suggests the licensor endorses you or your use.
 *
 * - Non Commercial - 
 * You may not use the material for commercial purposes.
 *
 * - No Derivatives - 
 * If you remix, transform, or build upon the material, you may not distribute the modified material.
 *
 * https://creativecommons.org/licenses/by-nc-nd/4.0/
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
	ui_min = 3; ui_max = 16; ui_step = 1;
	ui_tooltip = "";
	ui_label = "Samples";
	ui_category = "Motion Blur";
> = 5;

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
    for(int s = 0; s < UI_BLUR_SAMPLES_MAX; s++)
        summedSamples += tex2D(samplerColor, texcoord - sampleDist * (s - halfSamples)) / UI_BLUR_SAMPLES_MAX;

    return summedSamples;
}

technique LinearMotionBlur
{
    pass PassBlurThatShit
    {
        VertexShader = PostProcessVS;
        PixelShader = BlurPS;
    }
}