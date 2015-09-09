//
//  BSMediaExporter.h
//  TDAudioStreamer
//
//  Created by Bogdan Stasjuk on 8/27/15.
//  Copyright (c) 2015 Bogdan Stasjuk. All rights reserved.
//

#import <Foundation/Foundation.h>


@class AVAsset;


@interface BSMediaExporter : NSObject

@property (copy, nonatomic) void (^success)(NSURL *exportedURL);
@property (copy, nonatomic) void (^failure)(NSError *error);

+ (NSURL *)outputURLForAVFileType:(NSString *)avFileType error:(NSError *)error;

- (void)exportAssetToCAF:(AVAsset *)asset;
- (void)exportAssetToMP3:(AVAsset *)asset;

- (void)cancel;

@end
