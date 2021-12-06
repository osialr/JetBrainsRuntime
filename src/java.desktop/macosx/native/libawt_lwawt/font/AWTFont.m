/*
 * Copyright (c) 2011, 2013, Oracle and/or its affiliates. All rights reserved.
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
 *
 * This code is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 only, as
 * published by the Free Software Foundation.  Oracle designates this
 * particular file as subject to the "Classpath" exception as provided
 * by Oracle in the LICENSE file that accompanied this code.
 *
 * This code is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * version 2 for more details (a copy is included in the LICENSE file that
 * accompanied this code).
 *
 * You should have received a copy of the GNU General Public License version
 * 2 along with this work; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * Please contact Oracle, 500 Oracle Parkway, Redwood Shores, CA 94065 USA
 * or visit www.oracle.com if you need additional information or have any
 * questions.
 */

#import "java_awt_Font.h"
#import "sun_awt_PlatformFont.h"
#import "sun_awt_FontDescriptor.h"
#import "sun_font_CFont.h"
#import "sun_font_CFontManager.h"

#import "AWTFont.h"
#import "AWTStrike.h"
#import "CoreTextSupport.h"
#import "JNIUtilities.h"

@implementation AWTFont

- (id) initWithFont:(NSFont *)font fallbackBase:(NSFont *)fallbackBaseFont {
    self = [super init];
    if (self) {
        fFont = [font retain];
        fNativeCGFont = CTFontCopyGraphicsFont((CTFontRef)font, NULL);
        fFallbackBase = [fallbackBaseFont retain];
    }
    return self;
}

- (void) dealloc {
    [fFallbackBase release];
    fFallbackBase = nil;

    [fFont release];
    fFont = nil;

    if (fNativeCGFont) {
        CGFontRelease(fNativeCGFont);
    fNativeCGFont = NULL;
    }

    [super dealloc];
}

- (void) finalize {
    if (fNativeCGFont) {
        CGFontRelease(fNativeCGFont);
    fNativeCGFont = NULL;
    }
    [super finalize];
}

static NSString* uiName = nil;
static NSString* uiBoldName = nil;

+ (AWTFont *) awtFontForName:(NSString *)name
                       style:(int)style
{
    // create font with family & size
    NSFont *nsFont = nil;
    NSFont *nsFallbackBase = nil;

    if ((uiName != nil && [name isEqualTo:uiName]) ||
        (uiBoldName != nil && [name isEqualTo:uiBoldName])) {
        if (style & java_awt_Font_BOLD) {
            nsFont = [NSFont boldSystemFontOfSize:1.0];
            nsFallbackBase = [NSFont fontWithName:@"LucidaGrande-Bold" size:1.0];
        } else {
            nsFont = [NSFont systemFontOfSize:1.0];
            nsFallbackBase = [NSFont fontWithName:@"LucidaGrande" size:1.0];
        }
#ifdef DEBUG
        NSLog(@"nsFont-name is : %@", nsFont.familyName);
        NSLog(@"nsFont-family is : %@", nsFont.fontName);
        NSLog(@"nsFont-desc-name is : %@", nsFont.fontDescriptor.postscriptName);
#endif


    } else {
           nsFont = [NSFont fontWithName:name size:1.0];
    }

    if (nsFont == nil) {
        // if can't get font of that name, substitute system default font
        nsFont = [NSFont fontWithName:@"Lucida Grande" size:1.0];
#ifdef DEBUG
        NSLog(@"needed to substitute Lucida Grande for: %@", name);
#endif
    }

    // create an italic style (if one is installed)
    if (style & java_awt_Font_ITALIC) {
        nsFont = [[NSFontManager sharedFontManager] convertFont:nsFont toHaveTrait:NSItalicFontMask];
    }

    // create a bold style (if one is installed)
    if (style & java_awt_Font_BOLD) {
        nsFont = [[NSFontManager sharedFontManager] convertFont:nsFont toHaveTrait:NSBoldFontMask];
    }

    return [[[AWTFont alloc] initWithFont:nsFont fallbackBase:nsFallbackBase] autorelease];
}

+ (NSFont *) nsFontForJavaFont:(jobject)javaFont env:(JNIEnv *)env {
    if (javaFont == NULL) {
#ifdef DEBUG
        NSLog(@"nil font");
#endif
        return nil;
    }

    DECLARE_CLASS_RETURN(jc_Font, "java/awt/Font", nil);

    // obtain the Font2D
    DECLARE_METHOD_RETURN(jm_Font_getFont2D, jc_Font, "getFont2D", "()Lsun/font/Font2D;", nil);
    jobject font2d = (*env)->CallObjectMethod(env, javaFont, jm_Font_getFont2D);
    CHECK_EXCEPTION();
    if (font2d == NULL) {
#ifdef DEBUG
        NSLog(@"nil font2d");
#endif
        return nil;
    }

    // if it's not a CFont, it's likely one of TTF or OTF fonts
    // from the Sun rendering loops
    DECLARE_CLASS_RETURN(jc_CFont, "sun/font/CFont", nil);
    if (!(*env)->IsInstanceOf(env, font2d, jc_CFont)) {
#ifdef DEBUG
        NSLog(@"font2d !instanceof CFont");
#endif
        return nil;
    }

    DECLARE_METHOD_RETURN(jm_CFont_getFontStrike, jc_CFont, "getStrike", "(Ljava/awt/Font;)Lsun/font/FontStrike;", nil);
    jobject fontStrike = (*env)->CallObjectMethod(env, font2d, jm_CFont_getFontStrike, javaFont);
    CHECK_EXCEPTION();
    DECLARE_CLASS_RETURN(jc_CStrike, "sun/font/CStrike", nil);
    if (!(*env)->IsInstanceOf(env, fontStrike, jc_CStrike)) {
#ifdef DEBUG
        NSLog(@"fontStrike !instanceof CStrike");
#endif
        return nil;
    }

    DECLARE_METHOD_RETURN(jm_CStrike_nativeStrikePtr, jc_CStrike, "getNativeStrikePtr", "()J", nil);
    jlong awtStrikePtr = (*env)->CallLongMethod(env, fontStrike, jm_CStrike_nativeStrikePtr);
    CHECK_EXCEPTION();
    if (awtStrikePtr == 0L) {
#ifdef DEBUG
        NSLog(@"nil nativeFontPtr from CFont");
#endif
        return nil;
    }

    AWTStrike *strike = (AWTStrike *)jlong_to_ptr(awtStrikePtr);

    return [NSFont fontWithName:[strike->fAWTFont->fFont fontName] matrix:(CGFloat *)(&(strike->fAltTx))];
}

@end


#pragma mark --- Font Discovery and Loading ---

static NSArray* sFilteredFonts = nil;
static NSDictionary* sFontFamilyTable = nil;
static NSDictionary* sFontFaceTable = nil;

static NSString*
GetFamilyNameForFontName(NSString* fontname)
{
    return [sFontFamilyTable objectForKey:fontname];
}

static NSString*
GetFaceForFontName(NSString* fontname)
{
    return [sFontFaceTable objectForKey:fontname];
}

static void addFont(CTFontUIFontType uiType,
                    NSMutableArray *allFonts,
                    NSMutableDictionary* fontFamilyTable,
                    NSMutableDictionary* fontFacesTable) {

        CTFontRef font = CTFontCreateUIFontForLanguage(uiType, 0.0, NULL);
        if (font == NULL) {
            return;
        }
        CTFontDescriptorRef desc = CTFontCopyFontDescriptor(font);
        if (desc == NULL) {
            CFRelease(font);
            return;
        }
        CFStringRef family = CTFontDescriptorCopyAttribute(desc, kCTFontFamilyNameAttribute);
        if (family == NULL) {
            CFRelease(desc);
            CFRelease(font);
            return;
        }
        CFStringRef name = CTFontDescriptorCopyAttribute(desc, kCTFontNameAttribute);
        if (name == NULL) {
            CFRelease(family);
            CFRelease(desc);
            CFRelease(font);
            return;
        }
        CFStringRef face = CTFontDescriptorCopyAttribute(desc, kCTFontStyleNameAttribute);
        if (uiType == kCTFontUIFontSystem) {
            uiName = (NSString*)name;
        }
        if (uiType == kCTFontUIFontEmphasizedSystem) {
            uiBoldName = (NSString*)name;
        }
        [allFonts addObject:name];
        [fontFamilyTable setObject:family forKey:name];
        if (face) {
            [fontFacesTable setObject:face forKey:name];
        }
#ifdef DEBUG
        NSLog(@"name is : %@", (NSString*)name);
        NSLog(@"family is : %@", (NSString*)family);
        NSLog(@"face is : %@", (NSString*)face);
#endif
        if (face) {
            CFRelease(face);
        }
        CFRelease(family);
        CFRelease(name);
        CFRelease(desc);
        CFRelease(font);
}

