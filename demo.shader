// Built on top of the excellent CC0 godot shader by thepathgame here:  https://godotshaders.com/shader/crt-with-variable-fisheye/
// This file is similarly CC0 licensed - Enjoy!  :)  https://creativecommons.org/publicdomain/zero/1.0/

Shader "Custom/480pScanlineShader" {
    Properties
    {
        [PerRendererData] _MainTex ("Sprite Texture", 2D) = "white" {}
        [MaterialToggle] PixelSnap ("Pixel snap", Float) = 0
        _PreviousFrame ("Sprite Texture", 2D) = "black" {}
    }

    SubShader
    {
        Tags
        { 
            "Queue"="Transparent" 
            "IgnoreProjector"="True" 
            "RenderType"="Transparent" 
            "PreviewType"="Plane"
            "CanUseSpriteAtlas"="True"
        }

        Cull Off
        Lighting Off
        ZWrite Off
        Fog { Mode Off }
        Blend SrcAlpha OneMinusSrcAlpha

        Pass
        {
        CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag           
            #pragma multi_compile DUMMY PIXELSNAP_ON
            #include "UnityCG.cginc"

            struct appdata_t
            {
                float4 vertex   : POSITION;
                float4 color    : COLOR;
                float2 texcoord : TEXCOORD0;
            };

            struct v2f
            {
                float4 vertex   : SV_POSITION;
                fixed4 color    : COLOR;
                half2 texcoord  : TEXCOORD0;
            };

            sampler2D _MainTex;            
            sampler2D _PreviousFrame;  

            v2f vert(appdata_t IN)
            {
                v2f OUT;
                OUT.vertex = UnityObjectToClipPos(IN.vertex);
                OUT.texcoord = IN.texcoord;
                #ifdef PIXELSNAP_ON
                OUT.vertex = UnityPixelSnap (OUT.vertex);
                #endif

                return OUT;
            }

            fixed4 frag(v2f IN) : COLOR
            {
                float heightInPixels = _ScreenParams.y;
                float vUnitsPerPixel = (1 / heightInPixels);

                float widthInPixels = _ScreenParams.x;
                float uUnitsPerPixel = (1 / widthInPixels);

                float4 texColor = tex2D( _MainTex, IN.texcoord );
                float3 originalColor = tex2D( _MainTex, IN.texcoord );

                float3 outputColor;

                // Horizontal displacement of scanlines:

                // Displace scanlines slightly
                float maxOffsetForCrtWave = uUnitsPerPixel * 0.5;
	            
                // Wiggle the waves over time
                // Three sine waves of differing speeds multiplied with one another, instead of a single sine wave, to make a more complicated waveform
                // Using the Y coordinate as an input to the sine function so that the wave moves vertically over time
                float xOffsetForCrtWaves = sin(_Time.x * 0.3 + IN.texcoord.y * 21.0) * sin(_Time.y * 0.7 + IN.texcoord.y * 29.0) * sin(0.3 + _Time.x *  0.33 + IN.texcoord.y * 31.0) * maxOffsetForCrtWave;

                float displacedXCoordinate = IN.texcoord.x + xOffsetForCrtWaves;

                // Get the color of scanline-displaced pixel
                outputColor.r = tex2D(_MainTex, float2(displacedXCoordinate, IN.texcoord.y)).x;
                outputColor.g = tex2D(_MainTex, float2(displacedXCoordinate, IN.texcoord.y)).y;
                outputColor.b = tex2D(_MainTex, float2(displacedXCoordinate, IN.texcoord.y)).z;
                
                // We're doing a lot of color boosting later, and might accidentally start clipping, so lower everything down to make sure
                // that we have headroom to increase brightness and maintain detail
                outputColor *= 0.75;

                // Chromatic abberation:
                float chromaticAbberationOffset = uUnitsPerPixel * 2;

                // Red
                // Add a small amount of red that bleeds over from whatever pixel is diagonally up and to the right
                outputColor.r += 0.08 * tex2D(
                    _MainTex, 
                    0.75 * float2(xOffsetForCrtWaves + chromaticAbberationOffset, -chromaticAbberationOffset) + float2(IN.texcoord.x, IN.texcoord.y)
                ).x;

                //Cyan
                // Add a small amount of green that bleeds over from whatever pixel is diagonally up and to the left (this gets added to the b to make cyan)
                outputColor.g += 0.05 * tex2D(
                    _MainTex, 
                    0.75 * float2(xOffsetForCrtWaves - chromaticAbberationOffset, -chromaticAbberationOffset) + float2(IN.texcoord.x, IN.texcoord.y)
                ).y;
                // Add a small amount of blue that bleeds over from whatever pixel is diagonally up and to the left (this gets added to the g to make cyan)
                outputColor.b += 0.08 * tex2D(
                    _MainTex, 
                    0.75 * float2(xOffsetForCrtWaves - chromaticAbberationOffset, -chromaticAbberationOffset) + float2(IN.texcoord.x, IN.texcoord.y)
                ).z;

                // Imitate calibration errors leading to washout/oversaturation of bright colors by amplifying the output color slightly 
                // and taking a weighted average with the original output color
                outputColor = clamp(outputColor * 0.6 + 0.4 * outputColor * outputColor, 0.0, 1.0);

                // After all of the above math, we're about 1/3rd as bright as we should be (somehow)
	            outputColor *= 2.8;

                
                // Change brightness of individual scan lines, moving down over time
                float scanlinePulseWidthFactor = 3.5; // If this gets bigger, scan line pulses get wider.  If it gets smaller, they get thinner
                float scanlinePulseMovementSpeed = 1.5; // The speed at which lines move down the screen (in an arbitrary unit)
                float scanlinePulseMinBrightness = 0.45;
                float scanlinePulseMaxBrightnessIncrease = 0.55;

                // Scroll the bright lines vertically over time - By adding `Time` to the y coordinate being fed into the sine wave, the coordinate ranges which are brightened
                // change over time (due to `Time` constantly increasing in value).
                // If you remove the _Time.y portion of this, bands of brightness would be static based on y coordinate
	            float scanPulseBrightnessIncrease = clamp(
                       scanlinePulseMinBrightness + scanlinePulseMaxBrightnessIncrease * sin(scanlinePulseMovementSpeed * _Time.y + (IN.texcoord.y * heightInPixels) * (0.35 / scanlinePulseWidthFactor)), 
                       0.0, 
                       1.0
                   );

                // These exact values don't actually matter - I hardcoded in some values that looked nice
	            float scaledScanPulseBrightnessIncrease = pow(scanPulseBrightnessIncrease, 1.7) * 0.4;
	            outputColor = outputColor * (0.4 + 0.7 * scaledScanPulseBrightnessIncrease);

                // Also just pulse the entire screen slowly 
                // (use multiple sine waves stacked together so that the pulse is not a uniform rhythm, but a polyrythm of these sin waves)
                float pulseAmount = 0.2;
                float pulseSpeed = 2;
                outputColor *= 1.0 + pulseAmount * clamp(clamp(sin(pulseSpeed * 1 * _Time.y), 0.1, 1) * clamp(sin(pulseSpeed * 0.27 * _Time.y), 0.1, 1) * clamp(sin(pulseSpeed * 1.32 * _Time.y), 0.1, 1), 0, 1);

                // Re-up the color to what it used to be after we're finished doing our manipulations 
                // (remember, we lowered it intentionally at the start of all of this, in order to avoid clipping)
                outputColor *= 1.24;

                // Not sure how this would be possible, but if we're outside of the 0-1 UV space, render black.  Just in case.
	            if (IN.texcoord.x < 0.0 || IN.texcoord.x > 1.0)
		            outputColor *= 0.0;
	            if (IN.texcoord.y < 0.0 || IN.texcoord.y > 1.0)
		            outputColor *= 0.0;


                // Render scanlines between pixels
                float pixelsBetweenScanlines = 1;
                float scanlineWidth = vUnitsPerPixel / 2;
                float scanlineOffsetInVUnits = vUnitsPerPixel / 3;
                float scanlineBrightness = 0.4;

                // fmod is just shader language for the modulo operator (%) - Takes the remainder of the first param divided by the second param
                // Basically what we're doing here is checking for bands of Y coordinates that are within a scanline
                // and then lowering their brightness
                outputColor = fmod(IN.texcoord.y + scanlineOffsetInVUnits, pixelsBetweenScanlines * vUnitsPerPixel) <= scanlineWidth ? outputColor * scanlineBrightness : outputColor;

                return float4(outputColor.x, outputColor.y, outputColor.z, 1.0);
            }

        ENDCG
        }
    }
}