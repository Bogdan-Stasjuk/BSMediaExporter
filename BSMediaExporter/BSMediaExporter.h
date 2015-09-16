//
//  BSMediaExporter.h
//
//  Created by Bogdan Stasiuk on 8/27/15.
//  Copyright (c) 2015 Bogdan Stasiuk. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>


#if defined(__has_include)
#define IS_LAME_EXISTS __has_include("lame/lame.h")
#endif


@class AVAsset;


@interface BSMediaExporter : NSObject

@property (copy, nonatomic) void (^success)(NSURL *exportedURL);
@property (copy, nonatomic) void (^failure)(NSError *error);

/*!
 * @discussion Creates file at documents directory or removes existing file
 * @param avFileType AVFileType constant
 * @param error Error of creating file
 * @return File url or nil if error is occured
 */
+ (NSURL *)outputURLForAVFileType:(NSString *)avFileType error:(NSError *)error;

/*!
 * @discussion Exports media asset to kAudioFormatMPEG4AAC or kAudioFormatLinearPCM and calls success block or failure block appropriately
 * @param asset AVAsset instance of media item
 * @param audioFormatID Now is supported kAudioFormatMPEG4AAC and kAudioFormatLinearPCM only
 */
- (void)exportAsset:(AVAsset *)asset toAudioFormat:(AudioFormatID)audioFormatID;

#if IS_LAME_EXISTS
- (void)exportAssetToMP3:(AVAsset *)asset;
#endif

- (void)cancel;

@end