static NSDictionary* prebuiltFamilyNames() {
    return @{
             @"..SFCompactDisplay-Regular" : @".SF Compact Display",
             @"..SFCompactRounded-Regular" : @".SF Compact Rounded",
             @"..SFCompactText-Italic" : @".SF Compact Text",
             @"..SFCompactText-Regular" : @".SF Compact Text",
             @".AlBayanPUA" : @".Al Bayan PUA",
             @".AlBayanPUA-Bold" : @".Al Bayan PUA",
             @".AlNilePUA" : @".Al Nile PUA",
             @".AlNilePUA-Bold" : @".Al Nile PUA",
             @".AlTarikhPUA" : @".Al Tarikh PUA",
             @".AppleColorEmojiUI" : @".Apple Color Emoji UI",
             @".AppleSDGothicNeoI-Bold" : @".Apple SD Gothic NeoI",
             @".AppleSDGothicNeoI-ExtraBold" : @".Apple SD Gothic NeoI",
             @".AppleSDGothicNeoI-Heavy" : @".Apple SD Gothic NeoI",
             @".AppleSDGothicNeoI-Light" : @".Apple SD Gothic NeoI",
             @".AppleSDGothicNeoI-Medium" : @".Apple SD Gothic NeoI",
             @".AppleSDGothicNeoI-Regular" : @".Apple SD Gothic NeoI",
             @".AppleSDGothicNeoI-SemiBold" : @".Apple SD Gothic NeoI",
             @".AppleSDGothicNeoI-Thin" : @".Apple SD Gothic NeoI",
             @".AppleSDGothicNeoI-UltraLight" : @".Apple SD Gothic NeoI",
             @".ArabicUIDisplay-Black" : @".Arabic UI Display",
             @".ArabicUIDisplay-Bold" : @".Arabic UI Display",
             @".ArabicUIDisplay-Heavy" : @".Arabic UI Display",
             @".ArabicUIDisplay-Light" : @".Arabic UI Display",
             @".ArabicUIDisplay-Medium" : @".Arabic UI Display",
             @".ArabicUIDisplay-Regular" : @".Arabic UI Display",
             @".ArabicUIDisplay-Semibold" : @".Arabic UI Display",
             @".ArabicUIDisplay-Thin" : @".Arabic UI Display",
             @".ArabicUIDisplay-Ultralight" : @".Arabic UI Display",
             @".ArabicUIText-Bold" : @".Arabic UI Text",
             @".ArabicUIText-Heavy" : @".Arabic UI Text",
             @".ArabicUIText-Light" : @".Arabic UI Text",
             @".ArabicUIText-Medium" : @".Arabic UI Text",
             @".ArabicUIText-Regular" : @".Arabic UI Text",
             @".ArabicUIText-Semibold" : @".Arabic UI Text",
             @".ArialHebrewDeskInterface" : @".Arial Hebrew Desk Interface",
             @".ArialHebrewDeskInterface-Bold" : @".Arial Hebrew Desk Interface",
             @".ArialHebrewDeskInterface-Light" : @".Arial Hebrew Desk Interface",
             @".BaghdadPUA" : @".Baghdad PUA",
             @".BeirutPUA" : @".Beirut PUA",
             @".DamascusPUA" : @".Damascus PUA",
             @".DamascusPUABold" : @".Damascus PUA",
             @".DamascusPUALight" : @".Damascus PUA",
             @".DamascusPUAMedium" : @".Damascus PUA",
             @".DamascusPUASemiBold" : @".Damascus PUA",
             @".DecoTypeNaskhPUA" : @".DecoType Naskh PUA",
             @".DiwanKufiPUA" : @".Diwan Kufi PUA",
             @".FarahPUA" : @".Farah PUA",
             @".GeezaProInterface" : @".Geeza Pro Interface",
             @".GeezaProInterface-Bold" : @".Geeza Pro Interface",
             @".GeezaProInterface-Light" : @".Geeza Pro Interface",
             @".GeezaProPUA" : @".Geeza Pro PUA",
             @".GeezaProPUA-Bold" : @".Geeza Pro PUA",
             @".HelveticaNeueDeskInterface-Bold" : @".Helvetica Neue DeskInterface",
             @".HelveticaNeueDeskInterface-BoldItalic" : @".Helvetica Neue DeskInterface",
             @".HelveticaNeueDeskInterface-Heavy" : @".Helvetica Neue DeskInterface",
             @".HelveticaNeueDeskInterface-Italic" : @".Helvetica Neue DeskInterface",
             @".HelveticaNeueDeskInterface-Light" : @".Helvetica Neue DeskInterface",
             @".HelveticaNeueDeskInterface-MediumItalicP4" : @".Helvetica Neue DeskInterface",
             @".HelveticaNeueDeskInterface-MediumP4" : @".Helvetica Neue DeskInterface",
             @".HelveticaNeueDeskInterface-Regular" : @".Helvetica Neue DeskInterface",
             @".HelveticaNeueDeskInterface-Thin" : @".Helvetica Neue DeskInterface",
             @".HelveticaNeueDeskInterface-UltraLightP2" : @".Helvetica Neue DeskInterface",
             @".HiraKakuInterface-W0" : @".Hiragino Kaku Gothic Interface",
             @".HiraKakuInterface-W1" : @".Hiragino Kaku Gothic Interface",
             @".HiraKakuInterface-W2" : @".Hiragino Kaku Gothic Interface",
             @".HiraKakuInterface-W3" : @".Hiragino Kaku Gothic Interface",
             @".HiraKakuInterface-W4" : @".Hiragino Kaku Gothic Interface",
             @".HiraKakuInterface-W5" : @".Hiragino Kaku Gothic Interface",
             @".HiraKakuInterface-W6" : @".Hiragino Kaku Gothic Interface",
             @".HiraKakuInterface-W7" : @".Hiragino Kaku Gothic Interface",
             @".HiraKakuInterface-W8" : @".Hiragino Kaku Gothic Interface",
             @".HiraKakuInterface-W9" : @".Hiragino Kaku Gothic Interface",
             @".HiraginoSansGBInterface-W3" : @".Hiragino Sans GB Interface",
             @".HiraginoSansGBInterface-W6" : @".Hiragino Sans GB Interface",
             @".Keyboard" : @".Keyboard",
             @".KufiStandardGKPUA" : @".KufiStandardGK PUA",
             @".LucidaGrandeUI" : @".Lucida Grande UI",
             @".LucidaGrandeUI-Bold" : @".Lucida Grande UI",
             @".MunaPUA" : @".Muna PUA",
             @".MunaPUABlack" : @".Muna PUA",
             @".MunaPUABold" : @".Muna PUA",
             @".NadeemPUA" : @".Nadeem PUA",
             @".NewYork-Black" : @".New York",
             @".NewYork-BlackItalic" : @".New York",
             @".NewYork-Bold" : @".New York",
             @".NewYork-BoldItalic" : @".New York",
             @".NewYork-Heavy" : @".New York",
             @".NewYork-HeavyItalic" : @".New York",
             @".NewYork-Medium" : @".New York",
             @".NewYork-MediumItalic" : @".New York",
             @".NewYork-Regular" : @".New York",
             @".NewYork-RegularItalic" : @".New York",
             @".NewYork-Semibold" : @".New York",
             @".NewYork-SemiboldItalic" : @".New York",
             @".NotoNastaliqUrduUI" : @".Noto Nastaliq Urdu UI",
             @".NotoNastaliqUrduUI-Bold" : @".Noto Nastaliq Urdu UI",
             @".PingFangHK-Light" : @".PingFang HK",
             @".PingFangHK-Medium" : @".PingFang HK",
             @".PingFangHK-Regular" : @".PingFang HK",
             @".PingFangHK-Semibold" : @".PingFang HK",
             @".PingFangHK-Thin" : @".PingFang HK",
             @".PingFangHK-Ultralight" : @".PingFang HK",
             @".PingFangSC-Light" : @".PingFang SC",
             @".PingFangSC-Medium" : @".PingFang SC",
             @".PingFangSC-Regular" : @".PingFang SC",
             @".PingFangSC-Semibold" : @".PingFang SC",
             @".PingFangSC-Thin" : @".PingFang SC",
             @".PingFangSC-Ultralight" : @".PingFang SC",
             @".PingFangTC-Light" : @".PingFang TC",
             @".PingFangTC-Medium" : @".PingFang TC",
             @".PingFangTC-Regular" : @".PingFang TC",
             @".PingFangTC-Semibold" : @".PingFang TC",
             @".PingFangTC-Thin" : @".PingFang TC",
             @".PingFangTC-Ultralight" : @".PingFang TC",
             @".SFCompactDisplay-Black" : @".SF Compact Display",
             @".SFCompactDisplay-Bold" : @".SF Compact Display",
             @".SFCompactDisplay-Heavy" : @".SF Compact Display",
             @".SFCompactDisplay-Light" : @".SF Compact Display",
             @".SFCompactDisplay-Medium" : @".SF Compact Display",
             @".SFCompactDisplay-Regular" : @".SF Compact Display",
             @".SFCompactDisplay-Semibold" : @".SF Compact Display",
             @".SFCompactDisplay-Thin" : @".SF Compact Display",
             @".SFCompactDisplay-Ultralight" : @".SF Compact Display",
             @".SFCompactRounded-Black" : @".SF Compact Rounded",
             @".SFCompactRounded-Bold" : @".SF Compact Rounded",
             @".SFCompactRounded-Heavy" : @".SF Compact Rounded",
             @".SFCompactRounded-Light" : @".SF Compact Rounded",
             @".SFCompactRounded-Medium" : @".SF Compact Rounded",
             @".SFCompactRounded-Regular" : @".SF Compact Rounded",
             @".SFCompactRounded-Semibold" : @".SF Compact Rounded",
             @".SFCompactRounded-Thin" : @".SF Compact Rounded",
             @".SFCompactRounded-Ultralight" : @".SF Compact Rounded",
             @".SFCompactText-Bold" : @".SF Compact Text",
             @".SFCompactText-BoldG1" : @".SF Compact Text",
             @".SFCompactText-BoldG2" : @".SF Compact Text",
             @".SFCompactText-BoldG3" : @".SF Compact Text",
             @".SFCompactText-BoldItalic" : @".SF Compact Text",
             @".SFCompactText-BoldItalicG1" : @".SF Compact Text",
             @".SFCompactText-BoldItalicG2" : @".SF Compact Text",
             @".SFCompactText-BoldItalicG3" : @".SF Compact Text",
             @".SFCompactText-Heavy" : @".SF Compact Text",
             @".SFCompactText-HeavyItalic" : @".SF Compact Text",
             @".SFCompactText-Italic" : @".SF Compact Text",
             @".SFCompactText-Light" : @".SF Compact Text",
             @".SFCompactText-LightItalic" : @".SF Compact Text",
             @".SFCompactText-Medium" : @".SF Compact Text",
             @".SFCompactText-MediumItalic" : @".SF Compact Text",
             @".SFCompactText-Regular" : @".SF Compact Text",
             @".SFCompactText-RegularG1" : @".SF Compact Text",
             @".SFCompactText-RegularG2" : @".SF Compact Text",
             @".SFCompactText-RegularG3" : @".SF Compact Text",
             @".SFCompactText-RegularItalic" : @".SF Compact Text",
             @".SFCompactText-RegularItalicG1" : @".SF Compact Text",
             @".SFCompactText-RegularItalicG2" : @".SF Compact Text",
             @".SFCompactText-RegularItalicG3" : @".SF Compact Text",
             @".SFCompactText-Semibold" : @".SF Compact Text",
             @".SFCompactText-SemiboldItalic" : @".SF Compact Text",
             @".SFCompactText-Thin" : @".SF Compact Text",
             @".SFCompactText-ThinItalic" : @".SF Compact Text",
             @".SFCompactText-Ultralight" : @".SF Compact Text",
             @".SFCompactText-UltralightItalic" : @".SF Compact Text",
             @".SFNSDisplay" : @".SF NS Display",
             @".SFNSDisplay-Black" : @".SF NS Display",
             @".SFNSDisplay-BlackItalic" : @".SF NS Display",
             @".SFNSDisplay-Bold" : @".SF NS Display",
             @".SFNSDisplay-BoldItalic" : @".SF NS Display",
             @".SFNSDisplay-Heavy" : @".SF NS Display",
             @".SFNSDisplay-HeavyItalic" : @".SF NS Display",
             @".SFNSDisplay-Italic" : @".SF NS Display",
             @".SFNSDisplay-Light" : @".SF NS Display",
             @".SFNSDisplay-LightItalic" : @".SF NS Display",
             @".SFNSDisplay-Medium" : @".SF NS Display",
             @".SFNSDisplay-MediumItalic" : @".SF NS Display",
             @".SFNSDisplay-Semibold" : @".SF NS Display",
             @".SFNSDisplay-SemiboldItalic" : @".SF NS Display",
             @".SFNSDisplay-Thin" : @".SF NS Display",
             @".SFNSDisplay-ThinG1" : @".SF NS Display",
             @".SFNSDisplay-ThinG2" : @".SF NS Display",
             @".SFNSDisplay-ThinG3" : @".SF NS Display",
             @".SFNSDisplay-ThinG4" : @".SF NS Display",
             @".SFNSDisplay-ThinItalic" : @".SF NS Display",
             @".SFNSDisplay-Ultralight" : @".SF NS Display",
             @".SFNSDisplay-UltralightItalic" : @".SF NS Display",

             @".SFNS-Black" : @".SF NS",
             @".SFNS-BlackItalic" : @".SF NS",
             @".SFNS-Bold" : @".SF NS",
             @".SFNS-BoldG1" : @".SF NS",
             @".SFNS-BoldG2" : @".SF NS",
             @".SFNS-BoldG3" : @".SF NS",
             @".SFNS-BoldG4" : @".SF NS",
             @".SFNS-BoldItalic" : @".SF NS",
             @".SFNS-Heavy" : @".SF NS",
             @".SFNS-HeavyG1" : @".SF NS",
             @".SFNS-HeavyG2" : @".SF NS",
             @".SFNS-HeavyG3" : @".SF NS",
             @".SFNS-HeavyG4" : @".SF NS",
             @".SFNS-HeavyItalic" : @".SF NS",
             @".SFNS-Light" : @".SF NS",
             @".SFNS-LightG1" : @".SF NS",
             @".SFNS-LightG2" : @".SF NS",
             @".SFNS-LightG3" : @".SF NS",
             @".SFNS-LightG4" : @".SF NS",
             @".SFNS-LightItalic" : @".SF NS",
             @".SFNS-Medium" : @".SF NS",
             @".SFNS-MediumG1" : @".SF NS",
             @".SFNS-MediumG2" : @".SF NS",
             @".SFNS-MediumG3" : @".SF NS",
             @".SFNS-MediumG4" : @".SF NS",
             @".SFNS-MediumItalic" : @".SF NS",
             @".SFNS-Regular" : @".SF NS",
             @".SFNS-RegularG1" : @".SF NS",
             @".SFNS-RegularG2" : @".SF NS",
             @".SFNS-RegularG3" : @".SF NS",
             @".SFNS-RegularG4" : @".SF NS",
             @".SFNS-RegularItalic" : @".SF NS",
             @".SFNS-Semibold" : @".SF NS",
             @".SFNS-SemiboldG1" : @".SF NS",
             @".SFNS-SemiboldG2" : @".SF NS",
             @".SFNS-SemiboldG3" : @".SF NS",
             @".SFNS-SemiboldG4" : @".SF NS",
             @".SFNS-SemiboldItalic" : @".SF NS",
             @".SFNS-Thin" : @".SF NS",
             @".SFNS-ThinG1" : @".SF NS",
             @".SFNS-ThinG2" : @".SF NS",
             @".SFNS-ThinG3" : @".SF NS",
             @".SFNS-ThinG4" : @".SF NS",
             @".SFNS-ThinItalic" : @".SF NS",
             @".SFNS-Ultralight" : @".SF NS",
             @".SFNS-UltralightG1" : @".SF NS",
             @".SFNS-UltralightG2" : @".SF NS",
             @".SFNS-UltralightG3" : @".SF NS",
             @".SFNS-UltralightG4" : @".SF NS",
             @".SFNS-UltralightItalic" : @".SF NS",
             @".SFNS-Ultrathin" : @".SF NS",
             @".SFNS-UltrathinG1" : @".SF NS",
             @".SFNS-UltrathinG2" : @".SF NS",
             @".SFNS-UltrathinG3" : @".SF NS",
             @".SFNS-UltrathinG4" : @".SF NS",
             @".SFNS-UltrathinItalic" : @".SF NS",
             @".SFNSDisplayCondensed-Black" : @".SF NS Display Condensed",
             @".SFNSDisplayCondensed-Bold" : @".SF NS Display Condensed",
             @".SFNSDisplayCondensed-Heavy" : @".SF NS Display Condensed",
             @".SFNSDisplayCondensed-Light" : @".SF NS Display Condensed",
             @".SFNSDisplayCondensed-Medium" : @".SF NS Display Condensed",
             @".SFNSDisplayCondensed-Regular" : @".SF NS Display Condensed",
             @".SFNSDisplayCondensed-Semibold" : @".SF NS Display Condensed",
             @".SFNSDisplayCondensed-Thin" : @".SF NS Display Condensed",
             @".SFNSDisplayCondensed-Ultralight" : @".SF NS Display Condensed",
             @".SFNSMono-Bold" : @".SF NS Mono",
             @".SFNSMono-BoldItalic" : @".SF NS Mono",
             @".SFNSMono-Heavy" : @".SF NS Mono",
             @".SFNSMono-HeavyItalic" : @".SF NS Mono",
             @".SFNSMono-Light" : @".SF NS Mono",
             @".SFNSMono-LightItalic" : @".SF NS Mono",
             @".SFNSMono-Medium" : @".SF NS Mono",
             @".SFNSMono-MediumItalic" : @".SF NS Mono",
             @".SFNSMono-Regular" : @".SF NS Mono",
             @".SFNSMono-RegularItalic" : @".SF NS Mono",
             @".SFNSMono-Semibold" : @".SF NS Mono",
             @".SFNSMono-SemiboldItalic" : @".SF NS Mono",
             @".SFNSRounded-Black" : @".SF NS Rounded",
             @".SFNSRounded-Bold" : @".SF NS Rounded",
             @".SFNSRounded-BoldG1" : @".SF NS Rounded",
             @".SFNSRounded-BoldG2" : @".SF NS Rounded",
             @".SFNSRounded-BoldG3" : @".SF NS Rounded",
             @".SFNSRounded-BoldG4" : @".SF NS Rounded",
             @".SFNSRounded-Heavy" : @".SF NS Rounded",
             @".SFNSRounded-HeavyG1" : @".SF NS Rounded",
             @".SFNSRounded-HeavyG2" : @".SF NS Rounded",
             @".SFNSRounded-HeavyG3" : @".SF NS Rounded",
             @".SFNSRounded-HeavyG4" : @".SF NS Rounded",
             @".SFNSRounded-Light" : @".SF NS Rounded",
             @".SFNSRounded-LightG1" : @".SF NS Rounded",
             @".SFNSRounded-LightG2" : @".SF NS Rounded",
             @".SFNSRounded-LightG3" : @".SF NS Rounded",
             @".SFNSRounded-LightG4" : @".SF NS Rounded",
             @".SFNSRounded-Medium" : @".SF NS Rounded",
             @".SFNSRounded-MediumG1" : @".SF NS Rounded",
             @".SFNSRounded-MediumG2" : @".SF NS Rounded",
             @".SFNSRounded-MediumG3" : @".SF NS Rounded",
             @".SFNSRounded-MediumG4" : @".SF NS Rounded",
             @".SFNSRounded-Regular" : @".SF NS Rounded",
             @".SFNSRounded-RegularG1" : @".SF NS Rounded",
             @".SFNSRounded-RegularG2" : @".SF NS Rounded",
             @".SFNSRounded-RegularG3" : @".SF NS Rounded",
             @".SFNSRounded-RegularG4" : @".SF NS Rounded",
             @".SFNSRounded-Semibold" : @".SF NS Rounded",
             @".SFNSRounded-SemiboldG1" : @".SF NS Rounded",
             @".SFNSRounded-SemiboldG2" : @".SF NS Rounded",
             @".SFNSRounded-SemiboldG3" : @".SF NS Rounded",
             @".SFNSRounded-SemiboldG4" : @".SF NS Rounded",
             @".SFNSRounded-Thin" : @".SF NS Rounded",
             @".SFNSRounded-ThinG1" : @".SF NS Rounded",
             @".SFNSRounded-ThinG2" : @".SF NS Rounded",
             @".SFNSRounded-ThinG3" : @".SF NS Rounded",
             @".SFNSRounded-ThinG4" : @".SF NS Rounded",
             @".SFNSRounded-Ultralight" : @".SF NS Rounded",
             @".SFNSRounded-UltralightG1" : @".SF NS Rounded",
             @".SFNSRounded-UltralightG2" : @".SF NS Rounded",
             @".SFNSRounded-UltralightG3" : @".SF NS Rounded",
             @".SFNSRounded-UltralightG4" : @".SF NS Rounded",
             @".SFNSRounded-Ultrathin" : @".SF NS Rounded",
             @".SFNSRounded-UltrathinG1" : @".SF NS Rounded",
             @".SFNSRounded-UltrathinG2" : @".SF NS Rounded",
             @".SFNSRounded-UltrathinG3" : @".SF NS Rounded",
             @".SFNSRounded-UltrathinG4" : @".SF NS Rounded",
             @".SFNSSymbols-Black" : @".SF NS Symbols",
             @".SFNSSymbols-Bold" : @".SF NS Symbols",
             @".SFNSSymbols-Heavy" : @".SF NS Symbols",
             @".SFNSSymbols-Light" : @".SF NS Symbols",
             @".SFNSSymbols-Medium" : @".SF NS Symbols",
             @".SFNSSymbols-Regular" : @".SF NS Symbols",
             @".SFNSSymbols-Semibold" : @".SF NS Symbols",
             @".SFNSSymbols-Thin" : @".SF NS Symbols",
             @".SFNSSymbols-Ultralight" : @".SF NS Symbols",
             @".SFNSText" : @".SF NS Text",
             @".SFNSText-Bold" : @".SF NS Text",
             @".SFNSText-BoldItalic" : @".SF NS Text",
             @".SFNSText-Heavy" : @".SF NS Text",
             @".SFNSText-HeavyItalic" : @".SF NS Text",
             @".SFNSText-Italic" : @".SF NS Text",
             @".SFNSText-Light" : @".SF NS Text",
             @".SFNSText-LightItalic" : @".SF NS Text",
             @".SFNSText-Medium" : @".SF NS Text",
             @".SFNSText-MediumItalic" : @".SF NS Text",
             @".SFNSText-Semibold" : @".SF NS Text",
             @".SFNSText-SemiboldItalic" : @".SF NS Text",
             @".SFNSTextCondensed-Bold" : @".SF NS Text Condensed",
             @".SFNSTextCondensed-Heavy" : @".SF NS Text Condensed",
             @".SFNSTextCondensed-Light" : @".SF NS Text Condensed",
             @".SFNSTextCondensed-Medium" : @".SF NS Text Condensed",
             @".SFNSTextCondensed-Regular" : @".SF NS Text Condensed",
             @".SFNSTextCondensed-Semibold" : @".SF NS Text Condensed",
             @".SFCompact-Black" : @".SFCompact",
             @".SFCompact-BlackItalic" : @".SFCompact",
             @".SFCompact-Bold" : @".SFCompact",
             @".SFCompact-BoldG1" : @".SFCompact",
             @".SFCompact-BoldG2" : @".SFCompact",
             @".SFCompact-BoldG3" : @".SFCompact",
             @".SFCompact-BoldG4" : @".SFCompact",
             @".SFCompact-BoldItalic" : @".SFCompact",
             @".SFCompact-BoldItalicG1" : @".SFCompact",
             @".SFCompact-BoldItalicG2" : @".SFCompact",
             @".SFCompact-BoldItalicG3" : @".SFCompact",
             @".SFCompact-BoldItalicG4" : @".SFCompact",
             @".SFCompact-Heavy" : @".SFCompact",
             @".SFCompact-HeavyG1" : @".SFCompact",
             @".SFCompact-HeavyG2" : @".SFCompact",
             @".SFCompact-HeavyG3" : @".SFCompact",
             @".SFCompact-HeavyG4" : @".SFCompact",
             @".SFCompact-HeavyItalic" : @".SFCompact",
             @".SFCompact-HeavyItalicG1" : @".SFCompact",
             @".SFCompact-HeavyItalicG2" : @".SFCompact",
             @".SFCompact-HeavyItalicG3" : @".SFCompact",
             @".SFCompact-HeavyItalicG4" : @".SFCompact",
             @".SFCompact-Light" : @".SFCompact",
             @".SFCompact-LightG1" : @".SFCompact",
             @".SFCompact-LightG2" : @".SFCompact",
             @".SFCompact-LightG3" : @".SFCompact",
             @".SFCompact-LightG4" : @".SFCompact",
             @".SFCompact-LightItalic" : @".SFCompact",
             @".SFCompact-LightItalicG1" : @".SFCompact",
             @".SFCompact-LightItalicG2" : @".SFCompact",
             @".SFCompact-LightItalicG3" : @".SFCompact",
             @".SFCompact-LightItalicG4" : @".SFCompact",
             @".SFCompact-Medium" : @".SFCompact",
             @".SFCompact-MediumG1" : @".SFCompact",
             @".SFCompact-MediumG2" : @".SFCompact",
             @".SFCompact-MediumG3" : @".SFCompact",
             @".SFCompact-MediumG4" : @".SFCompact",
             @".SFCompact-MediumItalic" : @".SFCompact",
             @".SFCompact-MediumItalicG1" : @".SFCompact",
             @".SFCompact-MediumItalicG2" : @".SFCompact",
             @".SFCompact-MediumItalicG3" : @".SFCompact",
             @".SFCompact-MediumItalicG4" : @".SFCompact",
             @".SFCompact-Regular" : @".SFCompact",
             @".SFCompact-RegularG1" : @".SFCompact",
             @".SFCompact-RegularG2" : @".SFCompact",
             @".SFCompact-RegularG3" : @".SFCompact",
             @".SFCompact-RegularG4" : @".SFCompact",
             @".SFCompact-RegularItalic" : @".SFCompact",
             @".SFCompact-RegularItalicG1" : @".SFCompact",
             @".SFCompact-RegularItalicG2" : @".SFCompact",
             @".SFCompact-RegularItalicG3" : @".SFCompact",
             @".SFCompact-RegularItalicG4" : @".SFCompact",
             @".SFCompact-Semibold" : @".SFCompact",
             @".SFCompact-SemiboldG1" : @".SFCompact",
             @".SFCompact-SemiboldG2" : @".SFCompact",
             @".SFCompact-SemiboldG3" : @".SFCompact",
             @".SFCompact-SemiboldG4" : @".SFCompact",
             @".SFCompact-SemiboldItalic" : @".SFCompact",
             @".SFCompact-SemiboldItalicG1" : @".SFCompact",
             @".SFCompact-SemiboldItalicG2" : @".SFCompact",
             @".SFCompact-SemiboldItalicG3" : @".SFCompact",
             @".SFCompact-SemiboldItalicG4" : @".SFCompact",
             @".SFCompact-Thin" : @".SFCompact",
             @".SFCompact-ThinG1" : @".SFCompact",
             @".SFCompact-ThinG2" : @".SFCompact",
             @".SFCompact-ThinG3" : @".SFCompact",
             @".SFCompact-ThinG4" : @".SFCompact",
             @".SFCompact-ThinItalic" : @".SFCompact",
             @".SFCompact-ThinItalicG1" : @".SFCompact",
             @".SFCompact-ThinItalicG2" : @".SFCompact",
             @".SFCompact-ThinItalicG3" : @".SFCompact",
             @".SFCompact-ThinItalicG4" : @".SFCompact",
             @".SFCompact-Ultralight" : @".SFCompact",
             @".SFCompact-UltralightG1" : @".SFCompact",
             @".SFCompact-UltralightG2" : @".SFCompact",
             @".SFCompact-UltralightG3" : @".SFCompact",
             @".SFCompact-UltralightG4" : @".SFCompact",
             @".SFCompact-UltralightItalic" : @".SFCompact",
             @".SFCompact-UltralightItalicG1" : @".SFCompact",
             @".SFCompact-UltralightItalicG2" : @".SFCompact",
             @".SFCompact-UltralightItalicG3" : @".SFCompact",
             @".SFCompact-UltralightItalicG4" : @".SFCompact",
             @".SFNS-CompressedBlack" : @".SFNS",
             @".SFNS-CompressedBold" : @".SFNS",
             @".SFNS-CompressedBoldG1" : @".SFNS",
             @".SFNS-CompressedBoldG2" : @".SFNS",
             @".SFNS-CompressedBoldG3" : @".SFNS",
             @".SFNS-CompressedBoldG4" : @".SFNS",
             @".SFNS-CompressedHeavy" : @".SFNS",
             @".SFNS-CompressedHeavyG1" : @".SFNS",
             @".SFNS-CompressedHeavyG2" : @".SFNS",
             @".SFNS-CompressedHeavyG3" : @".SFNS",
             @".SFNS-CompressedHeavyG4" : @".SFNS",
             @".SFNS-CompressedLight" : @".SFNS",
             @".SFNS-CompressedLightG1" : @".SFNS",
             @".SFNS-CompressedLightG2" : @".SFNS",
             @".SFNS-CompressedLightG3" : @".SFNS",
             @".SFNS-CompressedLightG4" : @".SFNS",
             @".SFNS-CompressedMedium" : @".SFNS",
             @".SFNS-CompressedMediumG1" : @".SFNS",
             @".SFNS-CompressedMediumG2" : @".SFNS",
             @".SFNS-CompressedMediumG3" : @".SFNS",
             @".SFNS-CompressedMediumG4" : @".SFNS",
             @".SFNS-CompressedRegular" : @".SFNS",
             @".SFNS-CompressedRegularG1" : @".SFNS",
             @".SFNS-CompressedRegularG2" : @".SFNS",
             @".SFNS-CompressedRegularG3" : @".SFNS",
             @".SFNS-CompressedRegularG4" : @".SFNS",
             @".SFNS-CompressedSemibold" : @".SFNS",
             @".SFNS-CompressedSemiboldG1" : @".SFNS",
             @".SFNS-CompressedSemiboldG2" : @".SFNS",
             @".SFNS-CompressedSemiboldG3" : @".SFNS",
             @".SFNS-CompressedSemiboldG4" : @".SFNS",
             @".SFNS-CompressedThin" : @".SFNS",
             @".SFNS-CompressedThinG1" : @".SFNS",
             @".SFNS-CompressedThinG2" : @".SFNS",
             @".SFNS-CompressedThinG3" : @".SFNS",
             @".SFNS-CompressedThinG4" : @".SFNS",
             @".SFNS-CompressedUltralight" : @".SFNS",
             @".SFNS-CompressedUltralightG1" : @".SFNS",
             @".SFNS-CompressedUltralightG2" : @".SFNS",
             @".SFNS-CompressedUltralightG3" : @".SFNS",
             @".SFNS-CompressedUltralightG4" : @".SFNS",
             @".SFNS-CondensedBlack" : @".SFNS",
             @".SFNS-CondensedBold" : @".SFNS",
             @".SFNS-CondensedBoldG1" : @".SFNS",
             @".SFNS-CondensedBoldG2" : @".SFNS",
             @".SFNS-CondensedBoldG3" : @".SFNS",
             @".SFNS-CondensedBoldG4" : @".SFNS",
             @".SFNS-CondensedHeavy" : @".SFNS",
             @".SFNS-CondensedHeavyG1" : @".SFNS",
             @".SFNS-CondensedHeavyG2" : @".SFNS",
             @".SFNS-CondensedHeavyG3" : @".SFNS",
             @".SFNS-CondensedHeavyG4" : @".SFNS",
             @".SFNS-CondensedLight" : @".SFNS",
             @".SFNS-CondensedLightG1" : @".SFNS",
             @".SFNS-CondensedLightG2" : @".SFNS",
             @".SFNS-CondensedLightG3" : @".SFNS",
             @".SFNS-CondensedLightG4" : @".SFNS",
             @".SFNS-CondensedMedium" : @".SFNS",
             @".SFNS-CondensedMediumG1" : @".SFNS",
             @".SFNS-CondensedMediumG2" : @".SFNS",
             @".SFNS-CondensedMediumG3" : @".SFNS",
             @".SFNS-CondensedMediumG4" : @".SFNS",
             @".SFNS-CondensedRegular" : @".SFNS",
             @".SFNS-CondensedRegularG1" : @".SFNS",
             @".SFNS-CondensedRegularG2" : @".SFNS",
             @".SFNS-CondensedRegularG3" : @".SFNS",
             @".SFNS-CondensedRegularG4" : @".SFNS",
             @".SFNS-CondensedSemibold" : @".SFNS",
             @".SFNS-CondensedSemiboldG1" : @".SFNS",
             @".SFNS-CondensedSemiboldG2" : @".SFNS",
             @".SFNS-CondensedSemiboldG3" : @".SFNS",
             @".SFNS-CondensedSemiboldG4" : @".SFNS",
             @".SFNS-CondensedThin" : @".SFNS",
             @".SFNS-CondensedThinG1" : @".SFNS",
             @".SFNS-CondensedThinG2" : @".SFNS",
             @".SFNS-CondensedThinG3" : @".SFNS",
             @".SFNS-CondensedThinG4" : @".SFNS",
             @".SFNS-CondensedUltralight" : @".SFNS",
             @".SFNS-CondensedUltralightG1" : @".SFNS",
             @".SFNS-CondensedUltralightG2" : @".SFNS",
             @".SFNS-CondensedUltralightG3" : @".SFNS",
             @".SFNS-CondensedUltralightG4" : @".SFNS",
             @".SFNS-ExpandedBlack" : @".SFNS",
             @".SFNS-ExpandedBold" : @".SFNS",
             @".SFNS-ExpandedBoldG1" : @".SFNS",
             @".SFNS-ExpandedBoldG2" : @".SFNS",
             @".SFNS-ExpandedBoldG3" : @".SFNS",
             @".SFNS-ExpandedBoldG4" : @".SFNS",
             @".SFNS-ExpandedHeavy" : @".SFNS",
             @".SFNS-ExpandedHeavyG1" : @".SFNS",
             @".SFNS-ExpandedHeavyG2" : @".SFNS",
             @".SFNS-ExpandedHeavyG3" : @".SFNS",
             @".SFNS-ExpandedHeavyG4" : @".SFNS",
             @".SFNS-ExpandedLight" : @".SFNS",
             @".SFNS-ExpandedLightG1" : @".SFNS",
             @".SFNS-ExpandedLightG2" : @".SFNS",
             @".SFNS-ExpandedLightG3" : @".SFNS",
             @".SFNS-ExpandedLightG4" : @".SFNS",
             @".SFNS-ExpandedMedium" : @".SFNS",
             @".SFNS-ExpandedMediumG1" : @".SFNS",
             @".SFNS-ExpandedMediumG2" : @".SFNS",
             @".SFNS-ExpandedMediumG3" : @".SFNS",
             @".SFNS-ExpandedMediumG4" : @".SFNS",
             @".SFNS-ExpandedRegular" : @".SFNS",
             @".SFNS-ExpandedRegularG1" : @".SFNS",
             @".SFNS-ExpandedRegularG2" : @".SFNS",
             @".SFNS-ExpandedRegularG3" : @".SFNS",
             @".SFNS-ExpandedRegularG4" : @".SFNS",
             @".SFNS-ExpandedSemibold" : @".SFNS",
             @".SFNS-ExpandedSemiboldG1" : @".SFNS",
             @".SFNS-ExpandedSemiboldG2" : @".SFNS",
             @".SFNS-ExpandedSemiboldG3" : @".SFNS",
             @".SFNS-ExpandedSemiboldG4" : @".SFNS",
             @".SFNS-ExpandedThin" : @".SFNS",
             @".SFNS-ExpandedThinG1" : @".SFNS",
             @".SFNS-ExpandedThinG2" : @".SFNS",
             @".SFNS-ExpandedThinG3" : @".SFNS",
             @".SFNS-ExpandedThinG4" : @".SFNS",
             @".SFNS-ExpandedUltralight" : @".SFNS",
             @".SFNS-ExpandedUltralightG1" : @".SFNS",
             @".SFNS-ExpandedUltralightG2" : @".SFNS",
             @".SFNS-ExpandedUltralightG3" : @".SFNS",
             @".SFNS-ExpandedUltralightG4" : @".SFNS",
             @".SFNS-ExtraCompressedBlack" : @".SFNS",
             @".SFNS-ExtraCompressedBold" : @".SFNS",
             @".SFNS-ExtraCompressedBoldG1" : @".SFNS",
             @".SFNS-ExtraCompressedBoldG2" : @".SFNS",
             @".SFNS-ExtraCompressedBoldG3" : @".SFNS",
             @".SFNS-ExtraCompressedBoldG4" : @".SFNS",
             @".SFNS-ExtraCompressedHeavy" : @".SFNS",
             @".SFNS-ExtraCompressedHeavyG1" : @".SFNS",
             @".SFNS-ExtraCompressedHeavyG2" : @".SFNS",
             @".SFNS-ExtraCompressedHeavyG3" : @".SFNS",
             @".SFNS-ExtraCompressedHeavyG4" : @".SFNS",
             @".SFNS-ExtraCompressedLight" : @".SFNS",
             @".SFNS-ExtraCompressedLightG1" : @".SFNS",
             @".SFNS-ExtraCompressedLightG2" : @".SFNS",
             @".SFNS-ExtraCompressedLightG3" : @".SFNS",
             @".SFNS-ExtraCompressedLightG4" : @".SFNS",
             @".SFNS-ExtraCompressedMedium" : @".SFNS",
             @".SFNS-ExtraCompressedMediumG1" : @".SFNS",
             @".SFNS-ExtraCompressedMediumG2" : @".SFNS",
             @".SFNS-ExtraCompressedMediumG3" : @".SFNS",
             @".SFNS-ExtraCompressedMediumG4" : @".SFNS",
             @".SFNS-ExtraCompressedRegular" : @".SFNS",
             @".SFNS-ExtraCompressedRegularG1" : @".SFNS",
             @".SFNS-ExtraCompressedRegularG2" : @".SFNS",
             @".SFNS-ExtraCompressedRegularG3" : @".SFNS",
             @".SFNS-ExtraCompressedRegularG4" : @".SFNS",
             @".SFNS-ExtraCompressedSemibold" : @".SFNS",
             @".SFNS-ExtraCompressedSemiboldG1" : @".SFNS",
             @".SFNS-ExtraCompressedSemiboldG2" : @".SFNS",
             @".SFNS-ExtraCompressedSemiboldG3" : @".SFNS",
             @".SFNS-ExtraCompressedSemiboldG4" : @".SFNS",
             @".SFNS-ExtraCompressedThin" : @".SFNS",
             @".SFNS-ExtraCompressedThinG1" : @".SFNS",
             @".SFNS-ExtraCompressedThinG2" : @".SFNS",
             @".SFNS-ExtraCompressedThinG3" : @".SFNS",
             @".SFNS-ExtraCompressedThinG4" : @".SFNS",
             @".SFNS-ExtraCompressedUltralight" : @".SFNS",
             @".SFNS-ExtraCompressedUltralightG1" : @".SFNS",
             @".SFNS-ExtraCompressedUltralightG2" : @".SFNS",
             @".SFNS-ExtraCompressedUltralightG3" : @".SFNS",
             @".SFNS-ExtraCompressedUltralightG4" : @".SFNS",
             @".SFNS-ExtraExpandedBlack" : @".SFNS",
             @".SFNS-ExtraExpandedBold" : @".SFNS",
             @".SFNS-ExtraExpandedBoldG1" : @".SFNS",
             @".SFNS-ExtraExpandedBoldG2" : @".SFNS",
             @".SFNS-ExtraExpandedBoldG3" : @".SFNS",
             @".SFNS-ExtraExpandedBoldG4" : @".SFNS",
             @".SFNS-ExtraExpandedHeavy" : @".SFNS",
             @".SFNS-ExtraExpandedHeavyG1" : @".SFNS",
             @".SFNS-ExtraExpandedHeavyG2" : @".SFNS",
             @".SFNS-ExtraExpandedHeavyG3" : @".SFNS",
             @".SFNS-ExtraExpandedHeavyG4" : @".SFNS",
             @".SFNS-ExtraExpandedLight" : @".SFNS",
             @".SFNS-ExtraExpandedLightG1" : @".SFNS",
             @".SFNS-ExtraExpandedLightG2" : @".SFNS",
             @".SFNS-ExtraExpandedLightG3" : @".SFNS",
             @".SFNS-ExtraExpandedLightG4" : @".SFNS",
             @".SFNS-ExtraExpandedMedium" : @".SFNS",
             @".SFNS-ExtraExpandedMediumG1" : @".SFNS",
             @".SFNS-ExtraExpandedMediumG2" : @".SFNS",
             @".SFNS-ExtraExpandedMediumG3" : @".SFNS",
             @".SFNS-ExtraExpandedMediumG4" : @".SFNS",
             @".SFNS-ExtraExpandedRegular" : @".SFNS",
             @".SFNS-ExtraExpandedRegularG1" : @".SFNS",
             @".SFNS-ExtraExpandedRegularG2" : @".SFNS",
             @".SFNS-ExtraExpandedRegularG3" : @".SFNS",
             @".SFNS-ExtraExpandedRegularG4" : @".SFNS",
             @".SFNS-ExtraExpandedSemibold" : @".SFNS",
             @".SFNS-ExtraExpandedSemiboldG1" : @".SFNS",
             @".SFNS-ExtraExpandedSemiboldG2" : @".SFNS",
             @".SFNS-ExtraExpandedSemiboldG3" : @".SFNS",
             @".SFNS-ExtraExpandedSemiboldG4" : @".SFNS",
             @".SFNS-ExtraExpandedThin" : @".SFNS",
             @".SFNS-ExtraExpandedThinG1" : @".SFNS",
             @".SFNS-ExtraExpandedThinG2" : @".SFNS",
             @".SFNS-ExtraExpandedThinG3" : @".SFNS",
             @".SFNS-ExtraExpandedThinG4" : @".SFNS",
             @".SFNS-ExtraExpandedUltralight" : @".SFNS",
             @".SFNS-ExtraExpandedUltralightG1" : @".SFNS",
             @".SFNS-ExtraExpandedUltralightG2" : @".SFNS",
             @".SFNS-ExtraExpandedUltralightG3" : @".SFNS",
             @".SFNS-ExtraExpandedUltralightG4" : @".SFNS",
             @".SFNS-SemiCondensedBlack" : @".SFNS",
             @".SFNS-SemiCondensedBold" : @".SFNS",
             @".SFNS-SemiCondensedBoldG1" : @".SFNS",
             @".SFNS-SemiCondensedBoldG2" : @".SFNS",
             @".SFNS-SemiCondensedBoldG3" : @".SFNS",
             @".SFNS-SemiCondensedBoldG4" : @".SFNS",
             @".SFNS-SemiCondensedHeavy" : @".SFNS",
             @".SFNS-SemiCondensedHeavyG1" : @".SFNS",
             @".SFNS-SemiCondensedHeavyG2" : @".SFNS",
             @".SFNS-SemiCondensedHeavyG3" : @".SFNS",
             @".SFNS-SemiCondensedHeavyG4" : @".SFNS",
             @".SFNS-SemiCondensedLight" : @".SFNS",
             @".SFNS-SemiCondensedLightG1" : @".SFNS",
             @".SFNS-SemiCondensedLightG2" : @".SFNS",
             @".SFNS-SemiCondensedLightG3" : @".SFNS",
             @".SFNS-SemiCondensedLightG4" : @".SFNS",
             @".SFNS-SemiCondensedMedium" : @".SFNS",
             @".SFNS-SemiCondensedMediumG1" : @".SFNS",
             @".SFNS-SemiCondensedMediumG2" : @".SFNS",
             @".SFNS-SemiCondensedMediumG3" : @".SFNS",
             @".SFNS-SemiCondensedMediumG4" : @".SFNS",
             @".SFNS-SemiCondensedRegular" : @".SFNS",
             @".SFNS-SemiCondensedRegularG1" : @".SFNS",
             @".SFNS-SemiCondensedRegularG2" : @".SFNS",
             @".SFNS-SemiCondensedRegularG3" : @".SFNS",
             @".SFNS-SemiCondensedRegularG4" : @".SFNS",
             @".SFNS-SemiCondensedSemibold" : @".SFNS",
             @".SFNS-SemiCondensedSemiboldG1" : @".SFNS",
             @".SFNS-SemiCondensedSemiboldG2" : @".SFNS",
             @".SFNS-SemiCondensedSemiboldG3" : @".SFNS",
             @".SFNS-SemiCondensedSemiboldG4" : @".SFNS",
             @".SFNS-SemiCondensedThin" : @".SFNS",
             @".SFNS-SemiCondensedThinG1" : @".SFNS",
             @".SFNS-SemiCondensedThinG2" : @".SFNS",
             @".SFNS-SemiCondensedThinG3" : @".SFNS",
             @".SFNS-SemiCondensedThinG4" : @".SFNS",
             @".SFNS-SemiCondensedUltralight" : @".SFNS",
             @".SFNS-SemiCondensedUltralightG1" : @".SFNS",
             @".SFNS-SemiCondensedUltralightG2" : @".SFNS",
             @".SFNS-SemiCondensedUltralightG3" : @".SFNS",
             @".SFNS-SemiCondensedUltralightG4" : @".SFNS",
             @".SFNS-SemiExpandedBlack" : @".SFNS",
             @".SFNS-SemiExpandedBold" : @".SFNS",
             @".SFNS-SemiExpandedBoldG1" : @".SFNS",
             @".SFNS-SemiExpandedBoldG2" : @".SFNS",
             @".SFNS-SemiExpandedBoldG3" : @".SFNS",
             @".SFNS-SemiExpandedBoldG4" : @".SFNS",
             @".SFNS-SemiExpandedHeavy" : @".SFNS",
             @".SFNS-SemiExpandedHeavyG1" : @".SFNS",
             @".SFNS-SemiExpandedHeavyG2" : @".SFNS",
             @".SFNS-SemiExpandedHeavyG3" : @".SFNS",
             @".SFNS-SemiExpandedHeavyG4" : @".SFNS",
             @".SFNS-SemiExpandedLight" : @".SFNS",
             @".SFNS-SemiExpandedLightG1" : @".SFNS",
             @".SFNS-SemiExpandedLightG2" : @".SFNS",
             @".SFNS-SemiExpandedLightG3" : @".SFNS",
             @".SFNS-SemiExpandedLightG4" : @".SFNS",
             @".SFNS-SemiExpandedMedium" : @".SFNS",
             @".SFNS-SemiExpandedMediumG1" : @".SFNS",
             @".SFNS-SemiExpandedMediumG2" : @".SFNS",
             @".SFNS-SemiExpandedMediumG3" : @".SFNS",
             @".SFNS-SemiExpandedMediumG4" : @".SFNS",
             @".SFNS-SemiExpandedRegular" : @".SFNS",
             @".SFNS-SemiExpandedRegularG1" : @".SFNS",
             @".SFNS-SemiExpandedRegularG2" : @".SFNS",
             @".SFNS-SemiExpandedRegularG3" : @".SFNS",
             @".SFNS-SemiExpandedRegularG4" : @".SFNS",
             @".SFNS-SemiExpandedSemibold" : @".SFNS",
             @".SFNS-SemiExpandedSemiboldG1" : @".SFNS",
             @".SFNS-SemiExpandedSemiboldG2" : @".SFNS",
             @".SFNS-SemiExpandedSemiboldG3" : @".SFNS",
             @".SFNS-SemiExpandedSemiboldG4" : @".SFNS",
             @".SFNS-SemiExpandedThin" : @".SFNS",
             @".SFNS-SemiExpandedThinG1" : @".SFNS",
             @".SFNS-SemiExpandedThinG2" : @".SFNS",
             @".SFNS-SemiExpandedThinG3" : @".SFNS",
             @".SFNS-SemiExpandedThinG4" : @".SFNS",
             @".SFNS-SemiExpandedUltralight" : @".SFNS",
             @".SFNS-SemiExpandedUltralightG1" : @".SFNS",
             @".SFNS-SemiExpandedUltralightG2" : @".SFNS",
             @".SFNS-SemiExpandedUltralightG3" : @".SFNS",
             @".SFNS-SemiExpandedUltralightG4" : @".SFNS",
             @".SFNS-UltraCompressedBlack" : @".SFNS",
             @".SFNS-UltraCompressedBold" : @".SFNS",
             @".SFNS-UltraCompressedBoldG1" : @".SFNS",
             @".SFNS-UltraCompressedBoldG2" : @".SFNS",
             @".SFNS-UltraCompressedBoldG3" : @".SFNS",
             @".SFNS-UltraCompressedBoldG4" : @".SFNS",
             @".SFNS-UltraCompressedHeavy" : @".SFNS",
             @".SFNS-UltraCompressedHeavyG1" : @".SFNS",
             @".SFNS-UltraCompressedHeavyG2" : @".SFNS",
             @".SFNS-UltraCompressedHeavyG3" : @".SFNS",
             @".SFNS-UltraCompressedHeavyG4" : @".SFNS",
             @".SFNS-UltraCompressedLight" : @".SFNS",
             @".SFNS-UltraCompressedLightG1" : @".SFNS",
             @".SFNS-UltraCompressedLightG2" : @".SFNS",
             @".SFNS-UltraCompressedLightG3" : @".SFNS",
             @".SFNS-UltraCompressedLightG4" : @".SFNS",
             @".SFNS-UltraCompressedMedium" : @".SFNS",
             @".SFNS-UltraCompressedMediumG1" : @".SFNS",
             @".SFNS-UltraCompressedMediumG2" : @".SFNS",
             @".SFNS-UltraCompressedMediumG3" : @".SFNS",
             @".SFNS-UltraCompressedMediumG4" : @".SFNS",
             @".SFNS-UltraCompressedRegular" : @".SFNS",
             @".SFNS-UltraCompressedRegularG1" : @".SFNS",
             @".SFNS-UltraCompressedRegularG2" : @".SFNS",
             @".SFNS-UltraCompressedRegularG3" : @".SFNS",
             @".SFNS-UltraCompressedRegularG4" : @".SFNS",
             @".SFNS-UltraCompressedSemibold" : @".SFNS",
             @".SFNS-UltraCompressedSemiboldG1" : @".SFNS",
             @".SFNS-UltraCompressedSemiboldG2" : @".SFNS",
             @".SFNS-UltraCompressedSemiboldG3" : @".SFNS",
             @".SFNS-UltraCompressedSemiboldG4" : @".SFNS",
             @".SFNS-UltraCompressedThin" : @".SFNS",
             @".SFNS-UltraCompressedThinG1" : @".SFNS",
             @".SFNS-UltraCompressedThinG2" : @".SFNS",
             @".SFNS-UltraCompressedThinG3" : @".SFNS",
             @".SFNS-UltraCompressedThinG4" : @".SFNS",
             @".SFNS-UltraCompressedUltralight" : @".SFNS",
             @".SFNS-UltraCompressedUltralightG1" : @".SFNS",
             @".SFNS-UltraCompressedUltralightG2" : @".SFNS",
             @".SFNS-UltraCompressedUltralightG3" : @".SFNS",
             @".SFNS-UltraCompressedUltralightG4" : @".SFNS",
             @".SanaPUA" : @".Sana PUA",
             @".SavoyeLetPlainCC" : @".Savoye LET CC.",
             @"AlBayan" : @"Al Bayan",
             @"AlBayan-Bold" : @"Al Bayan",
             @"AlNile" : @"Al Nile",
             @"AlNile-Bold" : @"Al Nile",
             @"AlTarikh" : @"Al Tarikh",
             @"AmericanTypewriter" : @"American Typewriter",
             @"AmericanTypewriter-Bold" : @"American Typewriter",
             @"AmericanTypewriter-Condensed" : @"American Typewriter",
             @"AmericanTypewriter-CondensedBold" : @"American Typewriter",
             @"AmericanTypewriter-CondensedLight" : @"American Typewriter",
             @"AmericanTypewriter-Light" : @"American Typewriter",
             @"AmericanTypewriter-Semibold" : @"American Typewriter",
             @"AndaleMono" : @"Andale Mono",
             @"Apple-Chancery" : @"Apple Chancery",
             @"AppleBraille" : @"Apple Braille",
             @"AppleBraille-Outline6Dot" : @"Apple Braille",
             @"AppleBraille-Outline8Dot" : @"Apple Braille",
             @"AppleBraille-Pinpoint6Dot" : @"Apple Braille",
             @"AppleBraille-Pinpoint8Dot" : @"Apple Braille",
             @"AppleColorEmoji" : @"Apple Color Emoji",
             @"AppleGothic" : @"AppleGothic",
             @"AppleMyungjo" : @"AppleMyungjo",
             @"AppleSDGothicNeo-Bold" : @"Apple SD Gothic Neo",
             @"AppleSDGothicNeo-ExtraBold" : @"Apple SD Gothic Neo",
             @"AppleSDGothicNeo-Heavy" : @"Apple SD Gothic Neo",
             @"AppleSDGothicNeo-Light" : @"Apple SD Gothic Neo",
             @"AppleSDGothicNeo-Medium" : @"Apple SD Gothic Neo",
             @"AppleSDGothicNeo-Regular" : @"Apple SD Gothic Neo",
             @"AppleSDGothicNeo-SemiBold" : @"Apple SD Gothic Neo",
             @"AppleSDGothicNeo-Thin" : @"Apple SD Gothic Neo",
             @"AppleSDGothicNeo-UltraLight" : @"Apple SD Gothic Neo",
             @"AppleSymbols" : @"Apple Symbols",
             @"AquaKana" : @".Aqua Kana",
             @"AquaKana-Bold" : @".Aqua Kana",
             @"Arial-Black" : @"Arial Black",
             @"Arial-BoldItalicMT" : @"Arial",
             @"Arial-BoldMT" : @"Arial",
             @"Arial-ItalicMT" : @"Arial",
             @"ArialHebrew" : @"Arial Hebrew",
             @"ArialHebrew-Bold" : @"Arial Hebrew",
             @"ArialHebrew-Light" : @"Arial Hebrew",
             @"ArialHebrewScholar" : @"Arial Hebrew Scholar",
             @"ArialHebrewScholar-Bold" : @"Arial Hebrew Scholar",
             @"ArialHebrewScholar-Light" : @"Arial Hebrew Scholar",
             @"ArialMT" : @"Arial",
             @"ArialNarrow" : @"Arial Narrow",
             @"ArialNarrow-Bold" : @"Arial Narrow",
             @"ArialNarrow-BoldItalic" : @"Arial Narrow",
             @"ArialNarrow-Italic" : @"Arial Narrow",
             @"ArialRoundedMTBold" : @"Arial Rounded MT Bold",
             @"ArialUnicodeMS" : @"Arial Unicode MS",
             @"Athelas-Bold" : @"Athelas",
             @"Athelas-BoldItalic" : @"Athelas",
             @"Athelas-Italic" : @"Athelas",
             @"Athelas-Regular" : @"Athelas",
             @"Avenir-Black" : @"Avenir",
             @"Avenir-BlackOblique" : @"Avenir",
             @"Avenir-Book" : @"Avenir",
             @"Avenir-BookOblique" : @"Avenir",
             @"Avenir-Heavy" : @"Avenir",
             @"Avenir-HeavyOblique" : @"Avenir",
             @"Avenir-Light" : @"Avenir",
             @"Avenir-LightOblique" : @"Avenir",
             @"Avenir-Medium" : @"Avenir",
             @"Avenir-MediumOblique" : @"Avenir",
             @"Avenir-Oblique" : @"Avenir",
             @"Avenir-Roman" : @"Avenir",
             @"AvenirNext-Bold" : @"Avenir Next",
             @"AvenirNext-BoldItalic" : @"Avenir Next",
             @"AvenirNext-DemiBold" : @"Avenir Next",
             @"AvenirNext-DemiBoldItalic" : @"Avenir Next",
             @"AvenirNext-Heavy" : @"Avenir Next",
             @"AvenirNext-HeavyItalic" : @"Avenir Next",
             @"AvenirNext-Italic" : @"Avenir Next",
             @"AvenirNext-Medium" : @"Avenir Next",
             @"AvenirNext-MediumItalic" : @"Avenir Next",
             @"AvenirNext-Regular" : @"Avenir Next",
             @"AvenirNext-UltraLight" : @"Avenir Next",
             @"AvenirNext-UltraLightItalic" : @"Avenir Next",
             @"AvenirNextCondensed-Bold" : @"Avenir Next Condensed",
             @"AvenirNextCondensed-BoldItalic" : @"Avenir Next Condensed",
             @"AvenirNextCondensed-DemiBold" : @"Avenir Next Condensed",
             @"AvenirNextCondensed-DemiBoldItalic" : @"Avenir Next Condensed",
             @"AvenirNextCondensed-Heavy" : @"Avenir Next Condensed",
             @"AvenirNextCondensed-HeavyItalic" : @"Avenir Next Condensed",
             @"AvenirNextCondensed-Italic" : @"Avenir Next Condensed",
             @"AvenirNextCondensed-Medium" : @"Avenir Next Condensed",
             @"AvenirNextCondensed-MediumItalic" : @"Avenir Next Condensed",
             @"AvenirNextCondensed-Regular" : @"Avenir Next Condensed",
             @"AvenirNextCondensed-UltraLight" : @"Avenir Next Condensed",
             @"AvenirNextCondensed-UltraLightItalic" : @"Avenir Next Condensed",
             @"Ayuthaya" : @"Ayuthaya",
             @"Baghdad" : @"Baghdad",
             @"BanglaMN" : @"Bangla MN",
             @"BanglaMN-Bold" : @"Bangla MN",
             @"BanglaSangamMN" : @"Bangla Sangam MN",
             @"BanglaSangamMN-Bold" : @"Bangla Sangam MN",
             @"Baskerville" : @"Baskerville",
             @"Baskerville-Bold" : @"Baskerville",
             @"Baskerville-BoldItalic" : @"Baskerville",
             @"Baskerville-Italic" : @"Baskerville",
             @"Baskerville-SemiBold" : @"Baskerville",
             @"Baskerville-SemiBoldItalic" : @"Baskerville",
             @"Beirut" : @"Beirut",
             @"BigCaslon-Medium" : @"Big Caslon",
             @"BodoniOrnamentsITCTT" : @"Bodoni Ornaments",
             @"BodoniSvtyTwoITCTT-Bold" : @"Bodoni 72",
             @"BodoniSvtyTwoITCTT-Book" : @"Bodoni 72",
             @"BodoniSvtyTwoITCTT-BookIta" : @"Bodoni 72",
             @"BodoniSvtyTwoOSITCTT-Bold" : @"Bodoni 72 Oldstyle",
             @"BodoniSvtyTwoOSITCTT-Book" : @"Bodoni 72 Oldstyle",
             @"BodoniSvtyTwoOSITCTT-BookIt" : @"Bodoni 72 Oldstyle",
             @"BodoniSvtyTwoSCITCTT-Book" : @"Bodoni 72 Smallcaps",
             @"BradleyHandITCTT-Bold" : @"Bradley Hand",
             @"BrushScriptMT" : @"Brush Script MT",
             @"Calibri" : @"Calibri",
             @"Calibri-Bold" : @"Calibri",
             @"Calibri-BoldItalic" : @"Calibri",
             @"Calibri-Italic" : @"Calibri",
             @"Chalkboard" : @"Chalkboard",
             @"Chalkboard-Bold" : @"Chalkboard",
             @"ChalkboardSE-Bold" : @"Chalkboard SE",
             @"ChalkboardSE-Light" : @"Chalkboard SE",
             @"ChalkboardSE-Regular" : @"Chalkboard SE",
             @"Chalkduster" : @"Chalkduster",
             @"Charter-Black" : @"Charter",
             @"Charter-BlackItalic" : @"Charter",
             @"Charter-Bold" : @"Charter",
             @"Charter-BoldItalic" : @"Charter",
             @"Charter-Italic" : @"Charter",
             @"Charter-Roman" : @"Charter",
             @"Cochin" : @"Cochin",
             @"Cochin-Bold" : @"Cochin",
             @"Cochin-BoldItalic" : @"Cochin",
             @"Cochin-Italic" : @"Cochin",
             @"ComicSansMS" : @"Comic Sans MS",
             @"ComicSansMS-Bold" : @"Comic Sans MS",
             @"Copperplate" : @"Copperplate",
             @"Copperplate-Bold" : @"Copperplate",
             @"Copperplate-Light" : @"Copperplate",
             @"CorsivaHebrew" : @"Corsiva Hebrew",
             @"CorsivaHebrew-Bold" : @"Corsiva Hebrew",
             @"Courier" : @"Courier",
             @"Courier-Bold" : @"Courier",
             @"Courier-BoldOblique" : @"Courier",
             @"Courier-Oblique" : @"Courier",
             @"CourierNewPS-BoldItalicMT" : @"Courier New",
             @"CourierNewPS-BoldMT" : @"Courier New",
             @"CourierNewPS-ItalicMT" : @"Courier New",
             @"CourierNewPSMT" : @"Courier New",
             @"DINAlternate-Bold" : @"DIN Alternate",
             @"DINCondensed-Bold" : @"DIN Condensed",
             @"Damascus" : @"Damascus",
             @"DamascusBold" : @"Damascus",
             @"DamascusLight" : @"Damascus",
             @"DamascusMedium" : @"Damascus",
             @"DamascusSemiBold" : @"Damascus",
             @"DecoTypeNaskh" : @"DecoType Naskh",
             @"DevanagariMT" : @"Devanagari MT",
             @"DevanagariMT-Bold" : @"Devanagari MT",
             @"DevanagariSangamMN" : @"Devanagari Sangam MN",
             @"DevanagariSangamMN-Bold" : @"Devanagari Sangam MN",
             @"Didot" : @"Didot",
             @"Didot-Bold" : @"Didot",
             @"Didot-Italic" : @"Didot",
             @"DiwanKufi" : @"Diwan Kufi",
             @"DiwanMishafi" : @"Mishafi",
             @"DiwanMishafiGold" : @"Mishafi Gold",
             @"DiwanThuluth" : @"Diwan Thuluth",
             @"EuphemiaUCAS" : @"Euphemia UCAS",
             @"EuphemiaUCAS-Bold" : @"Euphemia UCAS",
             @"EuphemiaUCAS-Italic" : @"Euphemia UCAS",
             @"Farah" : @"Farah",
             @"Farisi" : @"Farisi",
             @"Futura-Bold" : @"Futura",
             @"Futura-CondensedExtraBold" : @"Futura",
             @"Futura-CondensedMedium" : @"Futura",
             @"Futura-Medium" : @"Futura",
             @"Futura-MediumItalic" : @"Futura",
             @"GB18030Bitmap" : @"GB18030 Bitmap",
             @"Galvji" : @"Galvji",
             @"Galvji-Bold" : @"Galvji",
             @"Galvji-BoldOblique" : @"Galvji",
             @"Galvji-Oblique" : @"Galvji",
             @"GeezaPro" : @"Geeza Pro",
             @"GeezaPro-Bold" : @"Geeza Pro",
             @"Geneva" : @"Geneva",
             @"Georgia" : @"Georgia",
             @"Georgia-Bold" : @"Georgia",
             @"Georgia-BoldItalic" : @"Georgia",
             @"Georgia-Italic" : @"Georgia",
             @"GillSans" : @"Gill Sans",
             @"GillSans-Bold" : @"Gill Sans",
             @"GillSans-BoldItalic" : @"Gill Sans",
             @"GillSans-Italic" : @"Gill Sans",
             @"GillSans-Light" : @"Gill Sans",
             @"GillSans-LightItalic" : @"Gill Sans",
             @"GillSans-SemiBold" : @"Gill Sans",
             @"GillSans-SemiBoldItalic" : @"Gill Sans",
             @"GillSans-UltraBold" : @"Gill Sans",
             @"GujaratiMT" : @"Gujarati MT",
             @"GujaratiMT-Bold" : @"Gujarati MT",
             @"GujaratiSangamMN" : @"Gujarati Sangam MN",
             @"GujaratiSangamMN-Bold" : @"Gujarati Sangam MN",
             @"GurmukhiMN" : @"Gurmukhi MN",
             @"GurmukhiMN-Bold" : @"Gurmukhi MN",
             @"GurmukhiSangamMN" : @"Gurmukhi Sangam MN",
             @"GurmukhiSangamMN-Bold" : @"Gurmukhi Sangam MN",
             @"Helvetica" : @"Helvetica",
             @"Helvetica-Bold" : @"Helvetica",
             @"Helvetica-BoldOblique" : @"Helvetica",
             @"Helvetica-Light" : @"Helvetica",
             @"Helvetica-LightOblique" : @"Helvetica",
             @"Helvetica-Oblique" : @"Helvetica",
             @"HelveticaLTMM" : @".Helvetica LT MM",
             @"HelveticaNeue" : @"Helvetica Neue",
             @"HelveticaNeue-Bold" : @"Helvetica Neue",
             @"HelveticaNeue-BoldItalic" : @"Helvetica Neue",
             @"HelveticaNeue-CondensedBlack" : @"Helvetica Neue",
             @"HelveticaNeue-CondensedBold" : @"Helvetica Neue",
             @"HelveticaNeue-Italic" : @"Helvetica Neue",
             @"HelveticaNeue-Light" : @"Helvetica Neue",
             @"HelveticaNeue-LightItalic" : @"Helvetica Neue",
             @"HelveticaNeue-Medium" : @"Helvetica Neue",
             @"HelveticaNeue-MediumItalic" : @"Helvetica Neue",
             @"HelveticaNeue-Thin" : @"Helvetica Neue",
             @"HelveticaNeue-ThinItalic" : @"Helvetica Neue",
             @"HelveticaNeue-UltraLight" : @"Helvetica Neue",
             @"HelveticaNeue-UltraLightItalic" : @"Helvetica Neue",
             @"Herculanum" : @"Herculanum",
             @"HiraKakuPro-W3" : @"Hiragino Kaku Gothic Pro",
             @"HiraKakuPro-W6" : @"Hiragino Kaku Gothic Pro",
             @"HiraKakuProN-W3" : @"Hiragino Kaku Gothic ProN",
             @"HiraKakuProN-W6" : @"Hiragino Kaku Gothic ProN",
             @"HiraKakuStd-W8" : @"Hiragino Kaku Gothic Std",
             @"HiraKakuStdN-W8" : @"Hiragino Kaku Gothic StdN",
             @"HiraMaruPro-W4" : @"Hiragino Maru Gothic Pro",
             @"HiraMaruProN-W4" : @"Hiragino Maru Gothic ProN",
             @"HiraMinPro-W3" : @"Hiragino Mincho Pro",
             @"HiraMinPro-W6" : @"Hiragino Mincho Pro",
             @"HiraMinProN-W3" : @"Hiragino Mincho ProN",
             @"HiraMinProN-W6" : @"Hiragino Mincho ProN",
             @"HiraginoSans-W0" : @"Hiragino Sans",
             @"HiraginoSans-W1" : @"Hiragino Sans",
             @"HiraginoSans-W2" : @"Hiragino Sans",
             @"HiraginoSans-W3" : @"Hiragino Sans",
             @"HiraginoSans-W4" : @"Hiragino Sans",
             @"HiraginoSans-W5" : @"Hiragino Sans",
             @"HiraginoSans-W6" : @"Hiragino Sans",
             @"HiraginoSans-W7" : @"Hiragino Sans",
             @"HiraginoSans-W8" : @"Hiragino Sans",
             @"HiraginoSans-W9" : @"Hiragino Sans",
             @"HiraginoSansGB-W3" : @"Hiragino Sans GB",
             @"HiraginoSansGB-W6" : @"Hiragino Sans GB",
             @"HoeflerText-Black" : @"Hoefler Text",
             @"HoeflerText-BlackItalic" : @"Hoefler Text",
             @"HoeflerText-Italic" : @"Hoefler Text",
             @"HoeflerText-Ornaments" : @"Hoefler Text",
             @"HoeflerText-Regular" : @"Hoefler Text",
             @"ITFDevanagari-Bold" : @"ITF Devanagari",
             @"ITFDevanagari-Book" : @"ITF Devanagari",
             @"ITFDevanagari-Demi" : @"ITF Devanagari",
             @"ITFDevanagari-Light" : @"ITF Devanagari",
             @"ITFDevanagari-Medium" : @"ITF Devanagari",
             @"ITFDevanagariMarathi-Bold" : @"ITF Devanagari Marathi",
             @"ITFDevanagariMarathi-Book" : @"ITF Devanagari Marathi",
             @"ITFDevanagariMarathi-Demi" : @"ITF Devanagari Marathi",
             @"ITFDevanagariMarathi-Light" : @"ITF Devanagari Marathi",
             @"ITFDevanagariMarathi-Medium" : @"ITF Devanagari Marathi",
             @"Impact" : @"Impact",
             @"InaiMathi" : @"InaiMathi",
             @"InaiMathi-Bold" : @"InaiMathi",
             @"IowanOldStyle-Black" : @"Iowan Old Style",
             @"IowanOldStyle-BlackItalic" : @"Iowan Old Style",
             @"IowanOldStyle-Bold" : @"Iowan Old Style",
             @"IowanOldStyle-BoldItalic" : @"Iowan Old Style",
             @"IowanOldStyle-Italic" : @"Iowan Old Style",
             @"IowanOldStyle-Roman" : @"Iowan Old Style",
             @"IowanOldStyle-Titling" : @"Iowan Old Style",
             @"Kailasa" : @"Kailasa",
             @"Kailasa-Bold" : @"Kailasa",
             @"KannadaMN" : @"Kannada MN",
             @"KannadaMN-Bold" : @"Kannada MN",
             @"KannadaSangamMN" : @"Kannada Sangam MN",
             @"KannadaSangamMN-Bold" : @"Kannada Sangam MN",
             @"Kefa-Bold" : @"Kefa",
             @"Kefa-Regular" : @"Kefa",
             @"KhmerMN" : @"Khmer MN",
             @"KhmerMN-Bold" : @"Khmer MN",
             @"KhmerSangamMN" : @"Khmer Sangam MN",
             @"KohinoorBangla-Bold" : @"Kohinoor Bangla",
             @"KohinoorBangla-Light" : @"Kohinoor Bangla",
             @"KohinoorBangla-Medium" : @"Kohinoor Bangla",
             @"KohinoorBangla-Regular" : @"Kohinoor Bangla",
             @"KohinoorBangla-Semibold" : @"Kohinoor Bangla",
             @"KohinoorDevanagari-Bold" : @"Kohinoor Devanagari",
             @"KohinoorDevanagari-Light" : @"Kohinoor Devanagari",
             @"KohinoorDevanagari-Medium" : @"Kohinoor Devanagari",
             @"KohinoorDevanagari-Regular" : @"Kohinoor Devanagari",
             @"KohinoorDevanagari-Semibold" : @"Kohinoor Devanagari",
             @"KohinoorGujarati-Bold" : @"Kohinoor Gujarati",
             @"KohinoorGujarati-Light" : @"Kohinoor Gujarati",
             @"KohinoorGujarati-Medium" : @"Kohinoor Gujarati",
             @"KohinoorGujarati-Regular" : @"Kohinoor Gujarati",
             @"KohinoorGujarati-Semibold" : @"Kohinoor Gujarati",
             @"KohinoorTelugu-Bold" : @"Kohinoor Telugu",
             @"KohinoorTelugu-Light" : @"Kohinoor Telugu",
             @"KohinoorTelugu-Medium" : @"Kohinoor Telugu",
             @"KohinoorTelugu-Regular" : @"Kohinoor Telugu",
             @"KohinoorTelugu-Semibold" : @"Kohinoor Telugu",
             @"Kokonor" : @"Kokonor",
             @"Krungthep" : @"Krungthep",
             @"KufiStandardGK" : @"KufiStandardGK",
             @"LaoMN" : @"Lao MN",
             @"LaoMN-Bold" : @"Lao MN",
             @"LaoSangamMN" : @"Lao Sangam MN",
             @"LastResort" : @".LastResort",
             @"LucidaGrande" : @"Lucida Grande",
             @"LucidaGrande-Bold" : @"Lucida Grande",
             @"Luminari-Regular" : @"Luminari",
             @"MalayalamMN" : @"Malayalam MN",
             @"MalayalamMN-Bold" : @"Malayalam MN",
             @"MalayalamSangamMN" : @"Malayalam Sangam MN",
             @"MalayalamSangamMN-Bold" : @"Malayalam Sangam MN",
             @"Marion-Bold" : @"Marion",
             @"Marion-Italic" : @"Marion",
             @"Marion-Regular" : @"Marion",
             @"MarkerFelt-Thin" : @"Marker Felt",
             @"MarkerFelt-Wide" : @"Marker Felt",
             @"Menlo-Bold" : @"Menlo",
             @"Menlo-BoldItalic" : @"Menlo",
             @"Menlo-Italic" : @"Menlo",
             @"Menlo-Regular" : @"Menlo",
             @"MicrosoftSansSerif" : @"Microsoft Sans Serif",
             @"Monaco" : @"Monaco",
             @"MonotypeGurmukhi" : @"Gurmukhi MT",
             @"Mshtakan" : @"Mshtakan",
             @"MshtakanBold" : @"Mshtakan",
             @"MshtakanBoldOblique" : @"Mshtakan",
             @"MshtakanOblique" : @"Mshtakan",
             @"MuktaMahee-Bold" : @"Mukta Mahee",
             @"MuktaMahee-ExtraBold" : @"Mukta Mahee",
             @"MuktaMahee-ExtraLight" : @"Mukta Mahee",
             @"MuktaMahee-Light" : @"Mukta Mahee",
             @"MuktaMahee-Medium" : @"Mukta Mahee",
             @"MuktaMahee-Regular" : @"Mukta Mahee",
             @"MuktaMahee-SemiBold" : @"Mukta Mahee",
             @"Muna" : @"Muna",
             @"MunaBlack" : @"Muna",
             @"MunaBold" : @"Muna",
             @"MyanmarMN" : @"Myanmar MN",
             @"MyanmarMN-Bold" : @"Myanmar MN",
             @"MyanmarSangamMN" : @"Myanmar Sangam MN",
             @"MyanmarSangamMN-Bold" : @"Myanmar Sangam MN",
             @"Nadeem" : @"Nadeem",
             @"NewPeninimMT" : @"New Peninim MT",
             @"NewPeninimMT-Bold" : @"New Peninim MT",
             @"NewPeninimMT-BoldInclined" : @"New Peninim MT",
             @"NewPeninimMT-Inclined" : @"New Peninim MT",
             @"Noteworthy-Bold" : @"Noteworthy",
             @"Noteworthy-Light" : @"Noteworthy",
             @"NotoNastaliqUrdu" : @"Noto Nastaliq Urdu",
             @"NotoNastaliqUrdu-Bold" : @"Noto Nastaliq Urdu",
             @"NotoSansArmenian-Black" : @"Noto Sans Armenian",
             @"NotoSansArmenian-Bold" : @"Noto Sans Armenian",
             @"NotoSansArmenian-ExtraBold" : @"Noto Sans Armenian",
             @"NotoSansArmenian-ExtraLight" : @"Noto Sans Armenian",
             @"NotoSansArmenian-Light" : @"Noto Sans Armenian",
             @"NotoSansArmenian-Medium" : @"Noto Sans Armenian",
             @"NotoSansArmenian-Regular" : @"Noto Sans Armenian",
             @"NotoSansArmenian-SemiBold" : @"Noto Sans Armenian",
             @"NotoSansArmenian-Thin" : @"Noto Sans Armenian",
             @"NotoSansAvestan-Regular" : @"Noto Sans Avestan",
             @"NotoSansBamum-Regular" : @"Noto Sans Bamum",
             @"NotoSansBatak-Regular" : @"Noto Sans Batak",
             @"NotoSansBrahmi-Regular" : @"Noto Sans Brahmi",
             @"NotoSansBuginese-Regular" : @"Noto Sans Buginese",
             @"NotoSansBuhid-Regular" : @"Noto Sans Buhid",
             @"NotoSansCarian-Regular" : @"Noto Sans Carian",
             @"NotoSansChakma-Regular" : @"Noto Sans Chakma",
             @"NotoSansCham-Regular" : @"Noto Sans Cham",
             @"NotoSansCoptic-Regular" : @"Noto Sans Coptic",
             @"NotoSansCuneiform-Regular" : @"Noto Sans Cuneiform",
             @"NotoSansCypriot-Regular" : @"Noto Sans Cypriot",
             @"NotoSansEgyptianHieroglyphs-Regular" : @"Noto Sans Egyptian Hieroglyphs",
             @"NotoSansGlagolitic-Regular" : @"Noto Sans Glagolitic",
             @"NotoSansGothic-Regular" : @"Noto Sans Gothic",
             @"NotoSansHanunoo-Regular" : @"Noto Sans Hanunoo",
             @"NotoSansImperialAramaic-Regular" : @"Noto Sans Imperial Aramaic",
             @"NotoSansInscriptionalPahlavi-Regular" : @"Noto Sans Inscriptional Pahlavi",
             @"NotoSansInscriptionalParthian-Regular" : @"Noto Sans Inscriptional Parthian",
             @"NotoSansJavanese-Regular" : @"Noto Sans Javanese",
             @"NotoSansKaithi-Regular" : @"Noto Sans Kaithi",
             @"NotoSansKannada-Black" : @"Noto Sans Kannada",
             @"NotoSansKannada-Bold" : @"Noto Sans Kannada",
             @"NotoSansKannada-ExtraBold" : @"Noto Sans Kannada",
             @"NotoSansKannada-ExtraLight" : @"Noto Sans Kannada",
             @"NotoSansKannada-Light" : @"Noto Sans Kannada",
             @"NotoSansKannada-Medium" : @"Noto Sans Kannada",
             @"NotoSansKannada-Regular" : @"Noto Sans Kannada",
             @"NotoSansKannada-SemiBold" : @"Noto Sans Kannada",
             @"NotoSansKannada-Thin" : @"Noto Sans Kannada",
             @"NotoSansKayahLi-Regular" : @"Noto Sans Kayah Li",
             @"NotoSansKharoshthi-Regular" : @"Noto Sans Kharoshthi",
             @"NotoSansLepcha-Regular" : @"Noto Sans Lepcha",
             @"NotoSansLimbu-Regular" : @"Noto Sans Limbu",
             @"NotoSansLinearB-Regular" : @"Noto Sans Linear B",
             @"NotoSansLisu-Regular" : @"Noto Sans Lisu",
             @"NotoSansLycian-Regular" : @"Noto Sans Lycian",
             @"NotoSansLydian-Regular" : @"Noto Sans Lydian",
             @"NotoSansMandaic-Regular" : @"Noto Sans Mandaic",
             @"NotoSansMeeteiMayek-Regular" : @"Noto Sans Meetei Mayek",
             @"NotoSansMongolian" : @"Noto Sans Mongolian",
             @"NotoSansMyanmar-Black" : @"Noto Sans Myanmar",
             @"NotoSansMyanmar-Bold" : @"Noto Sans Myanmar",
             @"NotoSansMyanmar-ExtraBold" : @"Noto Sans Myanmar",
             @"NotoSansMyanmar-ExtraLight" : @"Noto Sans Myanmar",
             @"NotoSansMyanmar-Light" : @"Noto Sans Myanmar",
             @"NotoSansMyanmar-Medium" : @"Noto Sans Myanmar",
             @"NotoSansMyanmar-Regular" : @"Noto Sans Myanmar",
             @"NotoSansMyanmar-SemiBold" : @"Noto Sans Myanmar",
             @"NotoSansMyanmar-Thin" : @"Noto Sans Myanmar",
             @"NotoSansNKo-Regular" : @"Noto Sans NKo",
             @"NotoSansNewTaiLue-Regular" : @"Noto Sans New Tai Lue",
             @"NotoSansOgham-Regular" : @"Noto Sans Ogham",
             @"NotoSansOlChiki-Regular" : @"Noto Sans Ol Chiki",
             @"NotoSansOldItalic-Regular" : @"Noto Sans Old Italic",
             @"NotoSansOldPersian-Regular" : @"Noto Sans Old Persian",
             @"NotoSansOldSouthArabian-Regular" : @"Noto Sans Old South Arabian",
             @"NotoSansOldTurkic-Regular" : @"Noto Sans Old Turkic",
             @"NotoSansOriya" : @"Noto Sans Oriya",
             @"NotoSansOriya-Bold" : @"Noto Sans Oriya",
             @"NotoSansOsmanya-Regular" : @"Noto Sans Osmanya",
             @"NotoSansPhagsPa-Regular" : @"Noto Sans PhagsPa",
             @"NotoSansPhoenician-Regular" : @"Noto Sans Phoenician",
             @"NotoSansRejang-Regular" : @"Noto Sans Rejang",
             @"NotoSansRunic-Regular" : @"Noto Sans Runic",
             @"NotoSansSamaritan-Regular" : @"Noto Sans Samaritan",
             @"NotoSansSaurashtra-Regular" : @"Noto Sans Saurashtra",
             @"NotoSansShavian-Regular" : @"Noto Sans Shavian",
             @"NotoSansSundanese-Regular" : @"Noto Sans Sundanese",
             @"NotoSansSylotiNagri-Regular" : @"Noto Sans Syloti Nagri",
             @"NotoSansSyriac-Regular" : @"Noto Sans Syriac",
             @"NotoSansTagalog-Regular" : @"Noto Sans Tagalog",
             @"NotoSansTagbanwa-Regular" : @"Noto Sans Tagbanwa",
             @"NotoSansTaiLe-Regular" : @"Noto Sans Tai Le",
             @"NotoSansTaiTham" : @"Noto Sans Tai Tham",
             @"NotoSansTaiViet-Regular" : @"Noto Sans Tai Viet",
             @"NotoSansThaana-Regular" : @"Noto Sans Thaana",
             @"NotoSansTifinagh-Regular" : @"Noto Sans Tifinagh",
             @"NotoSansUgaritic-Regular" : @"Noto Sans Ugaritic",
             @"NotoSansVai-Regular" : @"Noto Sans Vai",
             @"NotoSansYi-Regular" : @"Noto Sans Yi",
             @"NotoSansZawgyi-Black" : @"Noto Sans Zawgyi",
             @"NotoSansZawgyi-Bold" : @"Noto Sans Zawgyi",
             @"NotoSansZawgyi-ExtraBold" : @"Noto Sans Zawgyi",
             @"NotoSansZawgyi-ExtraLight" : @"Noto Sans Zawgyi",
             @"NotoSansZawgyi-Light" : @"Noto Sans Zawgyi",
             @"NotoSansZawgyi-Medium" : @"Noto Sans Zawgyi",
             @"NotoSansZawgyi-Regular" : @"Noto Sans Zawgyi",
             @"NotoSansZawgyi-SemiBold" : @"Noto Sans Zawgyi",
             @"NotoSansZawgyi-Thin" : @"Noto Sans Zawgyi",
             @"NotoSerifBalinese-Regular" : @"Noto Serif Balinese",
             @"NotoSerifMyanmar-Black" : @"Noto Serif Myanmar",
             @"NotoSerifMyanmar-Bold" : @"Noto Serif Myanmar",
             @"NotoSerifMyanmar-ExtraBold" : @"Noto Serif Myanmar",
             @"NotoSerifMyanmar-ExtraLight" : @"Noto Serif Myanmar",
             @"NotoSerifMyanmar-Light" : @"Noto Serif Myanmar",
             @"NotoSerifMyanmar-Medium" : @"Noto Serif Myanmar",
             @"NotoSerifMyanmar-Regular" : @"Noto Serif Myanmar",
             @"NotoSerifMyanmar-SemiBold" : @"Noto Serif Myanmar",
             @"NotoSerifMyanmar-Thin" : @"Noto Serif Myanmar",
             @"Optima-Bold" : @"Optima",
             @"Optima-BoldItalic" : @"Optima",
             @"Optima-ExtraBlack" : @"Optima",
             @"Optima-Italic" : @"Optima",
             @"Optima-Regular" : @"Optima",
             @"OriyaMN" : @"Oriya MN",
             @"OriyaMN-Bold" : @"Oriya MN",
             @"OriyaSangamMN" : @"Oriya Sangam MN",
             @"OriyaSangamMN-Bold" : @"Oriya Sangam MN",
             @"PTMono-Bold" : @"PT Mono",
             @"PTMono-Regular" : @"PT Mono",
             @"PTSans-Bold" : @"PT Sans",
             @"PTSans-BoldItalic" : @"PT Sans",
             @"PTSans-Caption" : @"PT Sans Caption",
             @"PTSans-CaptionBold" : @"PT Sans Caption",
             @"PTSans-Italic" : @"PT Sans",
             @"PTSans-Narrow" : @"PT Sans Narrow",
             @"PTSans-NarrowBold" : @"PT Sans Narrow",
             @"PTSans-Regular" : @"PT Sans",
             @"PTSerif-Bold" : @"PT Serif",
             @"PTSerif-BoldItalic" : @"PT Serif",
             @"PTSerif-Caption" : @"PT Serif Caption",
             @"PTSerif-CaptionItalic" : @"PT Serif Caption",
             @"PTSerif-Italic" : @"PT Serif",
             @"PTSerif-Regular" : @"PT Serif",
             @"Palatino-Bold" : @"Palatino",
             @"Palatino-BoldItalic" : @"Palatino",
             @"Palatino-Italic" : @"Palatino",
             @"Palatino-Roman" : @"Palatino",
             @"Papyrus" : @"Papyrus",
             @"Papyrus-Condensed" : @"Papyrus",
             @"Phosphate-Inline" : @"Phosphate",
             @"Phosphate-Solid" : @"Phosphate",
             @"PingFangHK-Light" : @"PingFang HK",
             @"PingFangHK-Medium" : @"PingFang HK",
             @"PingFangHK-Regular" : @"PingFang HK",
             @"PingFangHK-Semibold" : @"PingFang HK",
             @"PingFangHK-Thin" : @"PingFang HK",
             @"PingFangHK-Ultralight" : @"PingFang HK",
             @"PingFangSC-Light" : @"PingFang SC",
             @"PingFangSC-Medium" : @"PingFang SC",
             @"PingFangSC-Regular" : @"PingFang SC",
             @"PingFangSC-Semibold" : @"PingFang SC",
             @"PingFangSC-Thin" : @"PingFang SC",
             @"PingFangSC-Ultralight" : @"PingFang SC",
             @"PingFangTC-Light" : @"PingFang TC",
             @"PingFangTC-Medium" : @"PingFang TC",
             @"PingFangTC-Regular" : @"PingFang TC",
             @"PingFangTC-Semibold" : @"PingFang TC",
             @"PingFangTC-Thin" : @"PingFang TC",
             @"PingFangTC-Ultralight" : @"PingFang TC",
             @"PlantagenetCherokee" : @"Plantagenet Cherokee",
             @"Raanana" : @"Raanana",
             @"RaananaBold" : @"Raanana",
             @"Rockwell-Bold" : @"Rockwell",
             @"Rockwell-BoldItalic" : @"Rockwell",
             @"Rockwell-Italic" : @"Rockwell",
             @"Rockwell-Regular" : @"Rockwell",
             @"SFMono-Bold" : @"SF Mono",
             @"SFMono-BoldItalic" : @"SF Mono",
             @"SFMono-Regular" : @"SF Mono",
             @"SFMono-RegularItalic" : @"SF Mono",
             @"STHeitiSC-Light" : @"Heiti SC",
             @"STHeitiSC-Medium" : @"Heiti SC",
             @"STHeitiTC-Light" : @"Heiti TC",
             @"STHeitiTC-Medium" : @"Heiti TC",
             @"STIXGeneral-Bold" : @"STIXGeneral",
             @"STIXGeneral-BoldItalic" : @"STIXGeneral",
             @"STIXGeneral-Italic" : @"STIXGeneral",
             @"STIXGeneral-Regular" : @"STIXGeneral",
             @"STIXIntegralsD-Bold" : @"STIXIntegralsD",
             @"STIXIntegralsD-Regular" : @"STIXIntegralsD",
             @"STIXIntegralsSm-Bold" : @"STIXIntegralsSm",
             @"STIXIntegralsSm-Regular" : @"STIXIntegralsSm",
             @"STIXIntegralsUp-Bold" : @"STIXIntegralsUp",
             @"STIXIntegralsUp-Regular" : @"STIXIntegralsUp",
             @"STIXIntegralsUpD-Bold" : @"STIXIntegralsUpD",
             @"STIXIntegralsUpD-Regular" : @"STIXIntegralsUpD",
             @"STIXIntegralsUpSm-Bold" : @"STIXIntegralsUpSm",
             @"STIXIntegralsUpSm-Regular" : @"STIXIntegralsUpSm",
             @"STIXNonUnicode-Bold" : @"STIXNonUnicode",
             @"STIXNonUnicode-BoldItalic" : @"STIXNonUnicode",
             @"STIXNonUnicode-Italic" : @"STIXNonUnicode",
             @"STIXNonUnicode-Regular" : @"STIXNonUnicode",
             @"STIXSizeFiveSym-Regular" : @"STIXSizeFiveSym",
             @"STIXSizeFourSym-Bold" : @"STIXSizeFourSym",
             @"STIXSizeFourSym-Regular" : @"STIXSizeFourSym",
             @"STIXSizeOneSym-Bold" : @"STIXSizeOneSym",
             @"STIXSizeOneSym-Regular" : @"STIXSizeOneSym",
             @"STIXSizeThreeSym-Bold" : @"STIXSizeThreeSym",
             @"STIXSizeThreeSym-Regular" : @"STIXSizeThreeSym",
             @"STIXSizeTwoSym-Bold" : @"STIXSizeTwoSym",
             @"STIXSizeTwoSym-Regular" : @"STIXSizeTwoSym",
             @"STIXVariants-Bold" : @"STIXVariants",
             @"STIXVariants-Regular" : @"STIXVariants",
             @"STSong" : @"STSong",
             @"STSongti-SC-Black" : @"Songti SC",
             @"STSongti-SC-Bold" : @"Songti SC",
             @"STSongti-SC-Light" : @"Songti SC",
             @"STSongti-SC-Regular" : @"Songti SC",
             @"STSongti-TC-Bold" : @"Songti TC",
             @"STSongti-TC-Light" : @"Songti TC",
             @"STSongti-TC-Regular" : @"Songti TC",
             @"Sana" : @"Sana",
             @"Sathu" : @"Sathu",
             @"SavoyeLetPlain" : @"Savoye LET",
             @"Seravek" : @"Seravek",
             @"Seravek-Bold" : @"Seravek",
             @"Seravek-BoldItalic" : @"Seravek",
             @"Seravek-ExtraLight" : @"Seravek",
             @"Seravek-ExtraLightItalic" : @"Seravek",
             @"Seravek-Italic" : @"Seravek",
             @"Seravek-Light" : @"Seravek",
             @"Seravek-LightItalic" : @"Seravek",
             @"Seravek-Medium" : @"Seravek",
             @"Seravek-MediumItalic" : @"Seravek",
             @"ShreeDev0714" : @"Shree Devanagari 714",
             @"ShreeDev0714-Bold" : @"Shree Devanagari 714",
             @"ShreeDev0714-BoldItalic" : @"Shree Devanagari 714",
             @"ShreeDev0714-Italic" : @"Shree Devanagari 714",
             @"SignPainter-HouseScript" : @"SignPainter",
             @"SignPainter-HouseScriptSemibold" : @"SignPainter",
             @"Silom" : @"Silom",
             @"SinhalaMN" : @"Sinhala MN",
             @"SinhalaMN-Bold" : @"Sinhala MN",
             @"SinhalaSangamMN" : @"Sinhala Sangam MN",
             @"SinhalaSangamMN-Bold" : @"Sinhala Sangam MN",
             @"Skia-Regular" : @"Skia",
             @"Skia-Regular_Black" : @"Skia",
             @"Skia-Regular_Black-Condensed" : @"Skia",
             @"Skia-Regular_Black-Extended" : @"Skia",
             @"Skia-Regular_Bold" : @"Skia",
             @"Skia-Regular_Condensed" : @"Skia",
             @"Skia-Regular_Extended" : @"Skia",
             @"Skia-Regular_Light" : @"Skia",
             @"Skia-Regular_Light-Condensed" : @"Skia",
             @"Skia-Regular_Light-Extended" : @"Skia",
             @"SnellRoundhand" : @"Snell Roundhand",
             @"SnellRoundhand-Black" : @"Snell Roundhand",
             @"SnellRoundhand-Bold" : @"Snell Roundhand",
             @"SukhumvitSet-Bold" : @"Sukhumvit Set",
             @"SukhumvitSet-Light" : @"Sukhumvit Set",
             @"SukhumvitSet-Medium" : @"Sukhumvit Set",
             @"SukhumvitSet-SemiBold" : @"Sukhumvit Set",
             @"SukhumvitSet-Text" : @"Sukhumvit Set",
             @"SukhumvitSet-Thin" : @"Sukhumvit Set",
             @"Superclarendon-Black" : @"Superclarendon",
             @"Superclarendon-BlackItalic" : @"Superclarendon",
             @"Superclarendon-Bold" : @"Superclarendon",
             @"Superclarendon-BoldItalic" : @"Superclarendon",
             @"Superclarendon-Italic" : @"Superclarendon",
             @"Superclarendon-Light" : @"Superclarendon",
             @"Superclarendon-LightItalic" : @"Superclarendon",
             @"Superclarendon-Regular" : @"Superclarendon",
             @"Symbol" : @"Symbol",
             @"Tahoma" : @"Tahoma",
             @"Tahoma-Bold" : @"Tahoma",
             @"TamilMN" : @"Tamil MN",
             @"TamilMN-Bold" : @"Tamil MN",
             @"TamilSangamMN" : @"Tamil Sangam MN",
             @"TamilSangamMN-Bold" : @"Tamil Sangam MN",
             @"TeluguMN" : @"Telugu MN",
             @"TeluguMN-Bold" : @"Telugu MN",
             @"TeluguSangamMN" : @"Telugu Sangam MN",
             @"TeluguSangamMN-Bold" : @"Telugu Sangam MN",
             @"Thonburi" : @"Thonburi",
             @"Thonburi-Bold" : @"Thonburi",
             @"Thonburi-Light" : @"Thonburi",
             @"Times-Bold" : @"Times",
             @"Times-BoldItalic" : @"Times",
             @"Times-Italic" : @"Times",
             @"Times-Roman" : @"Times",
             @"TimesLTMM" : @".Times LT MM",
             @"TimesNewRomanPS-BoldItalicMT" : @"Times New Roman",
             @"TimesNewRomanPS-BoldMT" : @"Times New Roman",
             @"TimesNewRomanPS-ItalicMT" : @"Times New Roman",
             @"TimesNewRomanPSMT" : @"Times New Roman",
             @"Trattatello" : @"Trattatello",
             @"Trebuchet-BoldItalic" : @"Trebuchet MS",
             @"TrebuchetMS" : @"Trebuchet MS",
             @"TrebuchetMS-Bold" : @"Trebuchet MS",
             @"TrebuchetMS-Italic" : @"Trebuchet MS",
             @"Verdana" : @"Verdana",
             @"Verdana-Bold" : @"Verdana",
             @"Verdana-BoldItalic" : @"Verdana",
             @"Verdana-Italic" : @"Verdana",
             @"Waseem" : @"Waseem",
             @"WaseemLight" : @"Waseem",
             @"Webdings" : @"Webdings",
             @"Wingdings-Regular" : @"Wingdings",
             @"Wingdings2" : @"Wingdings 2",
             @"Wingdings3" : @"Wingdings 3",
             @"ZapfDingbatsITC" : @"Zapf Dingbats",
             @"Zapfino" : @"Zapfino",

             // JetBrains fonts
             @"DroidSans" : @"Droid Sans",
             @"DroidSans-Bold" : @"Droid Sans",
             @"DroidSansMono" : @"Droid Sans Mono",
             @"DroidSansMonoDotted" : @"Droid Sans Mono Dotted",
             @"DroidSansMonoSlashed" : @"Droid Sans Mono Slashed",
             @"DroidSerif" : @"Droid Serif",
             @"DroidSerif-Bold" : @"Droid Serif",
             @"DroidSerif-BoldItalic" : @"Droid Serif",
             @"DroidSerif-Italic" : @"Droid Serif",
             @"FiraCode-Bold" : @"Fira Code",
             @"FiraCode-Light" : @"Fira Code",
             @"FiraCode-Medium" : @"Fira Code",
             @"FiraCode-Regular" : @"Fira Code",
             @"FiraCode-Retina" : @"Fira Code",
             @"Inconsolata" : @"Inconsolata",
             @"JetBrainsMono-Bold" : @"JetBrains Mono",
             @"JetBrainsMono-Regular" : @"JetBrains Mono",
             @"JetBrainsMono-Italic" : @"JetBrains Mono",
             @"JetBrainsMono-BoldItalic" : @"JetBrains Mono",
             @"Roboto-Light" : @"Roboto",
             @"Roboto-Thin" : @"Roboto",
             @"SourceCodePro-Bold" : @"Source Code Pro",
             @"SourceCodePro-BoldIt" : @"Source Code Pro",
             @"SourceCodePro-It" : @"Source Code Pro",
             @"SourceCodePro-Regular" : @"Source Code Pro",
             @"Inter-Bold": @"Inter",
             @"Inter-BoldItalic": @"Inter",
             @"Inter-Italic": @"Inter",
             @"Inter-Regular": @"Inter"
             };
}

