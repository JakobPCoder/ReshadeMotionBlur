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

#ifndef BUFFER_PIXEL_SIZE
    #define BUFFER_PIXEL_SIZE	ReShade::PixelSize
#endif


// UI
uniform bool UI_SHOW_CROSSHAIR <
    ui_tooltip = "Whether to show the crosshair for Camera Point";
    ui_label = "Camera Point Crosshair";
    ui_category = "Camera Point";
    ui_category_closed = true;
> = false;

uniform float UI_PIXEL_X < __UNIFORM_SLIDER_INT1
    ui_min = 1; ui_max = BUFFER_WIDTH; ui_step = 1;
    ui_tooltip = "The Camera Point position on the X plane (width)";
    ui_label = "Camera Point X-Position";
    ui_category = "Camera Point";
    ui_category_closed = true;
> = BUFFER_WIDTH / 2;

uniform float UI_PIXEL_Y < __UNIFORM_SLIDER_INT1
    ui_min = 1; ui_max = BUFFER_HEIGHT; ui_step = 1;
    ui_tooltip = "The Camera Point position on the Y plane (height)";
    ui_label = "Camera Point Y-Position";
    ui_category = "Camera Point";
    ui_category_closed = true;
> = BUFFER_HEIGHT / 2;

uniform float3 UI_CROSSHAIR_COLOR < __UNIFORM_COLOR_INT3
    ui_min = 0; ui_max = 255; ui_step = 1;
    ui_tooltip = "The color of the crosshair which shows the Camera Point";
    ui_label = "Crosshair Color";
    ui_category = "Camera Point";
    ui_category_closed = true;
> = 1;

uniform float UI_BLUR_LENGTH < __UNIFORM_SLIDER_FLOAT1
    ui_min = 0.01; ui_max = 1.0; ui_step = 0.01;
    ui_tooltip = "The amount of blur";
    ui_label = "Blur Length";
    ui_category = "Motion Blur";
> = 0.50;

uniform uint UI_BLUR_SAMPLES_MAX < __UNIFORM_SLIDER_INT1
    ui_min = 3; ui_max = 24; ui_step = 1;
    ui_tooltip = "The amount of samples gathered";
    ui_label = "Samples";
    ui_category = "Motion Blur";
> = 6;


//  Textures & Samplers
texture2D texColor : COLOR;
sampler samplerColor { Texture = texColor; AddressU = Clamp; AddressV = Clamp; MipFilter = Linear; MinFilter = Linear; MagFilter = Linear; };

texture texMotionVectors          { Width = BUFFER_WIDTH;   Height = BUFFER_HEIGHT;   Format = RG16F; };
sampler SamplerMotionVectors2 { Texture = texMotionVectors; AddressU = Clamp; AddressV = Clamp; MipFilter = Point; MinFilter = Point; MagFilter = Point; };


// Passes
float3 Crosshair(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float3 colorOrig = tex2D(ReShade::BackBuffer, texcoord).rgb;

    if (!UI_SHOW_CROSSHAIR) {
        return colorOrig;
    }

    float3 color = 0;
    float3 crosshair = UI_CROSSHAIR_COLOR;
    float2 pixelCoord = float2(UI_PIXEL_X, UI_PIXEL_Y) * BUFFER_PIXEL_SIZE;
    float mask;

    int Xtest = 0;
    int Ytest = 0;
    if (abs((texcoord.x / BUFFER_PIXEL_SIZE.x) - (pixelCoord.x / BUFFER_PIXEL_SIZE.x)) < 0.5) Xtest = 1;
    if (abs((texcoord.y / BUFFER_PIXEL_SIZE.y) - (pixelCoord.y / BUFFER_PIXEL_SIZE.y)) < 0.5) Ytest = 1;
    if (Xtest == 1 && Ytest == 1){ Xtest = 0; Ytest = 0;}
    color = lerp(color, crosshair, Xtest);
    color = lerp(color, crosshair, Ytest);

    if(UI_CROSSHAIR_COLOR.x >= UI_CROSSHAIR_COLOR.y && UI_CROSSHAIR_COLOR.x >= UI_CROSSHAIR_COLOR.z) mask = color.x;
    if(UI_CROSSHAIR_COLOR.y >= UI_CROSSHAIR_COLOR.x && UI_CROSSHAIR_COLOR.y >= UI_CROSSHAIR_COLOR.z) mask = color.y;
    if(UI_CROSSHAIR_COLOR.z >= UI_CROSSHAIR_COLOR.x && UI_CROSSHAIR_COLOR.z >= UI_CROSSHAIR_COLOR.y) mask = color.z;
    if(UI_CROSSHAIR_COLOR.x >= UI_CROSSHAIR_COLOR.y && UI_CROSSHAIR_COLOR.x <= UI_CROSSHAIR_COLOR.z) mask = color.z;
    if(UI_CROSSHAIR_COLOR.y >= UI_CROSSHAIR_COLOR.x && UI_CROSSHAIR_COLOR.y <= UI_CROSSHAIR_COLOR.z) mask = color.z;
    if(UI_CROSSHAIR_COLOR.z >= UI_CROSSHAIR_COLOR.x && UI_CROSSHAIR_COLOR.z <= UI_CROSSHAIR_COLOR.y) mask = color.y;
    color = lerp(colorOrig, color, mask);

    return color;
}

float4 BlurPS(float4 position : SV_Position, float2 texcoord : TEXCOORD ) : SV_Target
{
    float2 currCoord = position.xy;
    float2 cameraPointCoord = float2(UI_PIXEL_X, UI_PIXEL_Y);
    float l2 = length(currCoord - cameraPointCoord);
    float2 maxDist = max(float2(BUFFER_WIDTH, BUFFER_HEIGHT) - cameraPointCoord, cameraPointCoord);
    float l2Max = length(maxDist);

    float2 velocity = tex2D(SamplerMotionVectors2, texcoord).xy;
    float2 velocityTimed = velocity / frametime;
    float2 blurDist = velocityTimed * 50 * UI_BLUR_LENGTH * (l2 / l2Max);
    float2 sampleDist = blurDist / UI_BLUR_SAMPLES_MAX;
    int halfSamples = UI_BLUR_SAMPLES_MAX / 2;

    float4 summedSamples = 0.0;
    for(int s = 0; s < UI_BLUR_SAMPLES_MAX; s++)
        summedSamples += tex2D(samplerColor, texcoord - sampleDist * (s - halfSamples)) / UI_BLUR_SAMPLES_MAX;

    return summedSamples;
}

technique LinearMotionBlur
{
    pass {
        VertexShader = PostProcessVS;
        PixelShader = Crosshair;
    }
    pass {
        VertexShader = PostProcessVS;
        PixelShader = BlurPS;
    }
}
