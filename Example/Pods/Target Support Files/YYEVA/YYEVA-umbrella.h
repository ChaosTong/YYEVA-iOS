#ifdef __OBJC__
#import <UIKit/UIKit.h>
#else
#ifndef FOUNDATION_EXPORT
#if defined(__cplusplus)
#define FOUNDATION_EXPORT extern "C"
#else
#define FOUNDATION_EXPORT extern
#endif
#endif
#endif

#import "YYEVACommon.h"
#import "YYEVAPlayer.h"
#import "YYEVAAssets.h"
#import "YYEVAEffectInfo.h"
#import "IYYEVAVideoRenderProtol.h"
#import "YYEVAVideoAlphaRender.h"
#import "YYEVAVideoEffectRender.h"
#import "YYEVAVideoShareTypes.h"
#import "YSVideoMetalUtils.h"
#import "YYEVADemuxMedia.h"
#import "YYEVA.h"

FOUNDATION_EXPORT double YYEVAVersionNumber;
FOUNDATION_EXPORT const unsigned char YYEVAVersionString[];