static NSDictionary* prebuiltFaceNames() {
    return @{
             @".SFNS-Black" : @"Black",
             @".SFNS-BlackItalic" : @"Black Italic",
             @".SFNS-Bold" : @"Bold",
             @".SFNS-BoldG1" : @"Bold G1",
             @".SFNS-BoldG2" : @"Bold G2",
             @".SFNS-BoldG3" : @"Bold G3",
             @".SFNS-BoldG4" : @"Bold G4",
             @".SFNS-BoldItalic" : @"Bold Italic",
             @".SFNS-Heavy" : @"Heavy",
             @".SFNS-HeavyG1" : @"Heavy G1",
             @".SFNS-HeavyG2" : @"Heavy G2",
             @".SFNS-HeavyG3" : @"Heavy G3",
             @".SFNS-HeavyG4" : @"Heavy G4",
             @".SFNS-HeavyItalic" : @"Heavy Italic",
             @".SFNS-Light" : @"Light",
             @".SFNS-LightG1" : @"Light G1",
             @".SFNS-LightG2" : @"Light G2",
             @".SFNS-LightG3" : @"Light G3",
             @".SFNS-LightG4" : @"Light G4",
             @".SFNS-LightItalic" : @"Light Italic",
             @".SFNS-Medium" : @"Medium",
             @".SFNS-MediumG1" : @"Medium G1",
             @".SFNS-MediumG2" : @"Medium G2",
             @".SFNS-MediumG3" : @"Medium G3",
             @".SFNS-MediumG4" : @"Medium G4",
             @".SFNS-MediumItalic" : @"Medium Italic",
             @".SFNS-Regular" : @"Regular",
             @".SFNS-RegularG1" : @"Regular G1",
             @".SFNS-RegularG2" : @"Regular G2",
             @".SFNS-RegularG3" : @"Regular G3",
             @".SFNS-RegularG4" : @"Regular G4",
             @".SFNS-RegularItalic" : @"Regular Italic",
             @".SFNS-Semibold" : @"Semibold",
             @".SFNS-SemiboldG1" : @"Semibold G1",
             @".SFNS-SemiboldG2" : @"Semibold G2",
             @".SFNS-SemiboldG3" : @"Semibold G3",
             @".SFNS-SemiboldG4" : @"Semibold G4",
             @".SFNS-SemiboldItalic" : @"Semibold Italic",
             @".SFNS-Thin" : @"Thin",
             @".SFNS-ThinG1" : @"Thin G1",
             @".SFNS-ThinG2" : @"Thin G2",
             @".SFNS-ThinG3" : @"Thin G3",
             @".SFNS-ThinG4" : @"Thin G4",
             @".SFNS-ThinItalic" : @"Thin Italic",
             @".SFNS-Ultralight" : @"Ultralight",
             @".SFNS-UltralightG1" : @"Ultralight G1",
             @".SFNS-UltralightG2" : @"Ultralight G2",
             @".SFNS-UltralightG3" : @"Ultralight G3",
             @".SFNS-UltralightG4" : @"Ultralight G4",
             @".SFNS-UltralightItalic" : @"Ultralight Italic",
             @".SFNS-Ultrathin" : @"Ultrathin",
             @".SFNS-UltrathinG1" : @"Ultrathin G1",
             @".SFNS-UltrathinG2" : @"Ultrathin G2",
             @".SFNS-UltrathinG3" : @"Ultrathin G3",
             @".SFNS-UltrathinG4" : @"Ultrathin G4",
             @".SFNS-UltrathinItalic" : @"Ultrathin Italic",
             @".SFNSMono-Bold" : @"Bold",
             @".SFNSMono-BoldItalic" : @"Bold Italic",
             @".SFNSMono-Heavy" : @"Heavy",
             @".SFNSMono-HeavyItalic" : @"Heavy Italic",
             @".SFNSMono-Light" : @"Light",
             @".SFNSMono-LightItalic" : @"Light Italic",
             @".SFNSMono-Medium" : @"Medium",
             @".SFNSMono-MediumItalic" : @"Medium Italic",
             @".SFNSMono-Regular" : @"Regular",
             @".SFNSMono-RegularItalic" : @"Regular Italic",
             @".SFNSMono-Semibold" : @"Semibold",
             @".SFNSMono-SemiboldItalic" : @"Semibold Italic",
             @".SFCompact-BlackItalic" : @"BlackItalic",
             @".SFCompact-Bold" : @"Bold",
             @".SFCompact-BoldG1" : @"Bold G1",
             @".SFCompact-BoldG2" : @"Bold G2",
             @".SFCompact-BoldG3" : @"Bold G3",
             @".SFCompact-BoldG4" : @"Bold G4",
             @".SFCompact-BoldItalic" : @"Bold Italic",
             @".SFCompact-BoldItalicG1" : @"Bold Italic G1",
             @".SFCompact-BoldItalicG2" : @"Bold Italic G2",
             @".SFCompact-BoldItalicG3" : @"Bold Italic G3",
             @".SFCompact-BoldItalicG4" : @"Bold Italic G4",
             @".SFCompact-Heavy" : @"Heavy",
             @".SFCompact-HeavyG1" : @"Heavy G1",
             @".SFCompact-HeavyG2" : @"Heavy G2",
             @".SFCompact-HeavyG3" : @"Heavy G3",
             @".SFCompact-HeavyG4" : @"Heavy G4",
             @".SFCompact-HeavyItalic" : @"Heavy Italic",
             @".SFCompact-HeavyItalicG1" : @"Heavy Italic G1",
             @".SFCompact-HeavyItalicG2" : @"Heavy Italic G2",
             @".SFCompact-HeavyItalicG3" : @"Heavy Italic G3",
             @".SFCompact-HeavyItalicG4" : @"Heavy Italic G4",
             @".SFCompact-Light" : @"Light",
             @".SFCompact-LightG1" : @"Light G1",
             @".SFCompact-LightG2" : @"Light G2",
             @".SFCompact-LightG3" : @"Light G3",
             @".SFCompact-LightG4" : @"Light G4",
             @".SFCompact-LightItalic" : @"Light Italic",
             @".SFCompact-LightItalicG1" : @"Light Italic G1",
             @".SFCompact-LightItalicG2" : @"Light Italic G2",
             @".SFCompact-LightItalicG3" : @"Light Italic G3",
             @".SFCompact-LightItalicG4" : @"Light Italic G4",
             @".SFCompact-Medium" : @"Medium",
             @".SFCompact-MediumG1" : @"Medium G1",
             @".SFCompact-MediumG2" : @"Medium G2",
             @".SFCompact-MediumG3" : @"Medium G3",
             @".SFCompact-MediumG4" : @"Medium G4",
             @".SFCompact-MediumItalic" : @"Medium Italic",
             @".SFCompact-MediumItalicG1" : @"Medium Italic G1",
             @".SFCompact-MediumItalicG2" : @"Medium Italic G2",
             @".SFCompact-MediumItalicG3" : @"Medium Italic G3",
             @".SFCompact-MediumItalicG4" : @"Medium Italic G4",
             @".SFCompact-Regular" : @"Regular",
             @".SFCompact-RegularG1" : @"Regular G1",
             @".SFCompact-RegularG2" : @"Regular G2",
             @".SFCompact-RegularG3" : @"Regular G3",
             @".SFCompact-RegularG4" : @"Regular G4",
             @".SFCompact-RegularItalic" : @"Regular Italic",
             @".SFCompact-RegularItalicG1" : @"Regular Italic G1",
             @".SFCompact-RegularItalicG2" : @"Regular Italic G2",
             @".SFCompact-RegularItalicG3" : @"Regular Italic G3",
             @".SFCompact-RegularItalicG4" : @"Regular Italic G4",
             @".SFCompact-Semibold" : @"Semibold",
             @".SFCompact-SemiboldG1" : @"Semibold G1",
             @".SFCompact-SemiboldG2" : @"Semibold G2",
             @".SFCompact-SemiboldG3" : @"Semibold G3",
             @".SFCompact-SemiboldG4" : @"Semibold G4",
             @".SFCompact-SemiboldItalic" : @"Semibold Italic",
             @".SFCompact-SemiboldItalicG1" : @"Semibold Italic G1",
             @".SFCompact-SemiboldItalicG2" : @"Semibold Italic G2",
             @".SFCompact-SemiboldItalicG3" : @"Semibold Italic G3",
             @".SFCompact-SemiboldItalicG4" : @"Semibold Italic G4",
             @".SFCompact-Thin" : @"Thin",
             @".SFCompact-ThinG1" : @"Thin G1",
             @".SFCompact-ThinG2" : @"Thin G2",
             @".SFCompact-ThinG3" : @"Thin G3",
             @".SFCompact-ThinG4" : @"Thin G4",
             @".SFCompact-ThinItalic" : @"Thin Italic",
             @".SFCompact-ThinItalicG1" : @"Thin Italic G1",
             @".SFCompact-ThinItalicG2" : @"Thin Italic G2",
             @".SFCompact-ThinItalicG3" : @"Thin Italic G3",
             @".SFCompact-ThinItalicG4" : @"Thin Italic G4",
             @".SFCompact-Ultralight" : @"Ultralight",
             @".SFCompact-UltralightG1" : @"Ultralight G1",
             @".SFCompact-UltralightG2" : @"Ultralight G2",
             @".SFCompact-UltralightG3" : @"Ultralight G3",
             @".SFCompact-UltralightG4" : @"Ultralight G4",
             @".SFCompact-UltralightItalic" : @"Ultralight Italic",
             @".SFCompact-UltralightItalicG1" : @"Ultralight Italic G1",
             @".SFCompact-UltralightItalicG2" : @"Ultralight Italic G2",
             @".SFCompact-UltralightItalicG3" : @"Ultralight Italic G3",
             @".SFCompact-UltralightItalicG4" : @"Ultralight Italic G4",
             @".SFNS-CompressedBlack" : @"Compressed Black",
             @".SFNS-CompressedBold" : @"Compressed Bold",
             @".SFNS-CompressedBoldG1" : @"Compressed Bold G1",
             @".SFNS-CompressedBoldG2" : @"Compressed Bold G2",
             @".SFNS-CompressedBoldG3" : @"Compressed Bold G3",
             @".SFNS-CompressedBoldG4" : @"Compressed Bold G4",
             @".SFNS-CompressedHeavy" : @"Compressed Heavy",
             @".SFNS-CompressedHeavyG1" : @"Compressed Heavy G1",
             @".SFNS-CompressedHeavyG2" : @"Compressed Heavy G2",
             @".SFNS-CompressedHeavyG3" : @"Compressed Heavy G3",
             @".SFNS-CompressedHeavyG4" : @"Compressed Heavy G4",
             @".SFNS-CompressedLight" : @"Compressed Light",
             @".SFNS-CompressedLightG1" : @"Compressed Light G1",
             @".SFNS-CompressedLightG2" : @"Compressed Light G2",
             @".SFNS-CompressedLightG3" : @"Compressed Light G3",
             @".SFNS-CompressedLightG4" : @"Compressed Light G4",
             @".SFNS-CompressedMedium" : @"Compressed Medium",
             @".SFNS-CompressedMediumG1" : @"Compressed Medium G1",
             @".SFNS-CompressedMediumG2" : @"Compressed Medium G2",
             @".SFNS-CompressedMediumG3" : @"Compressed Medium G3",
             @".SFNS-CompressedMediumG4" : @"Compressed Medium G4",
             @".SFNS-CompressedRegular" : @"Compressed Regular",
             @".SFNS-CompressedRegularG1" : @"Compressed Regular G1",
             @".SFNS-CompressedRegularG2" : @"Compressed Regular G2",
             @".SFNS-CompressedRegularG3" : @"Compressed Regular G3",
             @".SFNS-CompressedRegularG4" : @"Compressed Regular G4",
             @".SFNS-CompressedSemibold" : @"Compressed Semibold",
             @".SFNS-CompressedSemiboldG1" : @"Compressed Semibold G1",
             @".SFNS-CompressedSemiboldG2" : @"Compressed Semibold G2",
             @".SFNS-CompressedSemiboldG3" : @"Compressed Semibold G3",
             @".SFNS-CompressedSemiboldG4" : @"Compressed Semibold G4",
             @".SFNS-CompressedThin" : @"Compressed Thin",
             @".SFNS-CompressedThinG1" : @"Compressed Thin G1",
             @".SFNS-CompressedThinG2" : @"Compressed Thin G2",
             @".SFNS-CompressedThinG3" : @"Compressed Thin G3",
             @".SFNS-CompressedThinG4" : @"Compressed Thin G4",
             @".SFNS-CompressedUltralight" : @"Compressed Ultralight",
             @".SFNS-CompressedUltralightG1" : @"Compressed Ultralight G1",
             @".SFNS-CompressedUltralightG2" : @"Compressed Ultralight G2",
             @".SFNS-CompressedUltralightG3" : @"Compressed Ultralight G3",
             @".SFNS-CompressedUltralightG4" : @"Compressed Ultralight G4",
             @".SFNS-CondensedBlack" : @"Condensed Black",
             @".SFNS-CondensedBold" : @"Condensed Bold",
             @".SFNS-CondensedBoldG1" : @"Condensed Bold G1",
             @".SFNS-CondensedBoldG2" : @"Condensed Bold G2",
             @".SFNS-CondensedBoldG3" : @"Condensed Bold G3",
             @".SFNS-CondensedBoldG4" : @"Condensed Bold G4",
             @".SFNS-CondensedHeavy" : @"Condensed Heavy",
             @".SFNS-CondensedHeavyG1" : @"Condensed Heavy G1",
             @".SFNS-CondensedHeavyG2" : @"Condensed Heavy G2",
             @".SFNS-CondensedHeavyG3" : @"Condensed Heavy G3",
             @".SFNS-CondensedHeavyG4" : @"Condensed Heavy G4",
             @".SFNS-CondensedLight" : @"Condensed Light",
             @".SFNS-CondensedLightG1" : @"Condensed Light G1",
             @".SFNS-CondensedLightG2" : @"Condensed Light G2",
             @".SFNS-CondensedLightG3" : @"Condensed Light G3",
             @".SFNS-CondensedLightG4" : @"Condensed Light G4",
             @".SFNS-CondensedMedium" : @"Condensed Medium",
             @".SFNS-CondensedMediumG1" : @"Condensed Medium G1",
             @".SFNS-CondensedMediumG2" : @"Condensed Medium G2",
             @".SFNS-CondensedMediumG3" : @"Condensed Medium G3",
             @".SFNS-CondensedMediumG4" : @"Condensed Medium G4",
             @".SFNS-CondensedRegular" : @"Condensed Regular",
             @".SFNS-CondensedRegularG1" : @"Condensed Regular G1",
             @".SFNS-CondensedRegularG2" : @"Condensed Regular G2",
             @".SFNS-CondensedRegularG3" : @"Condensed Regular G3",
             @".SFNS-CondensedRegularG4" : @"Condensed Regular G4",
             @".SFNS-CondensedSemibold" : @"Condensed Semibold",
             @".SFNS-CondensedSemiboldG1" : @"Condensed Semibold G1",
             @".SFNS-CondensedSemiboldG2" : @"Condensed Semibold G2",
             @".SFNS-CondensedSemiboldG3" : @"Condensed Semibold G3",
             @".SFNS-CondensedSemiboldG4" : @"Condensed Semibold G4",
             @".SFNS-CondensedThin" : @"Condensed Thin",
             @".SFNS-CondensedThinG1" : @"Condensed Thin G1",
             @".SFNS-CondensedThinG2" : @"Condensed Thin G2",
             @".SFNS-CondensedThinG3" : @"Condensed Thin G3",
             @".SFNS-CondensedThinG4" : @"Condensed Thin G4",
             @".SFNS-CondensedUltralight" : @"Condensed Ultralight",
             @".SFNS-CondensedUltralightG1" : @"Condensed Ultralight G1",
             @".SFNS-CondensedUltralightG2" : @"Condensed Ultralight G2",
             @".SFNS-CondensedUltralightG3" : @"Condensed Ultralight G3",
             @".SFNS-CondensedUltralightG4" : @"Condensed Ultralight G4",
             @".SFNS-ExpandedBlack" : @"Expanded Black",
             @".SFNS-ExpandedBold" : @"Expanded Bold",
             @".SFNS-ExpandedBoldG1" : @"Expanded Bold G1",
             @".SFNS-ExpandedBoldG2" : @"Expanded Bold G2",
             @".SFNS-ExpandedBoldG3" : @"Expanded Bold G3",
             @".SFNS-ExpandedBoldG4" : @"Expanded Bold G4",
             @".SFNS-ExpandedHeavy" : @"Expanded Heavy",
             @".SFNS-ExpandedHeavyG1" : @"Expanded Heavy G1",
             @".SFNS-ExpandedHeavyG2" : @"Expanded Heavy G2",
             @".SFNS-ExpandedHeavyG3" : @"Expanded Heavy G3",
             @".SFNS-ExpandedHeavyG4" : @"Expanded Heavy G4",
             @".SFNS-ExpandedLight" : @"Expanded Light",
             @".SFNS-ExpandedLightG1" : @"Expanded Light G1",
             @".SFNS-ExpandedLightG2" : @"Expanded Light G2",
             @".SFNS-ExpandedLightG3" : @"Expanded Light G3",
             @".SFNS-ExpandedLightG4" : @"Expanded Light G4",
             @".SFNS-ExpandedMedium" : @"Expanded Medium",
             @".SFNS-ExpandedMediumG1" : @"Expanded Medium G1",
             @".SFNS-ExpandedMediumG2" : @"Expanded Medium G2",
             @".SFNS-ExpandedMediumG3" : @"Expanded Medium G3",
             @".SFNS-ExpandedMediumG4" : @"Expanded Medium G4",
             @".SFNS-ExpandedRegular" : @"Expanded Regular",
             @".SFNS-ExpandedRegularG1" : @"Expanded Regular G1",
             @".SFNS-ExpandedRegularG2" : @"Expanded Regular G2",
             @".SFNS-ExpandedRegularG3" : @"Expanded Regular G3",
             @".SFNS-ExpandedRegularG4" : @"Expanded Regular G4",
             @".SFNS-ExpandedSemibold" : @"Expanded Semibold",
             @".SFNS-ExpandedSemiboldG1" : @"Expanded Semibold G1",
             @".SFNS-ExpandedSemiboldG2" : @"Expanded Semibold G2",
             @".SFNS-ExpandedSemiboldG3" : @"Expanded Semibold G3",
             @".SFNS-ExpandedSemiboldG4" : @"Expanded Semibold G4",
             @".SFNS-ExpandedThin" : @"Expanded Thin",
             @".SFNS-ExpandedThinG1" : @"Expanded Thin G1",
             @".SFNS-ExpandedThinG2" : @"Expanded Thin G2",
             @".SFNS-ExpandedThinG3" : @"Expanded Thin G3",
             @".SFNS-ExpandedThinG4" : @"Expanded Thin G4",
             @".SFNS-ExpandedUltralight" : @"Expanded Ultralight",
             @".SFNS-ExpandedUltralightG1" : @"Expanded Ultralight G1",
             @".SFNS-ExpandedUltralightG2" : @"Expanded Ultralight G2",
             @".SFNS-ExpandedUltralightG3" : @"Expanded Ultralight G3",
             @".SFNS-ExpandedUltralightG4" : @"Expanded Ultralight G4",
             @".SFNS-ExtraCompressedBlack" : @"ExtraCompressed Black",
             @".SFNS-ExtraCompressedBold" : @"ExtraCompressed Bold",
             @".SFNS-ExtraCompressedBoldG1" : @"ExtraCompressed Bold G1",
             @".SFNS-ExtraCompressedBoldG2" : @"ExtraCompressed Bold G2",
             @".SFNS-ExtraCompressedBoldG3" : @"ExtraCompressed Bold G3",
             @".SFNS-ExtraCompressedBoldG4" : @"ExtraCompressed Bold G4",
             @".SFNS-ExtraCompressedHeavy" : @"ExtraCompressed Heavy",
             @".SFNS-ExtraCompressedHeavyG1" : @"ExtraCompressed Heavy G1",
             @".SFNS-ExtraCompressedHeavyG2" : @"ExtraCompressed Heavy G2",
             @".SFNS-ExtraCompressedHeavyG3" : @"ExtraCompressed Heavy G3",
             @".SFNS-ExtraCompressedHeavyG4" : @"ExtraCompressed Heavy G4",
             @".SFNS-ExtraCompressedLight" : @"ExtraCompressed Light",
             @".SFNS-ExtraCompressedLightG1" : @"ExtraCompressed Light G1",
             @".SFNS-ExtraCompressedLightG2" : @"ExtraCompressed Light G2",
             @".SFNS-ExtraCompressedLightG3" : @"ExtraCompressed Light G3",
             @".SFNS-ExtraCompressedLightG4" : @"ExtraCompressed Light G4",
             @".SFNS-ExtraCompressedMedium" : @"ExtraCompressed Medium",
             @".SFNS-ExtraCompressedMediumG1" : @"ExtraCompressed Medium G1",
             @".SFNS-ExtraCompressedMediumG2" : @"ExtraCompressed Medium G2",
             @".SFNS-ExtraCompressedMediumG3" : @"ExtraCompressed Medium G3",
             @".SFNS-ExtraCompressedMediumG4" : @"ExtraCompressed Medium G4",
             @".SFNS-ExtraCompressedRegular" : @"ExtraCompressed Regular",
             @".SFNS-ExtraCompressedRegularG1" : @"ExtraCompressed Regular G1",
             @".SFNS-ExtraCompressedRegularG2" : @"ExtraCompressed Regular G2",
             @".SFNS-ExtraCompressedRegularG3" : @"ExtraCompressed Regular G3",
             @".SFNS-ExtraCompressedRegularG4" : @"ExtraCompressed Regular G4",
             @".SFNS-ExtraCompressedSemibold" : @"ExtraCompressed Semibold",
             @".SFNS-ExtraCompressedSemiboldG1" : @"ExtraCompressed Semibold G1",
             @".SFNS-ExtraCompressedSemiboldG2" : @"ExtraCompressed Semibold G2",
             @".SFNS-ExtraCompressedSemiboldG3" : @"ExtraCompressed Semibold G3",
             @".SFNS-ExtraCompressedSemiboldG4" : @"ExtraCompressed Semibold G4",
             @".SFNS-ExtraCompressedThin" : @"ExtraCompressed Thin",
             @".SFNS-ExtraCompressedThinG1" : @"ExtraCompressed Thin G1",
             @".SFNS-ExtraCompressedThinG2" : @"ExtraCompressed Thin G2",
             @".SFNS-ExtraCompressedThinG3" : @"ExtraCompressed Thin G3",
             @".SFNS-ExtraCompressedThinG4" : @"ExtraCompressed Thin G4",
             @".SFNS-ExtraCompressedUltralight" : @"ExtraCompressed Ultralight",
             @".SFNS-ExtraCompressedUltralightG1" : @"ExtraCompressed Ultralight G1",
             @".SFNS-ExtraCompressedUltralightG2" : @"ExtraCompressed Ultralight G2",
             @".SFNS-ExtraCompressedUltralightG3" : @"ExtraCompressed Ultralight G3",
             @".SFNS-ExtraCompressedUltralightG4" : @"ExtraCompressed Ultralight G4",
             @".SFNS-ExtraExpandedBlack" : @"ExtraExpanded Black",
             @".SFNS-ExtraExpandedBold" : @"ExtraExpanded Bold",
             @".SFNS-ExtraExpandedBoldG1" : @"ExtraExpanded Bold G1",
             @".SFNS-ExtraExpandedBoldG2" : @"ExtraExpanded Bold G2",
             @".SFNS-ExtraExpandedBoldG3" : @"ExtraExpanded Bold G3",
             @".SFNS-ExtraExpandedBoldG4" : @"ExtraExpanded Bold G4",
             @".SFNS-ExtraExpandedHeavy" : @"ExtraExpanded Heavy",
             @".SFNS-ExtraExpandedHeavyG1" : @"ExtraExpanded Heavy G1",
             @".SFNS-ExtraExpandedHeavyG2" : @"ExtraExpanded Heavy G2",
             @".SFNS-ExtraExpandedHeavyG3" : @"ExtraExpanded Heavy G3",
             @".SFNS-ExtraExpandedHeavyG4" : @"ExtraExpanded Heavy G4",
             @".SFNS-ExtraExpandedLight" : @"ExtraExpanded Light",
             @".SFNS-ExtraExpandedLightG1" : @"ExtraExpanded Light G1",
             @".SFNS-ExtraExpandedLightG2" : @"ExtraExpanded Light G2",
             @".SFNS-ExtraExpandedLightG3" : @"ExtraExpanded Light G3",
             @".SFNS-ExtraExpandedLightG4" : @"ExtraExpanded Light G4",
             @".SFNS-ExtraExpandedMedium" : @"ExtraExpanded Medium",
             @".SFNS-ExtraExpandedMediumG1" : @"ExtraExpanded Medium G1",
             @".SFNS-ExtraExpandedMediumG2" : @"ExtraExpanded Medium G2",
             @".SFNS-ExtraExpandedMediumG3" : @"ExtraExpanded Medium G3",
             @".SFNS-ExtraExpandedMediumG4" : @"ExtraExpanded Medium G4",
             @".SFNS-ExtraExpandedRegular" : @"ExtraExpanded Regular",
             @".SFNS-ExtraExpandedRegularG1" : @"ExtraExpanded Regular G1",
             @".SFNS-ExtraExpandedRegularG2" : @"ExtraExpanded Regular G2",
             @".SFNS-ExtraExpandedRegularG3" : @"ExtraExpanded Regular G3",
             @".SFNS-ExtraExpandedRegularG4" : @"ExtraExpanded Regular G4",
             @".SFNS-ExtraExpandedSemibold" : @"ExtraExpanded Semibold",
             @".SFNS-ExtraExpandedSemiboldG1" : @"ExtraExpanded Semibold G1",
             @".SFNS-ExtraExpandedSemiboldG2" : @"ExtraExpanded Semibold G2",
             @".SFNS-ExtraExpandedSemiboldG3" : @"ExtraExpanded Semibold G3",
             @".SFNS-ExtraExpandedSemiboldG4" : @"ExtraExpanded Semibold G4",
             @".SFNS-ExtraExpandedThin" : @"ExtraExpanded Thin",
             @".SFNS-ExtraExpandedThinG1" : @"ExtraExpanded Thin G1",
             @".SFNS-ExtraExpandedThinG2" : @"ExtraExpanded Thin G2",
             @".SFNS-ExtraExpandedThinG3" : @"ExtraExpanded Thin G3",
             @".SFNS-ExtraExpandedThinG4" : @"ExtraExpanded Thin G4",
             @".SFNS-ExtraExpandedUltralight" : @"ExtraExpanded Ultralight",
             @".SFNS-ExtraExpandedUltralightG1" : @"ExtraExpanded Ultralight G1",
             @".SFNS-ExtraExpandedUltralightG2" : @"ExtraExpanded Ultralight G2",
             @".SFNS-ExtraExpandedUltralightG3" : @"ExtraExpanded Ultralight G3",
             @".SFNS-ExtraExpandedUltralightG4" : @"ExtraExpanded Ultralight G4",
             @".SFNS-SemiCondensedBlack" : @"SemiCondensed Black",
             @".SFNS-SemiCondensedBold" : @"SemiCondensed Bold",
             @".SFNS-SemiCondensedBoldG1" : @"SemiCondensed Bold G1",
             @".SFNS-SemiCondensedBoldG2" : @"SemiCondensed Bold G2",
             @".SFNS-SemiCondensedBoldG3" : @"SemiCondensed Bold G3",
             @".SFNS-SemiCondensedBoldG4" : @"SemiCondensed Bold G4",
             @".SFNS-SemiCondensedHeavy" : @"SemiCondensed Heavy",
             @".SFNS-SemiCondensedHeavyG1" : @"SemiCondensed Heavy G1",
             @".SFNS-SemiCondensedHeavyG2" : @"SemiCondensed Heavy G2",
             @".SFNS-SemiCondensedHeavyG3" : @"SemiCondensed Heavy G3",
             @".SFNS-SemiCondensedHeavyG4" : @"SemiCondensed Heavy G4",
             @".SFNS-SemiCondensedLight" : @"SemiCondensed Light",
             @".SFNS-SemiCondensedLightG1" : @"SemiCondensed Light G1",
             @".SFNS-SemiCondensedLightG2" : @"SemiCondensed Light G2",
             @".SFNS-SemiCondensedLightG3" : @"SemiCondensed Light G3",
             @".SFNS-SemiCondensedLightG4" : @"SemiCondensed Light G4",
             @".SFNS-SemiCondensedMedium" : @"SemiCondensed Medium",
             @".SFNS-SemiCondensedMediumG1" : @"SemiCondensed Medium G1",
             @".SFNS-SemiCondensedMediumG2" : @"SemiCondensed Medium G2",
             @".SFNS-SemiCondensedMediumG3" : @"SemiCondensed Medium G3",
             @".SFNS-SemiCondensedMediumG4" : @"SemiCondensed Medium G4",
             @".SFNS-SemiCondensedRegular" : @"SemiCondensed Regular",
             @".SFNS-SemiCondensedRegularG1" : @"SemiCondensed Regular G1",
             @".SFNS-SemiCondensedRegularG2" : @"SemiCondensed Regular G2",
             @".SFNS-SemiCondensedRegularG3" : @"SemiCondensed Regular G3",
             @".SFNS-SemiCondensedRegularG4" : @"SemiCondensed Regular G4",
             @".SFNS-SemiCondensedSemibold" : @"SemiCondensed Semibold",
             @".SFNS-SemiCondensedSemiboldG1" : @"SemiCondensed Semibold G1",
             @".SFNS-SemiCondensedSemiboldG2" : @"SemiCondensed Semibold G2",
             @".SFNS-SemiCondensedSemiboldG3" : @"SemiCondensed Semibold G3",
             @".SFNS-SemiCondensedSemiboldG4" : @"SemiCondensed Semibold G4",
             @".SFNS-SemiCondensedThin" : @"SemiCondensed Thin",
             @".SFNS-SemiCondensedThinG1" : @"SemiCondensed Thin G1",
             @".SFNS-SemiCondensedThinG2" : @"SemiCondensed Thin G2",
             @".SFNS-SemiCondensedThinG3" : @"SemiCondensed Thin G3",
             @".SFNS-SemiCondensedThinG4" : @"SemiCondensed Thin G4",
             @".SFNS-SemiCondensedUltralight" : @"SemiCondensed Ultralight",
             @".SFNS-SemiCondensedUltralightG1" : @"SemiCondensed Ultralight G1",
             @".SFNS-SemiCondensedUltralightG2" : @"SemiCondensed Ultralight G2",
             @".SFNS-SemiCondensedUltralightG3" : @"SemiCondensed Ultralight G3",
             @".SFNS-SemiCondensedUltralightG4" : @"SemiCondensed Ultralight G4",
             @".SFNS-SemiExpandedBlack" : @"SemiExpanded Black",
             @".SFNS-SemiExpandedBold" : @"SemiExpanded Bold",
             @".SFNS-SemiExpandedBoldG1" : @"SemiExpanded Bold G1",
             @".SFNS-SemiExpandedBoldG2" : @"SemiExpanded Bold G2",
             @".SFNS-SemiExpandedBoldG3" : @"SemiExpanded Bold G3",
             @".SFNS-SemiExpandedBoldG4" : @"SemiExpanded Bold G4",
             @".SFNS-SemiExpandedHeavy" : @"SemiExpanded Heavy",
             @".SFNS-SemiExpandedHeavyG1" : @"SemiExpanded Heavy G1",
             @".SFNS-SemiExpandedHeavyG2" : @"SemiExpanded Heavy G2",
             @".SFNS-SemiExpandedHeavyG3" : @"SemiExpanded Heavy G3",
             @".SFNS-SemiExpandedHeavyG4" : @"SemiExpanded Heavy G4",
             @".SFNS-SemiExpandedLight" : @"SemiExpanded Light",
             @".SFNS-SemiExpandedLightG1" : @"SemiExpanded Light G1",
             @".SFNS-SemiExpandedLightG2" : @"SemiExpanded Light G2",
             @".SFNS-SemiExpandedLightG3" : @"SemiExpanded Light G3",
             @".SFNS-SemiExpandedLightG4" : @"SemiExpanded Light G4",
             @".SFNS-SemiExpandedMedium" : @"SemiExpanded Medium",
             @".SFNS-SemiExpandedMediumG1" : @"SemiExpanded Medium G1",
             @".SFNS-SemiExpandedMediumG2" : @"SemiExpanded Medium G2",
             @".SFNS-SemiExpandedMediumG3" : @"SemiExpanded Medium G3",
             @".SFNS-SemiExpandedMediumG4" : @"SemiExpanded Medium G4",
             @".SFNS-SemiExpandedRegular" : @"SemiExpanded Regular",
             @".SFNS-SemiExpandedRegularG1" : @"SemiExpanded Regular G1",
             @".SFNS-SemiExpandedRegularG2" : @"SemiExpanded Regular G2",
             @".SFNS-SemiExpandedRegularG3" : @"SemiExpanded Regular G3",
             @".SFNS-SemiExpandedRegularG4" : @"SemiExpanded Regular G4",
             @".SFNS-SemiExpandedSemibold" : @"SemiExpanded Semibold",
             @".SFNS-SemiExpandedSemiboldG1" : @"SemiExpanded Semibold G1",
             @".SFNS-SemiExpandedSemiboldG2" : @"SemiExpanded Semibold G2",
             @".SFNS-SemiExpandedSemiboldG3" : @"SemiExpanded Semibold G3",
             @".SFNS-SemiExpandedSemiboldG4" : @"SemiExpanded Semibold G4",
             @".SFNS-SemiExpandedThin" : @"SemiExpanded Thin",
             @".SFNS-SemiExpandedThinG1" : @"SemiExpanded Thin G1",
             @".SFNS-SemiExpandedThinG2" : @"SemiExpanded Thin G2",
             @".SFNS-SemiExpandedThinG3" : @"SemiExpanded Thin G3",
             @".SFNS-SemiExpandedThinG4" : @"SemiExpanded Thin G4",
             @".SFNS-SemiExpandedUltralight" : @"SemiExpanded Ultralight",
             @".SFNS-SemiExpandedUltralightG1" : @"SemiExpanded Ultralight G1",
             @".SFNS-SemiExpandedUltralightG2" : @"SemiExpanded Ultralight G2",
             @".SFNS-SemiExpandedUltralightG3" : @"SemiExpanded Ultralight G3",
             @".SFNS-SemiExpandedUltralightG4" : @"SemiExpanded Ultralight G4",
             @".SFNS-UltraCompressedBlack" : @"UltraCompressed Black",
             @".SFNS-UltraCompressedBold" : @"UltraCompressed Bold",
             @".SFNS-UltraCompressedBoldG1" : @"UltraCompressed Bold G1",
             @".SFNS-UltraCompressedBoldG2" : @"UltraCompressed Bold G2",
             @".SFNS-UltraCompressedBoldG3" : @"UltraCompressed Bold G3",
             @".SFNS-UltraCompressedBoldG4" : @"UltraCompressed Bold G4",
             @".SFNS-UltraCompressedHeavy" : @"UltraCompressed Heavy",
             @".SFNS-UltraCompressedHeavyG1" : @"UltraCompressed Heavy G1",
             @".SFNS-UltraCompressedHeavyG2" : @"UltraCompressed Heavy G2",
             @".SFNS-UltraCompressedHeavyG3" : @"UltraCompressed Heavy G3",
             @".SFNS-UltraCompressedHeavyG4" : @"UltraCompressed Heavy G4",
             @".SFNS-UltraCompressedLight" : @"UltraCompressed Light",
             @".SFNS-UltraCompressedLightG1" : @"UltraCompressed Light G1",
             @".SFNS-UltraCompressedLightG2" : @"UltraCompressed Light G2",
             @".SFNS-UltraCompressedLightG3" : @"UltraCompressed Light G3",
             @".SFNS-UltraCompressedLightG4" : @"UltraCompressed Light G4",
             @".SFNS-UltraCompressedMedium" : @"UltraCompressed Medium",
             @".SFNS-UltraCompressedMediumG1" : @"UltraCompressed Medium G1",
             @".SFNS-UltraCompressedMediumG2" : @"UltraCompressed Medium G2",
             @".SFNS-UltraCompressedMediumG3" : @"UltraCompressed Medium G3",
             @".SFNS-UltraCompressedMediumG4" : @"UltraCompressed Medium G4",
             @".SFNS-UltraCompressedRegular" : @"UltraCompressed Regular",
             @".SFNS-UltraCompressedRegularG1" : @"UltraCompressed Regular G1",
             @".SFNS-UltraCompressedRegularG2" : @"UltraCompressed Regular G2",
             @".SFNS-UltraCompressedRegularG3" : @"UltraCompressed Regular G3",
             @".SFNS-UltraCompressedRegularG4" : @"UltraCompressed Regular G4",
             @".SFNS-UltraCompressedSemibold" : @"UltraCompressed Semibold",
             @".SFNS-UltraCompressedSemiboldG1" : @"UltraCompressed Semibold G1",
             @".SFNS-UltraCompressedSemiboldG2" : @"UltraCompressed Semibold G2",
             @".SFNS-UltraCompressedSemiboldG3" : @"UltraCompressed Semibold G3",
             @".SFNS-UltraCompressedSemiboldG4" : @"UltraCompressed Semibold G4",
             @".SFNS-UltraCompressedThin" : @"UltraCompressed Thin",
             @".SFNS-UltraCompressedThinG1" : @"UltraCompressed Thin G1",
             @".SFNS-UltraCompressedThinG2" : @"UltraCompressed Thin G2",
             @".SFNS-UltraCompressedThinG3" : @"UltraCompressed Thin G3",
             @".SFNS-UltraCompressedThinG4" : @"UltraCompressed Thin G4",
             @".SFNS-UltraCompressedUltralight" : @"UltraCompressed Ultralight",
             @".SFNS-UltraCompressedUltralightG1" : @"UltraCompressed Ultralight G1",
             @".SFNS-UltraCompressedUltralightG2" : @"UltraCompressed Ultralight G2",
             @".SFNS-UltraCompressedUltralightG3" : @"UltraCompressed Ultralight G3",
             @".SFNS-UltraCompressedUltralightG4" : @"UltraCompressed Ultralight G4",
             @".Keyboard" : @"Regular",
             @"AlBayan" : @"Plain",
             @"AlBayan-Bold" : @"Bold",
             @"AlNile" : @"Regular",
             @"AlNile-Bold" : @"Bold",
             @"AlTarikh" : @"Regular",
             @"AmericanTypewriter" : @"Regular",
             @"AmericanTypewriter-Bold" : @"Bold",
             @"AmericanTypewriter-Condensed" : @"Condensed",
             @"AmericanTypewriter-CondensedBold" : @"Condensed Bold",
             @"AmericanTypewriter-CondensedLight" : @"Condensed Light",
             @"AmericanTypewriter-Light" : @"Light",
             @"AmericanTypewriter-Semibold" : @"Semibold",
             @"AndaleMono" : @"Regular",
             @"Apple-Chancery" : @"Chancery",
             @"AppleBraille" : @"Regular",
             @"AppleBraille-Outline6Dot" : @"Outline 6 Dot",
             @"AppleBraille-Outline8Dot" : @"Outline 8 Dot",
             @"AppleBraille-Pinpoint6Dot" : @"Pinpoint 6 Dot",
             @"AppleBraille-Pinpoint8Dot" : @"Pinpoint 8 Dot",
             @"AppleColorEmoji" : @"Regular",
             @"AppleGothic" : @"Regular",
             @"AppleMyungjo" : @"Regular",
             @"AppleSDGothicNeo-Bold" : @"Bold",
             @"AppleSDGothicNeo-ExtraBold" : @"ExtraBold",
             @"AppleSDGothicNeo-Heavy" : @"Heavy",
             @"AppleSDGothicNeo-Light" : @"Light",
             @"AppleSDGothicNeo-Medium" : @"Medium",
             @"AppleSDGothicNeo-Regular" : @"Regular",
             @"AppleSDGothicNeo-SemiBold" : @"SemiBold",
             @"AppleSDGothicNeo-Thin" : @"Thin",
             @"AppleSDGothicNeo-UltraLight" : @"UltraLight",
             @"AppleSymbols" : @"Regular",
             @"AquaKana" : @"Regular",
             @"AquaKana-Bold" : @"Bold",
             @"Arial-Black" : @"Regular",
             @"Arial-BoldItalicMT" : @"Bold Italic",
             @"Arial-BoldMT" : @"Bold",
             @"Arial-ItalicMT" : @"Italic",
             @"ArialHebrew" : @"Regular",
             @"ArialHebrew-Bold" : @"Bold",
             @"ArialHebrew-Light" : @"Light",
             @"ArialHebrewScholar" : @"Regular",
             @"ArialHebrewScholar-Bold" : @"Bold",
             @"ArialHebrewScholar-Light" : @"Light",
             @"ArialMT" : @"Regular",
             @"ArialNarrow" : @"Regular",
             @"ArialNarrow-Bold" : @"Bold",
             @"ArialNarrow-BoldItalic" : @"Bold Italic",
             @"ArialNarrow-Italic" : @"Italic",
             @"ArialRoundedMTBold" : @"Regular",
             @"ArialUnicodeMS" : @"Regular",
             @"Athelas-Bold" : @"Bold",
             @"Athelas-BoldItalic" : @"Bold Italic",
             @"Athelas-Italic" : @"Italic",
             @"Athelas-Regular" : @"Regular",
             @"Avenir-Black" : @"Black",
             @"Avenir-BlackOblique" : @"Black Oblique",
             @"Avenir-Book" : @"Book",
             @"Avenir-BookOblique" : @"Book Oblique",
             @"Avenir-Heavy" : @"Heavy",
             @"Avenir-HeavyOblique" : @"Heavy Oblique",
             @"Avenir-Light" : @"Light",
             @"Avenir-LightOblique" : @"Light Oblique",
             @"Avenir-Medium" : @"Medium",
             @"Avenir-MediumOblique" : @"Medium Oblique",
             @"Avenir-Oblique" : @"Oblique",
             @"Avenir-Roman" : @"Roman",
             @"AvenirNext-Bold" : @"Bold",
             @"AvenirNext-BoldItalic" : @"Bold Italic",
             @"AvenirNext-DemiBold" : @"Demi Bold",
             @"AvenirNext-DemiBoldItalic" : @"Demi Bold Italic",
             @"AvenirNext-Heavy" : @"Heavy",
             @"AvenirNext-HeavyItalic" : @"Heavy Italic",
             @"AvenirNext-Italic" : @"Italic",
             @"AvenirNext-Medium" : @"Medium",
             @"AvenirNext-MediumItalic" : @"Medium Italic",
             @"AvenirNext-Regular" : @"Regular",
             @"AvenirNext-UltraLight" : @"Ultra Light",
             @"AvenirNext-UltraLightItalic" : @"Ultra Light Italic",
             @"AvenirNextCondensed-Bold" : @"Bold",
             @"AvenirNextCondensed-BoldItalic" : @"Bold Italic",
             @"AvenirNextCondensed-DemiBold" : @"Demi Bold",
             @"AvenirNextCondensed-DemiBoldItalic" : @"Demi Bold Italic",
             @"AvenirNextCondensed-Heavy" : @"Heavy",
             @"AvenirNextCondensed-HeavyItalic" : @"Heavy Italic",
             @"AvenirNextCondensed-Italic" : @"Italic",
             @"AvenirNextCondensed-Medium" : @"Medium",
             @"AvenirNextCondensed-MediumItalic" : @"Medium Italic",
             @"AvenirNextCondensed-Regular" : @"Regular",
             @"AvenirNextCondensed-UltraLight" : @"Ultra Light",
             @"AvenirNextCondensed-UltraLightItalic" : @"Ultra Light Italic",
             @"Ayuthaya" : @"Regular",
             @"Baghdad" : @"Regular",
             @"BanglaMN" : @"Regular",
             @"BanglaMN-Bold" : @"Bold",
             @"BanglaSangamMN" : @"Regular",
             @"BanglaSangamMN-Bold" : @"Bold",
             @"Baskerville" : @"Regular",
             @"Baskerville-Bold" : @"Bold",
             @"Baskerville-BoldItalic" : @"Bold Italic",
             @"Baskerville-Italic" : @"Italic",
             @"Baskerville-SemiBold" : @"SemiBold",
             @"Baskerville-SemiBoldItalic" : @"SemiBold Italic",
             @"Beirut" : @"Regular",
             @"BigCaslon-Medium" : @"Medium",
             @"BodoniOrnamentsITCTT" : @"Regular",
             @"BodoniSvtyTwoITCTT-Bold" : @"Bold",
             @"BodoniSvtyTwoITCTT-Book" : @"Book",
             @"BodoniSvtyTwoITCTT-BookIta" : @"Book Italic",
             @"BodoniSvtyTwoOSITCTT-Bold" : @"Bold",
             @"BodoniSvtyTwoOSITCTT-Book" : @"Book",
             @"BodoniSvtyTwoOSITCTT-BookIt" : @"Book Italic",
             @"BodoniSvtyTwoSCITCTT-Book" : @"Book",
             @"BradleyHandITCTT-Bold" : @"Bold",
             @"BrushScriptMT" : @"Italic",
             @"Chalkboard" : @"Regular",
             @"Chalkboard-Bold" : @"Bold",
             @"ChalkboardSE-Bold" : @"Bold",
             @"ChalkboardSE-Light" : @"Light",
             @"ChalkboardSE-Regular" : @"Regular",
             @"Chalkduster" : @"Regular",
             @"Charter-Black" : @"Black",
             @"Charter-BlackItalic" : @"Black Italic",
             @"Charter-Bold" : @"Bold",
             @"Charter-BoldItalic" : @"Bold Italic",
             @"Charter-Italic" : @"Italic",
             @"Charter-Roman" : @"Roman",
             @"Cochin" : @"Regular",
             @"Cochin-Bold" : @"Bold",
             @"Cochin-BoldItalic" : @"Bold Italic",
             @"Cochin-Italic" : @"Italic",
             @"ComicSansMS" : @"Regular",
             @"ComicSansMS-Bold" : @"Bold",
             @"Copperplate" : @"Regular",
             @"Copperplate-Bold" : @"Bold",
             @"Copperplate-Light" : @"Light",
             @"CorsivaHebrew" : @"Regular",
             @"CorsivaHebrew-Bold" : @"Bold",
             @"Courier" : @"Regular",
             @"Courier-Bold" : @"Bold",
             @"Courier-BoldOblique" : @"Bold Oblique",
             @"Courier-Oblique" : @"Oblique",
             @"CourierNewPS-BoldItalicMT" : @"Bold Italic",
             @"CourierNewPS-BoldMT" : @"Bold",
             @"CourierNewPS-ItalicMT" : @"Italic",
             @"CourierNewPSMT" : @"Regular",
             @"DFKaiShu-SB-Estd-BF" : @"Regular",
             @"DFWaWaSC-W5" : @"Regular",
             @"DFWaWaTC-W5" : @"Regular",
             @"DINAlternate-Bold" : @"Bold",
             @"DINCondensed-Bold" : @"Bold",
             @"Damascus" : @"Regular",
             @"DamascusBold" : @"Bold",
             @"DamascusLight" : @"Light",
             @"DamascusMedium" : @"Medium",
             @"DamascusSemiBold" : @"Semi Bold",
             @"DecoTypeNaskh" : @"Regular",
             @"DevanagariMT" : @"Regular",
             @"DevanagariMT-Bold" : @"Bold",
             @"DevanagariSangamMN" : @"Regular",
             @"DevanagariSangamMN-Bold" : @"Bold",
             @"Didot" : @"Regular",
             @"Didot-Bold" : @"Bold",
             @"Didot-Italic" : @"Italic",
             @"DiwanKufi" : @"Regular",
             @"DiwanMishafi" : @"Regular",
             @"DiwanMishafiGold" : @"Regular",
             @"DiwanThuluth" : @"Regular",
             @"EuphemiaUCAS" : @"Regular",
             @"EuphemiaUCAS-Bold" : @"Bold",
             @"EuphemiaUCAS-Italic" : @"Italic",
             @"FZLTTHB--B51-0" : @"Heavy",
             @"FZLTTHK--GBK1-0" : @"Heavy",
             @"FZLTXHB--B51-0" : @"Extralight",
             @"FZLTXHK--GBK1-0" : @"Extralight",
             @"FZLTZHB--B51-0" : @"Demibold",
             @"FZLTZHK--GBK1-0" : @"Demibold",
             @"Farah" : @"Regular",
             @"Farisi" : @"Regular",
             @"Futura-Bold" : @"Bold",
             @"Futura-CondensedExtraBold" : @"Condensed ExtraBold",
             @"Futura-CondensedMedium" : @"Condensed Medium",
             @"Futura-Medium" : @"Medium",
             @"Futura-MediumItalic" : @"Medium Italic",
             @"GB18030Bitmap" : @"Regular",
             @"Galvji" : @"Regular",
             @"Galvji-Bold" : @"Bold",
             @"Galvji-BoldOblique" : @"Bold Oblique",
             @"Galvji-Oblique" : @"Oblique",
             @"GeezaPro" : @"Regular",
             @"GeezaPro-Bold" : @"Bold",
             @"Geneva" : @"Regular",
             @"Georgia" : @"Regular",
             @"Georgia-Bold" : @"Bold",
             @"Georgia-BoldItalic" : @"Bold Italic",
             @"Georgia-Italic" : @"Italic",
             @"GillSans" : @"Regular",
             @"GillSans-Bold" : @"Bold",
             @"GillSans-BoldItalic" : @"Bold Italic",
             @"GillSans-Italic" : @"Italic",
             @"GillSans-Light" : @"Light",
             @"GillSans-LightItalic" : @"Light Italic",
             @"GillSans-SemiBold" : @"SemiBold",
             @"GillSans-SemiBoldItalic" : @"SemiBold Italic",
             @"GillSans-UltraBold" : @"UltraBold",
             @"GujaratiMT" : @"Regular",
             @"GujaratiMT-Bold" : @"Bold",
             @"GujaratiSangamMN" : @"Regular",
             @"GujaratiSangamMN-Bold" : @"Bold",
             @"GurmukhiMN" : @"Regular",
             @"GurmukhiMN-Bold" : @"Bold",
             @"GurmukhiSangamMN" : @"Regular",
             @"GurmukhiSangamMN-Bold" : @"Bold",
             @"HannotateSC-W5" : @"Regular",
             @"HannotateSC-W7" : @"Bold",
             @"HannotateTC-W5" : @"Regular",
             @"HannotateTC-W7" : @"Bold",
             @"HanziPenSC-W3" : @"Regular",
             @"HanziPenSC-W5" : @"Bold",
             @"HanziPenTC-W3" : @"Regular",
             @"HanziPenTC-W5" : @"Bold",
             @"Helvetica" : @"Regular",
             @"Helvetica-Bold" : @"Bold",
             @"Helvetica-BoldOblique" : @"Bold Oblique",
             @"Helvetica-Light" : @"Light",
             @"Helvetica-LightOblique" : @"Light Oblique",
             @"Helvetica-Oblique" : @"Oblique",
             @"HelveticaLTMM" : @"Regular",
             @"HelveticaNeue" : @"Regular",
             @"HelveticaNeue-Bold" : @"Bold",
             @"HelveticaNeue-BoldItalic" : @"Bold Italic",
             @"HelveticaNeue-CondensedBlack" : @"Condensed Black",
             @"HelveticaNeue-CondensedBold" : @"Condensed Bold",
             @"HelveticaNeue-Italic" : @"Italic",
             @"HelveticaNeue-Light" : @"Light",
             @"HelveticaNeue-LightItalic" : @"Light Italic",
             @"HelveticaNeue-Medium" : @"Medium",
             @"HelveticaNeue-MediumItalic" : @"Medium Italic",
             @"HelveticaNeue-Thin" : @"Thin",
             @"HelveticaNeue-ThinItalic" : @"Thin Italic",
             @"HelveticaNeue-UltraLight" : @"UltraLight",
             @"HelveticaNeue-UltraLightItalic" : @"UltraLight Italic",
             @"Herculanum" : @"Regular",
             @"HiraKakuPro-W3" : @"W3",
             @"HiraKakuPro-W6" : @"W6",
             @"HiraKakuProN-W3" : @"W3",
             @"HiraKakuProN-W6" : @"W6",
             @"HiraKakuStd-W8" : @"W8",
             @"HiraKakuStdN-W8" : @"W8",
             @"HiraMaruPro-W4" : @"W4",
             @"HiraMaruProN-W4" : @"W4",
             @"HiraMinPro-W3" : @"W3",
             @"HiraMinPro-W6" : @"W6",
             @"HiraMinProN-W3" : @"W3",
             @"HiraMinProN-W6" : @"W6",
             @"HiraginoSans-W0" : @"W0",
             @"HiraginoSans-W1" : @"W1",
             @"HiraginoSans-W2" : @"W2",
             @"HiraginoSans-W3" : @"W3",
             @"HiraginoSans-W4" : @"W4",
             @"HiraginoSans-W5" : @"W5",
             @"HiraginoSans-W6" : @"W6",
             @"HiraginoSans-W7" : @"W7",
             @"HiraginoSans-W8" : @"W8",
             @"HiraginoSans-W9" : @"W9",
             @"HiraginoSansCNS-W3" : @"W3",
             @"HiraginoSansCNS-W6" : @"W6",
             @"HiraginoSansGB-W3" : @"W3",
             @"HiraginoSansGB-W6" : @"W6",
             @"HoeflerText-Black" : @"Black",
             @"HoeflerText-BlackItalic" : @"Black Italic",
             @"HoeflerText-Italic" : @"Italic",
             @"HoeflerText-Ornaments" : @"Ornaments",
             @"HoeflerText-Regular" : @"Regular",
             @"ITFDevanagari-Bold" : @"Bold",
             @"ITFDevanagari-Book" : @"Book",
             @"ITFDevanagari-Demi" : @"Demi",
             @"ITFDevanagari-Light" : @"Light",
             @"ITFDevanagari-Medium" : @"Medium",
             @"ITFDevanagariMarathi-Bold" : @"Bold",
             @"ITFDevanagariMarathi-Book" : @"Book",
             @"ITFDevanagariMarathi-Demi" : @"Demi",
             @"ITFDevanagariMarathi-Light" : @"Light",
             @"ITFDevanagariMarathi-Medium" : @"Medium",
             @"Impact" : @"Regular",
             @"InaiMathi" : @"Regular",
             @"InaiMathi-Bold" : @"Bold",
             @"IowanOldStyle-Black" : @"Black",
             @"IowanOldStyle-BlackItalic" : @"Black Italic",
             @"IowanOldStyle-Bold" : @"Bold",
             @"IowanOldStyle-BoldItalic" : @"Bold Italic",
             @"IowanOldStyle-Italic" : @"Italic",
             @"IowanOldStyle-Roman" : @"Roman",
             @"IowanOldStyle-Titling" : @"Titling",
             @"JCHEadA" : @"Regular",
             @"JCfg" : @"Regular",
             @"JCkg" : @"Regular",
             @"JCsmPC" : @"Regular",
             @"Kailasa" : @"Regular",
             @"Kailasa-Bold" : @"Bold",
             @"KannadaMN" : @"Regular",
             @"KannadaMN-Bold" : @"Bold",
             @"KannadaSangamMN" : @"Regular",
             @"KannadaSangamMN-Bold" : @"Bold",
             @"Kefa-Bold" : @"Bold",
             @"Kefa-Regular" : @"Regular",
             @"KhmerMN" : @"Regular",
             @"KhmerMN-Bold" : @"Bold",
             @"KhmerSangamMN" : @"Regular",
             @"Klee-Demibold" : @"Demibold",
             @"Klee-Medium" : @"Medium",
             @"KohinoorBangla-Bold" : @"Bold",
             @"KohinoorBangla-Light" : @"Light",
             @"KohinoorBangla-Medium" : @"Medium",
             @"KohinoorBangla-Regular" : @"Regular",
             @"KohinoorBangla-Semibold" : @"Semibold",
             @"KohinoorDevanagari-Bold" : @"Bold",
             @"KohinoorDevanagari-Light" : @"Light",
             @"KohinoorDevanagari-Medium" : @"Medium",
             @"KohinoorDevanagari-Regular" : @"Regular",
             @"KohinoorDevanagari-Semibold" : @"Semibold",
             @"KohinoorGujarati-Bold" : @"Bold",
             @"KohinoorGujarati-Light" : @"Light",
             @"KohinoorGujarati-Medium" : @"Medium",
             @"KohinoorGujarati-Regular" : @"Regular",
             @"KohinoorGujarati-Semibold" : @"Semibold",
             @"KohinoorTelugu-Bold" : @"Bold",
             @"KohinoorTelugu-Light" : @"Light",
             @"KohinoorTelugu-Medium" : @"Medium",
             @"KohinoorTelugu-Regular" : @"Regular",
             @"KohinoorTelugu-Semibold" : @"Semibold",
             @"Kokonor" : @"Regular",
             @"Krungthep" : @"Regular",
             @"KufiStandardGK" : @"Regular",
             @"LaoMN" : @"Regular",
             @"LaoMN-Bold" : @"Bold",
             @"LaoSangamMN" : @"Regular",
             @"LastResort" : @"Regular",
             @"LiGothicMed" : @"Medium",
             @"LiHeiPro" : @"Medium",
             @"LiSongPro" : @"Light",
             @"LiSungLight" : @"Light",
             @"LucidaGrande" : @"Regular",
             @"LucidaGrande-Bold" : @"Bold",
             @"Luminari-Regular" : @"Regular",
             @"MLingWaiMedium-SC" : @"Medium",
             @"MLingWaiMedium-TC" : @"Medium",
             @"MalayalamMN" : @"Regular",
             @"MalayalamMN-Bold" : @"Bold",
             @"MalayalamSangamMN" : @"Regular",
             @"MalayalamSangamMN-Bold" : @"Bold",
             @"Marion-Bold" : @"Bold",
             @"Marion-Italic" : @"Italic",
             @"Marion-Regular" : @"Regular",
             @"MarkerFelt-Thin" : @"Thin",
             @"MarkerFelt-Wide" : @"Wide",
             @"Menlo-Bold" : @"Bold",
             @"Menlo-BoldItalic" : @"Bold Italic",
             @"Menlo-Italic" : @"Italic",
             @"Menlo-Regular" : @"Regular",
             @"MicrosoftSansSerif" : @"Regular",
             @"Monaco" : @"Regular",
             @"MonotypeGurmukhi" : @"Regular",
             @"Mshtakan" : @"Regular",
             @"MshtakanBold" : @"Bold",
             @"MshtakanBoldOblique" : @"BoldOblique",
             @"MshtakanOblique" : @"Oblique",
             @"MuktaMahee-Bold" : @"Bold",
             @"MuktaMahee-ExtraBold" : @"ExtraBold",
             @"MuktaMahee-ExtraLight" : @"ExtraLight",
             @"MuktaMahee-Light" : @"Light",
             @"MuktaMahee-Medium" : @"Medium",
             @"MuktaMahee-Regular" : @"Regular",
             @"MuktaMahee-SemiBold" : @"SemiBold",
             @"Muna" : @"Regular",
             @"MunaBlack" : @"Black",
             @"MunaBold" : @"Bold",
             @"MyanmarMN" : @"Regular",
             @"MyanmarMN-Bold" : @"Bold",
             @"MyanmarSangamMN" : @"Regular",
             @"MyanmarSangamMN-Bold" : @"Bold",
             @"Nadeem" : @"Regular",
             @"NanumBrush" : @"Regular",
             @"NanumGothic" : @"Regular",
             @"NanumGothicBold" : @"Bold",
             @"NanumGothicExtraBold" : @"ExtraBold",
             @"NanumMyeongjo" : @"Regular",
             @"NanumMyeongjoBold" : @"Bold",
             @"NanumMyeongjoExtraBold" : @"ExtraBold",
             @"NanumPen" : @"Regular",
             @"NewPeninimMT" : @"Regular",
             @"NewPeninimMT-Bold" : @"Bold",
             @"NewPeninimMT-BoldInclined" : @"Bold Inclined",
             @"NewPeninimMT-Inclined" : @"Inclined",
             @"Noteworthy-Bold" : @"Bold",
             @"Noteworthy-Light" : @"Light",
             @"NotoNastaliqUrdu" : @"Regular",
             @"NotoNastaliqUrdu-Bold" : @"Bold",
             @"NotoSansArmenian-Black" : @"Black",
             @"NotoSansArmenian-Bold" : @"Bold",
             @"NotoSansArmenian-ExtraBold" : @"ExtraBold",
             @"NotoSansArmenian-ExtraLight" : @"ExtraLight",
             @"NotoSansArmenian-Light" : @"Light",
             @"NotoSansArmenian-Medium" : @"Medium",
             @"NotoSansArmenian-Regular" : @"Regular",
             @"NotoSansArmenian-SemiBold" : @"SemiBold",
             @"NotoSansArmenian-Thin" : @"Thin",
             @"NotoSansAvestan-Regular" : @"Regular",
             @"NotoSansBamum-Regular" : @"Regular",
             @"NotoSansBatak-Regular" : @"Regular",
             @"NotoSansBrahmi-Regular" : @"Regular",
             @"NotoSansBuginese-Regular" : @"Regular",
             @"NotoSansBuhid-Regular" : @"Regular",
             @"NotoSansCarian-Regular" : @"Regular",
             @"NotoSansChakma-Regular" : @"Regular",
             @"NotoSansCham-Regular" : @"Regular",
             @"NotoSansCoptic-Regular" : @"Regular",
             @"NotoSansCuneiform-Regular" : @"Regular",
             @"NotoSansCypriot-Regular" : @"Regular",
             @"NotoSansEgyptianHieroglyphs-Regular" : @"Regular",
             @"NotoSansGlagolitic-Regular" : @"Regular",
             @"NotoSansGothic-Regular" : @"Regular",
             @"NotoSansHanunoo-Regular" : @"Regular",
             @"NotoSansImperialAramaic-Regular" : @"Regular",
             @"NotoSansInscriptionalPahlavi-Regular" : @"Regular",
             @"NotoSansInscriptionalParthian-Regular" : @"Regular",
             @"NotoSansJavanese-Regular" : @"Regular",
             @"NotoSansKaithi-Regular" : @"Regular",
             @"NotoSansKannada-Black" : @"Black",
             @"NotoSansKannada-Bold" : @"Bold",
             @"NotoSansKannada-ExtraBold" : @"ExtraBold",
             @"NotoSansKannada-ExtraLight" : @"ExtraLight",
             @"NotoSansKannada-Light" : @"Light",
             @"NotoSansKannada-Medium" : @"Medium",
             @"NotoSansKannada-Regular" : @"Regular",
             @"NotoSansKannada-SemiBold" : @"SemiBold",
             @"NotoSansKannada-Thin" : @"Thin",
             @"NotoSansKayahLi-Regular" : @"Regular",
             @"NotoSansKharoshthi-Regular" : @"Regular",
             @"NotoSansLepcha-Regular" : @"Regular",
             @"NotoSansLimbu-Regular" : @"Regular",
             @"NotoSansLinearB-Regular" : @"Regular",
             @"NotoSansLisu-Regular" : @"Regular",
             @"NotoSansLycian-Regular" : @"Regular",
             @"NotoSansLydian-Regular" : @"Regular",
             @"NotoSansMandaic-Regular" : @"Regular",
             @"NotoSansMeeteiMayek-Regular" : @"Regular",
             @"NotoSansMongolian" : @"Regular",
             @"NotoSansMyanmar-Black" : @"Black",
             @"NotoSansMyanmar-Bold" : @"Bold",
             @"NotoSansMyanmar-ExtraBold" : @"ExtraBold",
             @"NotoSansMyanmar-ExtraLight" : @"ExtraLight",
             @"NotoSansMyanmar-Light" : @"Light",
             @"NotoSansMyanmar-Medium" : @"Medium",
             @"NotoSansMyanmar-Regular" : @"Regular",
             @"NotoSansMyanmar-SemiBold" : @"SemiBold",
             @"NotoSansMyanmar-Thin" : @"Thin",
             @"NotoSansNKo-Regular" : @"Regular",
             @"NotoSansNewTaiLue-Regular" : @"Regular",
             @"NotoSansOgham-Regular" : @"Regular",
             @"NotoSansOlChiki-Regular" : @"Regular",
             @"NotoSansOldItalic-Regular" : @"Regular",
             @"NotoSansOldPersian-Regular" : @"Regular",
             @"NotoSansOldSouthArabian-Regular" : @"Regular",
             @"NotoSansOldTurkic-Regular" : @"Regular",
             @"NotoSansOriya" : @"Regular",
             @"NotoSansOriya-Bold" : @"Bold",
             @"NotoSansOsmanya-Regular" : @"Regular",
             @"NotoSansPhagsPa-Regular" : @"Regular",
             @"NotoSansPhoenician-Regular" : @"Regular",
             @"NotoSansRejang-Regular" : @"Regular",
             @"NotoSansRunic-Regular" : @"Regular",
             @"NotoSansSamaritan-Regular" : @"Regular",
             @"NotoSansSaurashtra-Regular" : @"Regular",
             @"NotoSansShavian-Regular" : @"Regular",
             @"NotoSansSundanese-Regular" : @"Regular",
             @"NotoSansSylotiNagri-Regular" : @"Regular",
             @"NotoSansSyriac-Regular" : @"Regular",
             @"NotoSansTagalog-Regular" : @"Regular",
             @"NotoSansTagbanwa-Regular" : @"Regular",
             @"NotoSansTaiLe-Regular" : @"Regular",
             @"NotoSansTaiTham" : @"Regular",
             @"NotoSansTaiViet-Regular" : @"Regular",
             @"NotoSansThaana-Regular" : @"Regular",
             @"NotoSansTifinagh-Regular" : @"Regular",
             @"NotoSansUgaritic-Regular" : @"Regular",
             @"NotoSansVai-Regular" : @"Regular",
             @"NotoSansYi-Regular" : @"Regular",
             @"NotoSansZawgyi-Black" : @"Black",
             @"NotoSansZawgyi-Bold" : @"Bold",
             @"NotoSansZawgyi-ExtraBold" : @"ExtraBold",
             @"NotoSansZawgyi-ExtraLight" : @"ExtraLight",
             @"NotoSansZawgyi-Light" : @"Light",
             @"NotoSansZawgyi-Medium" : @"Medium",
             @"NotoSansZawgyi-Regular" : @"Regular",
             @"NotoSansZawgyi-SemiBold" : @"SemiBold",
             @"NotoSansZawgyi-Thin" : @"Thin",
             @"NotoSerifBalinese-Regular" : @"Regular",
             @"NotoSerifMyanmar-Black" : @"Black",
             @"NotoSerifMyanmar-Bold" : @"Bold",
             @"NotoSerifMyanmar-ExtraBold" : @"ExtraBold",
             @"NotoSerifMyanmar-ExtraLight" : @"ExtraLight",
             @"NotoSerifMyanmar-Light" : @"Light",
             @"NotoSerifMyanmar-Medium" : @"Medium",
             @"NotoSerifMyanmar-Regular" : @"Regular",
             @"NotoSerifMyanmar-SemiBold" : @"SemiBold",
             @"NotoSerifMyanmar-Thin" : @"Thin",
             @"Optima-Bold" : @"Bold",
             @"Optima-BoldItalic" : @"Bold Italic",
             @"Optima-ExtraBlack" : @"ExtraBlack",
             @"Optima-Italic" : @"Italic",
             @"Optima-Regular" : @"Regular",
             @"OriyaMN" : @"Regular",
             @"OriyaMN-Bold" : @"Bold",
             @"OriyaSangamMN" : @"Regular",
             @"OriyaSangamMN-Bold" : @"Bold",
             @"Osaka" : @"Regular",
             @"Osaka-Mono" : @"Regular-Mono",
             @"PSLOrnanongPro-Bold" : @"Bold",
             @"PSLOrnanongPro-BoldItalic" : @"Bold Italic",
             @"PSLOrnanongPro-Demibold" : @"Demibold",
             @"PSLOrnanongPro-DemiboldItalic" : @"Demibold Italic",
             @"PSLOrnanongPro-Italic" : @"Italic",
             @"PSLOrnanongPro-Light" : @"Light",
             @"PSLOrnanongPro-LightItalic" : @"Light Italic",
             @"PSLOrnanongPro-Regular" : @"Regular",
             @"PTMono-Bold" : @"Bold",
             @"PTMono-Regular" : @"Regular",
             @"PTSans-Bold" : @"Bold",
             @"PTSans-BoldItalic" : @"Bold Italic",
             @"PTSans-Caption" : @"Regular",
             @"PTSans-CaptionBold" : @"Bold",
             @"PTSans-Italic" : @"Italic",
             @"PTSans-Narrow" : @"Regular",
             @"PTSans-NarrowBold" : @"Bold",
             @"PTSans-Regular" : @"Regular",
             @"PTSerif-Bold" : @"Bold",
             @"PTSerif-BoldItalic" : @"Bold Italic",
             @"PTSerif-Caption" : @"Regular",
             @"PTSerif-CaptionItalic" : @"Italic",
             @"PTSerif-Italic" : @"Italic",
             @"PTSerif-Regular" : @"Regular",
             @"Palatino-Bold" : @"Bold",
             @"Palatino-BoldItalic" : @"Bold Italic",
             @"Palatino-Italic" : @"Italic",
             @"Palatino-Roman" : @"Regular",
             @"Papyrus" : @"Regular",
             @"Papyrus-Condensed" : @"Condensed",
             @"Phosphate-Inline" : @"Inline",
             @"Phosphate-Solid" : @"Solid",
             @"PingFangHK-Light" : @"Light",
             @"PingFangHK-Medium" : @"Medium",
             @"PingFangHK-Regular" : @"Regular",
             @"PingFangHK-Semibold" : @"Semibold",
             @"PingFangHK-Thin" : @"Thin",
             @"PingFangHK-Ultralight" : @"Ultralight",
             @"PingFangSC-Light" : @"Light",
             @"PingFangSC-Medium" : @"Medium",
             @"PingFangSC-Regular" : @"Regular",
             @"PingFangSC-Semibold" : @"Semibold",
             @"PingFangSC-Thin" : @"Thin",
             @"PingFangSC-Ultralight" : @"Ultralight",
             @"PingFangTC-Light" : @"Light",
             @"PingFangTC-Medium" : @"Medium",
             @"PingFangTC-Regular" : @"Regular",
             @"PingFangTC-Semibold" : @"Semibold",
             @"PingFangTC-Thin" : @"Thin",
             @"PingFangTC-Ultralight" : @"Ultralight",
             @"PlantagenetCherokee" : @"Regular",
             @"Raanana" : @"Regular",
             @"RaananaBold" : @"Bold",
             @"Rockwell-Bold" : @"Bold",
             @"Rockwell-BoldItalic" : @"Bold Italic",
             @"Rockwell-Italic" : @"Italic",
             @"Rockwell-Regular" : @"Regular",
             @"SFMono-Bold" : @"Bold",
             @"SFMono-BoldItalic" : @"Bold Italic",
             @"SFMono-Heavy" : @"Heavy",
             @"SFMono-HeavyItalic" : @"Heavy Italic",
             @"SFMono-Light" : @"Light",
             @"SFMono-LightItalic" : @"Light Italic",
             @"SFMono-Medium" : @"Medium",
             @"SFMono-MediumItalic" : @"Medium Italic",
             @"SFMono-Regular" : @"Regular",
             @"SFMono-RegularItalic" : @"Regular Italic",
             @"SFMono-Semibold" : @"Semibold",
             @"SFMono-SemiboldItalic" : @"Semibold Italic",
             @"SIL-Hei-Med-Jian" : @"Regular",
             @"SIL-Kai-Reg-Jian" : @"Regular",
             @"STBaoliSC-Regular" : @"Regular",
             @"STBaoliTC-Regular" : @"Regular",
             @"STFangsong" : @"Regular",
             @"STHeiti" : @"Regular",
             @"STHeitiSC-Light" : @"Light",
             @"STHeitiSC-Medium" : @"Medium",
             @"STHeitiTC-Light" : @"Light",
             @"STHeitiTC-Medium" : @"Medium",
             @"STIXGeneral-Bold" : @"Bold",
             @"STIXGeneral-BoldItalic" : @"Bold Italic",
             @"STIXGeneral-Italic" : @"Italic",
             @"STIXGeneral-Regular" : @"Regular",
             @"STIXIntegralsD-Bold" : @"Bold",
             @"STIXIntegralsD-Regular" : @"Regular",
             @"STIXIntegralsSm-Bold" : @"Bold",
             @"STIXIntegralsSm-Regular" : @"Regular",
             @"STIXIntegralsUp-Bold" : @"Bold",
             @"STIXIntegralsUp-Regular" : @"Regular",
             @"STIXIntegralsUpD-Bold" : @"Bold",
             @"STIXIntegralsUpD-Regular" : @"Regular",
             @"STIXIntegralsUpSm-Bold" : @"Bold",
             @"STIXIntegralsUpSm-Regular" : @"Regular",
             @"STIXNonUnicode-Bold" : @"Bold",
             @"STIXNonUnicode-BoldItalic" : @"Bold Italic",
             @"STIXNonUnicode-Italic" : @"Italic",
             @"STIXNonUnicode-Regular" : @"Regular",
             @"STIXSizeFiveSym-Regular" : @"Regular",
             @"STIXSizeFourSym-Bold" : @"Bold",
             @"STIXSizeFourSym-Regular" : @"Regular",
             @"STIXSizeOneSym-Bold" : @"Bold",
             @"STIXSizeOneSym-Regular" : @"Regular",
             @"STIXSizeThreeSym-Bold" : @"Bold",
             @"STIXSizeThreeSym-Regular" : @"Regular",
             @"STIXSizeTwoSym-Bold" : @"Bold",
             @"STIXSizeTwoSym-Regular" : @"Regular",
             @"STIXVariants-Bold" : @"Bold",
             @"STIXVariants-Regular" : @"Regular",
             @"STKaiti" : @"Regular",
             @"STKaitiSC-Black" : @"Black",
             @"STKaitiSC-Bold" : @"Bold",
             @"STKaitiSC-Regular" : @"Regular",
             @"STKaitiTC-Black" : @"Black",
             @"STKaitiTC-Bold" : @"Bold",
             @"STKaitiTC-Regular" : @"Regular",
             @"STLibianSC-Regular" : @"Regular",
             @"STLibianTC-Regular" : @"Regular",
             @"STSong" : @"Regular",
             @"STSongti-SC-Black" : @"Black",
             @"STSongti-SC-Bold" : @"Bold",
             @"STSongti-SC-Light" : @"Light",
             @"STSongti-SC-Regular" : @"Regular",
             @"STSongti-TC-Bold" : @"Bold",
             @"STSongti-TC-Light" : @"Light",
             @"STSongti-TC-Regular" : @"Regular",
             @"STXihei" : @"Light",
             @"STXingkaiSC-Bold" : @"Bold",
             @"STXingkaiSC-Light" : @"Light",
             @"STXingkaiTC-Bold" : @"Bold",
             @"STXingkaiTC-Light" : @"Light",
             @"STYuanti-SC-Bold" : @"Bold",
             @"STYuanti-SC-Light" : @"Light",
             @"STYuanti-SC-Regular" : @"Regular",
             @"STYuanti-TC-Bold" : @"Bold",
             @"STYuanti-TC-Light" : @"Light",
             @"STYuanti-TC-Regular" : @"Regular",
             @"Sana" : @"Regular",
             @"Sathu" : @"Regular",
             @"SavoyeLetPlain" : @"Plain",
             @"Seravek" : @"Regular",
             @"Seravek-Bold" : @"Bold",
             @"Seravek-BoldItalic" : @"Bold Italic",
             @"Seravek-ExtraLight" : @"ExtraLight",
             @"Seravek-ExtraLightItalic" : @"ExtraLight Italic",
             @"Seravek-Italic" : @"Italic",
             @"Seravek-Light" : @"Light",
             @"Seravek-LightItalic" : @"Light Italic",
             @"Seravek-Medium" : @"Medium",
             @"Seravek-MediumItalic" : @"Medium Italic",
             @"ShreeDev0714" : @"Regular",
             @"ShreeDev0714-Bold" : @"Bold",
             @"ShreeDev0714-BoldItalic" : @"Bold Italic",
             @"ShreeDev0714-Italic" : @"Italic",
             @"SignPainter-HouseScript" : @"HouseScript",
             @"SignPainter-HouseScriptSemibold" : @"HouseScript Semibold",
             @"Silom" : @"Regular",
             @"SinhalaMN" : @"Regular",
             @"SinhalaMN-Bold" : @"Bold",
             @"SinhalaSangamMN" : @"Regular",
             @"SinhalaSangamMN-Bold" : @"Bold",
             @"Skia-Regular" : @"Regular",
             @"Skia-Regular_Black" : @"Black",
             @"Skia-Regular_Black-Condensed" : @"Black Condensed",
             @"Skia-Regular_Black-Extended" : @"Black Extended",
             @"Skia-Regular_Bold" : @"Bold",
             @"Skia-Regular_Condensed" : @"Condensed",
             @"Skia-Regular_Extended" : @"Extended",
             @"Skia-Regular_Light" : @"Light",
             @"Skia-Regular_Light-Condensed" : @"Light Condensed",
             @"Skia-Regular_Light-Extended" : @"Light Extended",
             @"SnellRoundhand" : @"Regular",
             @"SnellRoundhand-Black" : @"Black",
             @"SnellRoundhand-Bold" : @"Bold",
             @"SukhumvitSet-Bold" : @"Bold",
             @"SukhumvitSet-Light" : @"Light",
             @"SukhumvitSet-Medium" : @"Medium",
             @"SukhumvitSet-SemiBold" : @"Semi Bold",
             @"SukhumvitSet-Text" : @"Text",
             @"SukhumvitSet-Thin" : @"Thin",
             @"Superclarendon-Black" : @"Black",
             @"Superclarendon-BlackItalic" : @"Black Italic",
             @"Superclarendon-Bold" : @"Bold",
             @"Superclarendon-BoldItalic" : @"Bold Italic",
             @"Superclarendon-Italic" : @"Italic",
             @"Superclarendon-Light" : @"Light",
             @"Superclarendon-LightItalic" : @"Light Italic",
             @"Superclarendon-Regular" : @"Regular",
             @"Symbol" : @"Regular",
             @"Tahoma" : @"Regular",
             @"Tahoma-Bold" : @"Bold",
             @"TamilMN" : @"Regular",
             @"TamilMN-Bold" : @"Bold",
             @"TamilSangamMN" : @"Regular",
             @"TamilSangamMN-Bold" : @"Bold",
             @"TeamViewer12" : @"Medium",
             @"TeluguMN" : @"Regular",
             @"TeluguMN-Bold" : @"Bold",
             @"TeluguSangamMN" : @"Regular",
             @"TeluguSangamMN-Bold" : @"Bold",
             @"Thonburi" : @"Regular",
             @"Thonburi-Bold" : @"Bold",
             @"Thonburi-Light" : @"Light",
             @"Times-Bold" : @"Bold",
             @"Times-BoldItalic" : @"Bold Italic",
             @"Times-Italic" : @"Italic",
             @"Times-Roman" : @"Regular",
             @"TimesLTMM" : @"Regular",
             @"TimesNewRomanPS-BoldItalicMT" : @"Bold Italic",
             @"TimesNewRomanPS-BoldMT" : @"Bold",
             @"TimesNewRomanPS-ItalicMT" : @"Italic",
             @"TimesNewRomanPSMT" : @"Regular",
             @"ToppanBunkyuGothicPr6N-DB" : @"Demibold",
             @"ToppanBunkyuGothicPr6N-Regular" : @"Regular",
             @"ToppanBunkyuMidashiGothicStdN-ExtraBold" : @"Extrabold",
             @"ToppanBunkyuMidashiMinchoStdN-ExtraBold" : @"Extrabold",
             @"ToppanBunkyuMinchoPr6N-Regular" : @"Regular",
             @"Trattatello" : @"Regular",
             @"Trebuchet-BoldItalic" : @"Bold Italic",
             @"TrebuchetMS" : @"Regular",
             @"TrebuchetMS-Bold" : @"Bold",
             @"TrebuchetMS-Italic" : @"Italic",
             @"TsukuARdGothic-Bold" : @"Bold",
             @"TsukuARdGothic-Regular" : @"Regular",
             @"TsukuBRdGothic-Bold" : @"Bold",
             @"TsukuBRdGothic-Regular" : @"Regular",
             @"Verdana" : @"Regular",
             @"Verdana-Bold" : @"Bold",
             @"Verdana-BoldItalic" : @"Bold Italic",
             @"Verdana-Italic" : @"Italic",
             @"Waseem" : @"Regular",
             @"WaseemLight" : @"Light",
             @"Webdings" : @"Regular",
             @"WeibeiSC-Bold" : @"Bold",
             @"WeibeiTC-Bold" : @"Bold",
             @"Wingdings-Regular" : @"Regular",
             @"Wingdings2" : @"Regular",
             @"Wingdings3" : @"Regular",
             @"YuGo-Bold" : @"Bold",
             @"YuGo-Medium" : @"Medium",
             @"YuKyo-Bold" : @"Bold",
             @"YuKyo-Medium" : @"Medium",
             @"YuKyo_Yoko-Bold" : @"Bold",
             @"YuKyo_Yoko-Medium" : @"Medium",
             @"YuMin-Demibold" : @"Demibold",
             @"YuMin-Extrabold" : @"Extrabold",
             @"YuMin-Medium" : @"Medium",
             @"YuMin_36pKn-Demibold" : @"Demibold",
             @"YuMin_36pKn-Extrabold" : @"Extrabold",
             @"YuMin_36pKn-Medium" : @"Medium",
             @"YuppySC-Regular" : @"Regular",
             @"YuppyTC-Regular" : @"Regular",
             @"ZapfDingbatsITC" : @"Regular",
             @"Zapfino" : @"Regular",

             // JetBrains fonts
             @"DroidSans" : @"Regular",
             @"DroidSans-Bold" : @"Bold",
             @"DroidSansMono" : @"Regular",
             @"DroidSansMonoDotted" : @"Regular",
             @"DroidSansMonoSlashed" : @"Regular",
             @"DroidSerif" : @"Regular",
             @"DroidSerif-Bold" : @"Bold",
             @"DroidSerif-BoldItalic" : @"Bold Italic",
             @"DroidSerif-Italic" : @"Italic",
             @"FiraCode-Bold" : @"Bold",
             @"FiraCode-Light" : @"Light",
             @"FiraCode-Medium" : @"Medium",
             @"FiraCode-Regular" : @"Regular",
             @"FiraCode-Retina" : @"Retina",
             @"Inconsolata" : @"Medium",
             @"JetBrainsMono-Bold" : @"Bold",
             @"JetBrainsMono-Regular" : @"Regular",
             @"JetBrainsMono-Italic" : @"Italic",
             @"JetBrainsMono-BoldItalic" : @"Bold Italic",
             @"Roboto-Light" : @"Light",
             @"Roboto-Thin" : @"Thin",
             @"SourceCodePro-Bold" : @"Bold",
             @"SourceCodePro-BoldIt" : @"Bold Italic",
             @"SourceCodePro-It" : @"Italic",
             @"SourceCodePro-Regular" : @"Regular",
             @"Inter-Bold": @"Bold",
             @"Inter-BoldItalic": @"Bold Italoc",
             @"Inter-Italic": @"Italic",
             @"Inter-Regular": @"Regular"
            };
}

static bool
isVisibleFamily(NSString *familyName) {
    return familyName != nil &&
    ([familyName characterAtIndex:0] != '.' ||
     [familyName isEqualToString:@".SF NS Text"] ||
     [familyName isEqualToString:@".SF NS Display"] ||
     // Catalina
     [familyName isEqualToString:@".SF NS Mono"] ||
     [familyName isEqualToString:@".SF NS"]);
}

static NSArray*
GetFilteredFonts()
{
    if (sFilteredFonts == nil) {
        NSFontManager *fontManager = [NSFontManager sharedFontManager];
        NSArray<NSString *> *availableFonts= [fontManager availableFonts];
        NSUInteger fontCount = [availableFonts count];
        NSMutableArray* allFonts = [NSMutableArray arrayWithCapacity:fontCount];
        NSMutableDictionary* fontFamilyTable = [[NSMutableDictionary alloc] initWithCapacity:fontCount];
        NSMutableDictionary* fontFacesTable = [[NSMutableDictionary alloc] initWithCapacity:fontCount];
        NSMutableDictionary* fontTable = [[NSMutableDictionary alloc] initWithCapacity:fontCount];
        NSDictionary* prebuiltFamilies = prebuiltFamilyNames();
        NSDictionary* prebuiltFaces = prebuiltFaceNames();
        for (NSString *fontName in availableFonts) {
            NSFont* font = nil;
            NSString* familyName = [prebuiltFamilies objectForKey:fontName];
            if (!familyName) {
                font = [NSFont fontWithName:fontName size:NSFont.systemFontSize];
                if(font && font.familyName) {
                    familyName = font.familyName;
//                    NSLog(@"@\"%@\" : @\"%@\",", fontName, familyName);
                }
            }
            if (!isVisibleFamily(familyName)) {
                continue;
            }
            NSString* face = [prebuiltFaces objectForKey:fontName];
            if (!face) {
                if (!font) {
                    font = [NSFont fontWithName:fontName size:NSFont.systemFontSize];
                }
                if (font) {
                    NSFontDescriptor* desc = font.fontDescriptor;
                    if (desc) {
                        face = [desc objectForKey:NSFontFaceAttribute];
//                        if (face) NSLog(@"@\"%@\" : @\"%@\",", fontName, face);
                    }
                }
            }
            [allFonts addObject:fontName];
            [fontFamilyTable setObject:familyName forKey:fontName];
            if (face) {
                [fontFacesTable setObject:face forKey:fontName];
            }
        }


        /*
         * JavaFX registers these fonts and so JDK needs to do so as well.
         * If this isn't done we will have mis-matched rendering, since
         * although these may include fonts that are enumerated normally
         * they also demonstrably includes fonts that are not.
         */
        addFont(kCTFontUIFontSystem, allFonts, fontFamilyTable, fontFacesTable);
        addFont(kCTFontUIFontEmphasizedSystem, allFonts, fontFamilyTable, fontFacesTable);

        sFilteredFonts = allFonts;
        sFontFamilyTable = fontFamilyTable;
        sFontFaceTable = fontFacesTable;
    }

    return sFilteredFonts;
}

#pragma mark --- sun.font.CFontManager JNI ---

static OSStatus CreateFSRef(FSRef *myFSRefPtr, NSString *inPath)
{
    return FSPathMakeRef((UInt8 *)[inPath fileSystemRepresentation],
                         myFSRefPtr, NULL);
}

/*
 * Class:     sun_font_CFontManager
 * Method:    loadNativeFonts
 * Signature: ()V
 */
JNIEXPORT void JNICALL
Java_sun_font_CFontManager_loadNativeFonts
    (JNIEnv *env, jobject jthis)
{
    DECLARE_CLASS(jc_CFontManager, "sun/font/CFontManager");
    DECLARE_METHOD(jm_registerFont, jc_CFontManager, "registerFont", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V");

    jint num = 0;

JNI_COCOA_ENTER(env);

    NSArray *filteredFonts = GetFilteredFonts();
    num = (jint)[filteredFonts count];

    jint i;
    for (i = 0; i < num; i++) {
        NSString *fontname = [filteredFonts objectAtIndex:i];
        jobject jFontName = NSStringToJavaString(env, fontname);
        jobject jFontFamilyName =
            NSStringToJavaString(env, GetFamilyNameForFontName(fontname));
        NSString *face = GetFaceForFontName(fontname);
        jobject jFaceName = face ? NSStringToJavaString(env, face) : NULL;

        (*env)->CallVoidMethod(env, jthis, jm_registerFont, jFontName, jFontFamilyName, jFaceName);
        CHECK_EXCEPTION();
        (*env)->DeleteLocalRef(env, jFontName);
        (*env)->DeleteLocalRef(env, jFontFamilyName);
        if (jFaceName) {
            (*env)->DeleteLocalRef(env, jFaceName);
        }
    }

JNI_COCOA_EXIT(env);
}

/*
 * Class:     Java_sun_font_CFontManager_loadNativeDirFonts
 * Method:    getNativeFontVersion
 * Signature: (Ljava/lang/String;)Ljava/lang/String;
 */
JNIEXPORT JNICALL jstring
Java_sun_font_CFontManager_getNativeFontVersion
        (JNIEnv *env, jclass clz, jstring psName)
{
    jstring result = NULL;
JNI_COCOA_ENTER(env);
    NSString *psNameStr = JavaStringToNSString(env, psName);
    CTFontRef sFont = CTFontCreateWithName(psNameStr, 13, nil);
    CFStringRef sFontPSName = CTFontCopyName(sFont, kCTFontPostScriptNameKey);
    // CTFontCreateWithName always returns some font,
    // so we need to check if it is right one
    if ([psNameStr isEqualToString:sFontPSName]) {
        CFStringRef fontVersionStr = CTFontCopyName(sFont,
                                                    kCTFontVersionNameKey);
        result = NSStringToJavaString(env, fontVersionStr);
        CFRelease(fontVersionStr);
    }

    CFRelease(sFontPSName);
    CFRelease(sFont);
JNI_COCOA_EXIT(env);
    return result;
}

/*
 * Class:     Java_sun_font_CFontManager_loadNativeDirFonts
 * Method:    loadNativeDirFonts
 * Signature: (Ljava/lang/String;)V;
 */
JNIEXPORT void JNICALL
Java_sun_font_CFontManager_loadNativeDirFonts
(JNIEnv *env, jclass clz, jstring filename)
{
JNI_COCOA_ENTER(env);

    NSString *path = JavaStringToNSString(env, filename);
    NSURL *url = [NSURL fileURLWithPath:(NSString *)path];
    bool res = CTFontManagerRegisterFontsForURL((CFURLRef)url, kCTFontManagerScopeProcess, nil);
#ifdef DEBUG
    NSLog(@"path is : %@", (NSString*)path);
    NSLog(@"url is : %@", (NSString*)url);
    printf("res is %d\n", res);
#endif
JNI_COCOA_EXIT(env);
}

#pragma mark --- sun.font.CFont JNI ---

/*
 * Class:     sun_font_CFont
 * Method:    getPlatformFontPtrNative
 * Signature: (JI)[B
 */
JNIEXPORT jlong JNICALL
Java_sun_font_CFont_getCGFontPtrNative
    (JNIEnv *env, jclass clazz,
     jlong awtFontPtr)
{
    AWTFont *awtFont = (AWTFont *)jlong_to_ptr(awtFontPtr);
    return (jlong)(awtFont->fNativeCGFont);
}

/*
 * Class:     sun_font_CFont
 * Method:    getTableBytesNative
 * Signature: (JI)[B
 */
JNIEXPORT jbyteArray JNICALL
Java_sun_font_CFont_getTableBytesNative
    (JNIEnv *env, jclass clazz,
     jlong awtFontPtr, jint jtag)
{
    jbyteArray jbytes = NULL;
JNI_COCOA_ENTER(env);

    CTFontTableTag tag = (CTFontTableTag)jtag;
    int i, found = 0;
    AWTFont *awtFont = (AWTFont *)jlong_to_ptr(awtFontPtr);
    NSFont* nsFont = awtFont->fFont;
    CTFontRef ctfont = (CTFontRef)nsFont;
    CFArrayRef tagsArray =
        CTFontCopyAvailableTables(ctfont, kCTFontTableOptionNoOptions);
    CFIndex numTags = CFArrayGetCount(tagsArray);
    for (i=0; i<numTags; i++) {
        if (tag ==
            (CTFontTableTag)(uintptr_t)CFArrayGetValueAtIndex(tagsArray, i)) {
            found = 1;
            break;
        }
    }
    CFRelease(tagsArray);
    if (!found) {
        return NULL;
    }
    CFDataRef table = CTFontCopyTable(ctfont, tag, kCTFontTableOptionNoOptions);
    if (table == NULL) {
        return NULL;
    }

    char *tableBytes = (char*)(CFDataGetBytePtr(table));
    size_t tableLength = CFDataGetLength(table);
    if (tableBytes == NULL || tableLength == 0) {
        CFRelease(table);
        return NULL;
    }

    jbytes = (*env)->NewByteArray(env, (jsize)tableLength);
    if (jbytes == NULL) {
        return NULL;
    }
    (*env)->SetByteArrayRegion(env, jbytes, 0,
                               (jsize)tableLength,
                               (jbyte*)tableBytes);
    CFRelease(table);

JNI_COCOA_EXIT(env);

    return jbytes;
}

/*
 * Class:     sun_font_CFont
 * Method:    initNativeFont
 * Signature: (Ljava/lang/String;I)J
 */
JNIEXPORT jlong JNICALL
Java_sun_font_CFont_createNativeFont
    (JNIEnv *env, jclass clazz,
     jstring nativeFontName, jint style)
{
    AWTFont *awtFont = nil;

JNI_COCOA_ENTER(env);

    awtFont =
        [AWTFont awtFontForName:JavaStringToNSString(env, nativeFontName)
         style:style]; // autoreleased

    if (awtFont) {
        CFRetain(awtFont); // GC
    }

JNI_COCOA_EXIT(env);

    return ptr_to_jlong(awtFont);
}

/*
 * Class:     sun_font_CFont
 * Method:    getWidthNative
 * Signature: (J)F
 */
JNIEXPORT jfloat JNICALL
Java_sun_font_CFont_getWidthNative
    (JNIEnv *env, jobject cfont, jlong awtFontPtr)
{
    float widthVal;
JNI_COCOA_ENTER(env);

    AWTFont *awtFont = (AWTFont *)jlong_to_ptr(awtFontPtr);
    NSFont* nsFont = awtFont->fFont;
    NSFontDescriptor *fontDescriptor = nsFont.fontDescriptor;
    NSDictionary *fontTraits = [fontDescriptor objectForKey : NSFontTraitsAttribute];
    NSNumber *width = [fontTraits objectForKey : NSFontWidthTrait];
    widthVal = (float)[width floatValue];

JNI_COCOA_EXIT(env);
   return (jfloat)widthVal;
}

/*
 * Class:     sun_font_CFont
 * Method:    getWeightNative
 * Signature: (J)F
 */
JNIEXPORT jfloat JNICALL
Java_sun_font_CFont_getWeightNative
    (JNIEnv *env, jobject cfont, jlong awtFontPtr)
{
    float weightVal;
JNI_COCOA_ENTER(env);

    AWTFont *awtFont = (AWTFont *)jlong_to_ptr(awtFontPtr);
    NSFont* nsFont = awtFont->fFont;
    NSFontDescriptor *fontDescriptor = nsFont.fontDescriptor;
    NSDictionary *fontTraits = [fontDescriptor objectForKey : NSFontTraitsAttribute];
    NSNumber *weight = [fontTraits objectForKey : NSFontWeightTrait];
    weightVal = (float)[weight floatValue];

JNI_COCOA_EXIT(env);
   return (jfloat)weightVal;
}

/*
 * Class:     sun_font_CFont
 * Method:    disposeNativeFont
 * Signature: (J)V
 */
JNIEXPORT void JNICALL
Java_sun_font_CFont_disposeNativeFont
    (JNIEnv *env, jclass clazz, jlong awtFontPtr)
{
JNI_COCOA_ENTER(env);

    if (awtFontPtr) {
        CFRelease((AWTFont *)jlong_to_ptr(awtFontPtr)); // GC
    }

JNI_COCOA_EXIT(env);
}


#pragma mark --- Miscellaneous JNI ---

#ifndef HEADLESS
/*
 * Class:     sun_awt_PlatformFont
 * Method:    initIDs
 * Signature: ()V
 */
JNIEXPORT void JNICALL
Java_sun_awt_PlatformFont_initIDs
    (JNIEnv *env, jclass cls)
{
}

/*
 * Class:     sun_awt_FontDescriptor
 * Method:    initIDs
 * Signature: ()V
 */
JNIEXPORT void JNICALL
Java_sun_awt_FontDescriptor_initIDs
    (JNIEnv *env, jclass cls)
{
}
#endif

/*
 * Class:     sun_font_CFont
 * Method:    getCascadeList
 * Signature: (JLjava/util/ArrayList;)V
 */
JNIEXPORT void JNICALL
Java_sun_font_CFont_getCascadeList
    (JNIEnv *env, jclass cls, jlong awtFontPtr, jobject arrayListOfString)
{
JNI_COCOA_ENTER(env);
    jclass alc = (*env)->FindClass(env, "java/util/ArrayList");
    if (alc == NULL) return;
    jmethodID addMID = (*env)->GetMethodID(env, alc, "add", "(Ljava/lang/Object;)Z");
    if (addMID == NULL) return;

    CFIndex i;
    AWTFont *awtFont = (AWTFont *)jlong_to_ptr(awtFontPtr);
    NSFont* nsFont = awtFont->fFont;
#ifdef DEBUG
    CFStringRef base = CTFontCopyFullName((CTFontRef)nsFont);
    NSLog(@"BaseFont is : %@", (NSString*)base);
    CFRelease(base);
#endif
    bool anotherBaseFont = false;
    if (awtFont->fFallbackBase != nil) {
        nsFont = awtFont->fFallbackBase;
        anotherBaseFont = true;
    }
    CTFontRef font = (CTFontRef)nsFont;
    CFArrayRef codes = CFLocaleCopyISOLanguageCodes();

    CFArrayRef fds = CTFontCopyDefaultCascadeListForLanguages(font, codes);
    CFRelease(codes);
    CFIndex cnt = CFArrayGetCount(fds);
    for (i= anotherBaseFont ? -1 : 0; i<cnt; i++) {
        CFStringRef fontname;
        if (i < 0) {
            fontname = CTFontCopyPostScriptName(font);
        } else {
            CTFontDescriptorRef ref = CFArrayGetValueAtIndex(fds, i);
            fontname = CTFontDescriptorCopyAttribute(ref, kCTFontNameAttribute);
        }
#ifdef DEBUG
        NSLog(@"Font is : %@", (NSString*)fontname);
#endif
        jstring jFontName = (jstring)NSStringToJavaString(env, fontname);
        CFRelease(fontname);
        (*env)->CallBooleanMethod(env, arrayListOfString, addMID, jFontName);
        if ((*env)->ExceptionOccurred(env)) {
            CFRelease(fds);
            return;
        }
        (*env)->DeleteLocalRef(env, jFontName);
    }
    CFRelease(fds);
JNI_COCOA_EXIT(env);
}

static CFStringRef EMOJI_FONT_NAME = CFSTR("Apple Color Emoji");

bool IsEmojiFont(CTFontRef font)
{
    CFStringRef name = CTFontCopyFullName(font);
    if (name == NULL) return false;
    bool isFixedColor = CFStringCompare(name, EMOJI_FONT_NAME, 0) == kCFCompareEqualTo;
    CFRelease(name);
    return isFixedColor;
}
