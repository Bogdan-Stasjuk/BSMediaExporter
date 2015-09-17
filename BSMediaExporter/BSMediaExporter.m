//
//  BSMediaExporter.m
//
//  Created by Bogdan Stasiuk on 8/27/15.
//  Copyright (c) 2015 Bogdan Stasiuk. All rights reserved.
//

#import "BSMediaExporter.h"

#import <MobileCoreServices/UTType.h>

#import <BSMacros/BSMacros.h>
#import <BSAudioFileHelper/BSAudioFileHelper.h>
#import <NSFileManager+Helper/NSFileManager+Helper.h>

#if IS_LAME_EXISTS
#include "lame/lame.h"
#endif


static NSString * const BSExportedFileName = @"exported";


@interface BSMediaExporter ()

@property (strong, nonatomic) dispatch_group_t dispatchGroup;
@property (strong, nonatomic) dispatch_queue_t mainSerializationQueue;
@property (strong, nonatomic) dispatch_queue_t rwAudioSerializationQueue;
@property (strong, nonatomic) dispatch_queue_t rwVideoSerializationQueue;

@property (strong, nonatomic) AVAssetReader             *assetReader;
@property (strong, nonatomic) AVAssetWriter             *assetWriter;
@property (strong, nonatomic) AVAssetReaderTrackOutput  *assetReaderAudioOutput;
@property (strong, nonatomic) AVAssetWriterInput        *assetWriterAudioInput;
@property (strong, nonatomic) AVAssetReaderTrackOutput  *assetReaderVideoOutput;
@property (strong, nonatomic) AVAssetWriterInput        *assetWriterVideoInput;

@property (strong, nonatomic) NSURL *outputCAFURL;

@property (assign, nonatomic) BOOL cancelled;
@property (assign, nonatomic) BOOL exportToMP3;
@property (assign, nonatomic) BOOL audioFinished;
@property (assign, nonatomic) BOOL videoFinished;

@end


@implementation BSMediaExporter

#pragma mark - Public methods

#pragma mark -Static

+ (NSURL *)outputURLForAVFileType:(NSString *)avFileType error:(NSError *)error {
    NSString *filenameExtansion = CFBridgingRelease(UTTypeCopyPreferredTagWithClass((__bridge CFStringRef)avFileType, kUTTagClassFilenameExtension));
    NSString *filename = [BSExportedFileName stringByAppendingPathExtension:filenameExtansion];
    NSURL *outputURL = [NSFileManager getTmpURLWithFilename:filename];
    BSLogCap(@"%@", outputURL);
    
    return outputURL;
}

#pragma mark -Nonstatic

- (instancetype)init {
    self = [super init];
    if (self) {
        // Create the main serialization queue.
        NSString *serializationQueueDescription = [NSString stringWithFormat:@"%@ serialization queue", self];
        self.mainSerializationQueue = dispatch_queue_create([serializationQueueDescription UTF8String], NULL);
        
        // Create the serialization queue to use for reading and writing the audio data.
        NSString *rwAudioSerializationQueueDescription = [NSString stringWithFormat:@"%@ rw audio serialization queue", self];
        self.rwAudioSerializationQueue = dispatch_queue_create([rwAudioSerializationQueueDescription UTF8String], NULL);
        
        // Create the serialization queue to use for reading and writing the video data.
        NSString *rwVideoSerializationQueueDescription = [NSString stringWithFormat:@"%@ rw video serialization queue", self];
        self.rwVideoSerializationQueue = dispatch_queue_create([rwVideoSerializationQueueDescription UTF8String], NULL);
    }
    
    return self;
}

- (void)exportAsset:(AVAsset *)asset toAudioFormat:(AudioFormatID)audioFormatID {
    NSString *avFileType;
    switch (audioFormatID) {
        case kAudioFormatLinearPCM:
            avFileType = AVFileTypeCoreAudioFormat;
            break;
        case kAudioFormatMPEG4AAC:
            avFileType = AVFileTypeMPEG4;
            break;
            
        default:
            BSLog(@"There is no AVFileType constant for audioFormat '%@'", [BSAudioFileHelper nameForAudioFormatID:audioFormatID]);

            if (self.failure) {
                self.failure(nil);
            }
            
            return;
    }
    
    NSError *error;
    self.outputCAFURL = [[self class] outputURLForAVFileType:avFileType error:error];
    if (!self.outputCAFURL) {
        if (self.failure) {
            self.failure(error);
        }

        return;
    }
    
    // Asynchronously load the tracks of the asset you want to read.
    [asset loadValuesAsynchronouslyForKeys:@[@"tracks"] completionHandler:^{
        // Once the tracks have finished loading, dispatch the work to the main serialization queue.
        dispatch_async(self.mainSerializationQueue, ^{
            // Due to asynchronous nature, check to see if user has already cancelled.
            if (self.cancelled) {
                return;
            }
            
            BOOL success = YES;
            NSError *localError;
            
            // Check for success of loading the assets tracks.
            success = ([asset statusOfValueForKey:@"tracks" error:&localError] == AVKeyValueStatusLoaded);

            if (success) {
                success = [self setupAssetReaderAndAssetWriterWithAsset:asset outputAudioFormat:audioFormatID error:&localError];
            }
            
            if (success) {
                success = [self startAssetReaderAndWriter:&localError];
            }
            
            if (!success) {
                [self readingAndWritingDidFinishSuccessfully:success withError:localError];
            }
        });
    }];
}

#if IS_LAME_EXISTS
- (void)exportAssetToMP3:(AVAsset *)asset {
    BSLog();
    
    self.exportToMP3 = YES;
    [self exportAssetToCAF:asset];
}
#endif

- (void)cancel {
    // Handle cancellation asynchronously, but serialize it with the main queue.
    dispatch_async(self.mainSerializationQueue, ^{
        // If we had audio data to reencode, we need to cancel the audio work.
        if (self.assetWriterAudioInput)
        {
            // Handle cancellation asynchronously again, but this time serialize it with the audio queue.
            dispatch_async(self.rwAudioSerializationQueue, ^{
                // Update the Boolean property indicating the task is complete and mark the input as finished if it hasn't already been marked as such.
                BOOL oldFinished = self.audioFinished;
                self.audioFinished = YES;
                if (oldFinished == NO)
                {
                    [self.assetWriterAudioInput markAsFinished];
                }
                // Leave the dispatch group since the audio work is finished now.
                dispatch_group_leave(self.dispatchGroup);
            });
        }
        
        if (self.assetWriterVideoInput)
        {
            // Handle cancellation asynchronously again, but this time serialize it with the video queue.
            dispatch_async(self.rwVideoSerializationQueue, ^{
                // Update the Boolean property indicating the task is complete and mark the input as finished if it hasn't already been marked as such.
                BOOL oldFinished = self.videoFinished;
                self.videoFinished = YES;
                if (oldFinished == NO)
                {
                    [self.assetWriterVideoInput markAsFinished];
                }
                // Leave the dispatch group, since the video work is finished now.
                dispatch_group_leave(self.dispatchGroup);
            });
        }
        // Set the cancelled Boolean property to YES to cancel any work on the main queue as well.
        self.cancelled = YES;
    });
}


#pragma - Private methods

- (BOOL)setupAssetReaderAndAssetWriterWithAsset:(AVAsset *)asset outputAudioFormat:(AudioFormatID)audioFormatID error:(NSError **)outError {
    // Create and initialize the asset reader.
    self.assetReader = [[AVAssetReader alloc] initWithAsset:asset error:outError];
    BOOL success = (self.assetReader != nil);
    if (success) {
        // If the asset reader was successfully initialized, do the same for the asset writer.
        self.assetWriter = [[AVAssetWriter alloc] initWithURL:self.outputCAFURL fileType:AVFileTypeQuickTimeMovie error:outError];
        success = (self.assetWriter != nil);
    }
    
    // If the reader and writer were successfully initialized, grab the audio and video asset tracks that will be used.
    if (success) {
        NSArray *audioTracks = [asset tracksWithMediaType:AVMediaTypeAudio];
        AVAssetTrack *assetAudioTrack = audioTracks.firstObject;

        NSArray *videoTracks = [asset tracksWithMediaType:AVMediaTypeVideo];
        AVAssetTrack *assetVideoTrack = videoTracks.firstObject;
        
        // If there is an audio track to read, set the decompression settings to Linear PCM and create the asset reader output.
        if (assetAudioTrack) {
            NSDictionary *decompressionAudioSettings = @{ AVFormatIDKey : @(kAudioFormatLinearPCM), };
            self.assetReaderAudioOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:assetAudioTrack outputSettings:decompressionAudioSettings];

            [self.assetReader addOutput:self.assetReaderAudioOutput];
            // Then, set the compression settings to 128kbps AAC and create the asset writer input.
            AudioChannelLayout stereoChannelLayout = {
                .mChannelLayoutTag = kAudioChannelLayoutTag_Stereo,
                .mChannelBitmap = 0,
                .mNumberChannelDescriptions = 0
            };
            NSData *channelLayoutAsData = [NSData dataWithBytes:&stereoChannelLayout length:offsetof(AudioChannelLayout, mChannelDescriptions)];
            
            /*The following keys are not allowed when format ID is 'aach' (kAudioFormatMPEG4AAC_HE): AVLinearPCMIsBigEndianKey, AVLinearPCMIsFloatKey, AVLinearPCMIsNonInterleaved, AVLinearPCMBitDepthKey'*/
            //                                                       AVLinearPCMIsBigEndianKey: @NO,
            //                                                       AVLinearPCMIsFloatKey: @NO,
            //                                                       AVLinearPCMIsNonInterleaved: @NO,
            //                                                       AVLinearPCMBitDepthKey: @16,
            
            /* The following keys are not allowed when format ID is 'lpcm' (kAudioFormatLinearPCM) */
            //                                                       AVEncoderAudioQualityKey: @(AVAudioQualityMax),
            //                                                       AVEncoderBitRateStrategyKey: AVAudioBitRateStrategy_Variable,
            //                                                       AVEncoderAudioQualityForVBRKey: @(AVAudioQualityMax),
            //                                                       AVEncoderBitRateKey   : [NSNumber numberWithInteger:128000],
            
            /* AVAssetWriterInput does not support: */
            //                                                       AVSampleRateConverterAudioQualityKey: @(AVAudioQualityMax),
            //                                                       AVEncoderAudioQualityKey: @(AVAudioQualityMax),
            NSDictionary *compressionAudioSettingsCustom;
            switch (audioFormatID) {
                case kAudioFormatMPEG4AAC:
                    compressionAudioSettingsCustom = @{ AVEncoderBitRateKey: @64000, };
                    break;
                case kAudioFormatLinearPCM:
                    compressionAudioSettingsCustom = @{ AVLinearPCMBitDepthKey: @16,
                                                        AVLinearPCMIsBigEndianKey: @NO,
                                                        AVLinearPCMIsFloatKey: @NO,
                                                        AVLinearPCMIsNonInterleaved: @NO, };
                    
                    
                default:
                    BSLog(@"There is no outputSettings for audioFormat '%@'", [BSAudioFileHelper nameForAudioFormatID:audioFormatID]);
                    
                    if (self.failure) {
                        self.failure(nil);
                    }
                    
                    return NO;
            }
            
            NSMutableDictionary *compressionAudioSettings = @{AVFormatIDKey: @(audioFormatID),
                                                              AVChannelLayoutKey: channelLayoutAsData,
                                                              AVSampleRateKey: @44100.f,
                                                              AVNumberOfChannelsKey: @2, }.mutableCopy;
            [compressionAudioSettings addEntriesFromDictionary:compressionAudioSettingsCustom];
            
            self.assetWriterAudioInput = [AVAssetWriterInput assetWriterInputWithMediaType:[assetAudioTrack mediaType] outputSettings:compressionAudioSettings];
            [self.assetWriter addInput:self.assetWriterAudioInput];
        }
        
        // If there is a video track to read, set the decompression settings for YUV and create the asset reader output.
        if (assetVideoTrack) {
            NSDictionary *decompressionVideoSettings = @{
                                                         (id)kCVPixelBufferPixelFormatTypeKey     : [NSNumber numberWithUnsignedInt:kCVPixelFormatType_422YpCbCr8],
                                                         (id)kCVPixelBufferIOSurfacePropertiesKey : [NSDictionary dictionary]
                                                         };
            self.assetReaderVideoOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:assetVideoTrack outputSettings:decompressionVideoSettings];
            [self.assetReader addOutput:self.assetReaderVideoOutput];
            CMFormatDescriptionRef formatDescription = NULL;
            // Grab the video format descriptions from the video track and grab the first one if it exists.
            NSArray *videoFormatDescriptions = [assetVideoTrack formatDescriptions];
            if ([videoFormatDescriptions count] > 0) {
                formatDescription = (__bridge CMFormatDescriptionRef)[videoFormatDescriptions objectAtIndex:0];
            }
            CGSize trackDimensions = {
                .width = 0.0,
                .height = 0.0,
            };
            // If the video track had a format description, grab the track dimensions from there. Otherwise, grab them direcly from the track itself.
            if (formatDescription)
                trackDimensions = CMVideoFormatDescriptionGetPresentationDimensions(formatDescription, false, false);
            else
                trackDimensions = [assetVideoTrack naturalSize];
            NSDictionary *compressionSettings = nil;
            // If the video track had a format description, attempt to grab the clean aperture settings and pixel aspect ratio used by the video.
            if (formatDescription)
            {
                NSDictionary *cleanAperture = nil;
                NSDictionary *pixelAspectRatio = nil;
                CFDictionaryRef cleanApertureFromCMFormatDescription = CMFormatDescriptionGetExtension(formatDescription, kCMFormatDescriptionExtension_CleanAperture);
                if (cleanApertureFromCMFormatDescription)
                {
                    cleanAperture = @{
                                      AVVideoCleanApertureWidthKey            : (id)CFDictionaryGetValue(cleanApertureFromCMFormatDescription, kCMFormatDescriptionKey_CleanApertureWidth),
                                      AVVideoCleanApertureHeightKey           : (id)CFDictionaryGetValue(cleanApertureFromCMFormatDescription, kCMFormatDescriptionKey_CleanApertureHeight),
                                      AVVideoCleanApertureHorizontalOffsetKey : (id)CFDictionaryGetValue(cleanApertureFromCMFormatDescription, kCMFormatDescriptionKey_CleanApertureHorizontalOffset),
                                      AVVideoCleanApertureVerticalOffsetKey   : (id)CFDictionaryGetValue(cleanApertureFromCMFormatDescription, kCMFormatDescriptionKey_CleanApertureVerticalOffset)
                                      };
                }
                CFDictionaryRef pixelAspectRatioFromCMFormatDescription = CMFormatDescriptionGetExtension(formatDescription, kCMFormatDescriptionExtension_PixelAspectRatio);
                if (pixelAspectRatioFromCMFormatDescription)
                {
                    pixelAspectRatio = @{
                                         AVVideoPixelAspectRatioHorizontalSpacingKey : (id)CFDictionaryGetValue(pixelAspectRatioFromCMFormatDescription, kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing),
                                         AVVideoPixelAspectRatioVerticalSpacingKey   : (id)CFDictionaryGetValue(pixelAspectRatioFromCMFormatDescription, kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing)
                                         };
                }
                // Add whichever settings we could grab from the format description to the compression settings dictionary.
                if (cleanAperture || pixelAspectRatio)
                {
                    NSMutableDictionary *mutableCompressionSettings = [NSMutableDictionary dictionary];
                    if (cleanAperture)
                        [mutableCompressionSettings setObject:cleanAperture forKey:AVVideoCleanApertureKey];
                    if (pixelAspectRatio)
                        [mutableCompressionSettings setObject:pixelAspectRatio forKey:AVVideoPixelAspectRatioKey];
                    compressionSettings = mutableCompressionSettings;
                }
            }
            // Create the video settings dictionary for H.264.
            NSMutableDictionary *videoSettings = (NSMutableDictionary *) @{
                                                                           AVVideoCodecKey  : AVVideoCodecH264,
                                                                           AVVideoWidthKey  : [NSNumber numberWithDouble:trackDimensions.width],
                                                                           AVVideoHeightKey : [NSNumber numberWithDouble:trackDimensions.height]
                                                                           };
            // Put the compression settings into the video settings dictionary if we were able to grab them.
            if (compressionSettings)
                [videoSettings setObject:compressionSettings forKey:AVVideoCompressionPropertiesKey];
            // Create the asset writer input and add it to the asset writer.
            self.assetWriterVideoInput = [AVAssetWriterInput assetWriterInputWithMediaType:[assetVideoTrack mediaType] outputSettings:videoSettings];
            [self.assetWriter addInput:self.assetWriterVideoInput];
        }
    }
    
    return success;
}

- (BOOL)startAssetReaderAndWriter:(NSError **)outError
{
    BOOL success = YES;
    // Attempt to start the asset reader.
    success = [self.assetReader startReading];
    if (!success)
        *outError = [self.assetReader error];
    if (success)
    {
        // If the reader started successfully, attempt to start the asset writer.
        success = [self.assetWriter startWriting];
        if (!success)
            *outError = [self.assetWriter error];
    }
    
    if (success)
    {
        // If the asset reader and writer both started successfully, create the dispatch group where the reencoding will take place and start a sample-writing session.
        self.dispatchGroup = dispatch_group_create();
        [self.assetWriter startSessionAtSourceTime:kCMTimeZero];
        self.audioFinished = NO;
        self.videoFinished = NO;
        
        if (self.assetWriterAudioInput)
        {
            // If there is audio to reencode, enter the dispatch group before beginning the work.
            dispatch_group_enter(self.dispatchGroup);
            // Specify the block to execute when the asset writer is ready for audio media data, and specify the queue to call it on.
            [self.assetWriterAudioInput requestMediaDataWhenReadyOnQueue:self.rwAudioSerializationQueue usingBlock:^{
                // Because the block is called asynchronously, check to see whether its task is complete.
                if (self.audioFinished)
                    return;
                BOOL completedOrFailed = NO;
                // If the task isn't complete yet, make sure that the input is actually ready for more media data.
                while ([self.assetWriterAudioInput isReadyForMoreMediaData] && !completedOrFailed)
                {
                    // Get the next audio sample buffer, and append it to the output file.
                    CMSampleBufferRef sampleBuffer = [self.assetReaderAudioOutput copyNextSampleBuffer];
                    if (sampleBuffer != NULL)
                    {
                        BOOL success = [self.assetWriterAudioInput appendSampleBuffer:sampleBuffer];
                        CFRelease(sampleBuffer);
                        sampleBuffer = NULL;
                        completedOrFailed = !success;
                    }
                    else
                    {
                        completedOrFailed = YES;
                    }
                }
                if (completedOrFailed)
                {
                    // Mark the input as finished, but only if we haven't already done so, and then leave the dispatch group (since the audio work has finished).
                    BOOL oldFinished = self.audioFinished;
                    self.audioFinished = YES;
                    if (oldFinished == NO)
                    {
                        [self.assetWriterAudioInput markAsFinished];
                    }
                    dispatch_group_leave(self.dispatchGroup);
                }
            }];
        }
        
        if (self.assetWriterVideoInput)
        {
            // If we had video to reencode, enter the dispatch group before beginning the work.
            dispatch_group_enter(self.dispatchGroup);
            // Specify the block to execute when the asset writer is ready for video media data, and specify the queue to call it on.
            [self.assetWriterVideoInput requestMediaDataWhenReadyOnQueue:self.rwVideoSerializationQueue usingBlock:^{
                // Because the block is called asynchronously, check to see whether its task is complete.
                if (self.videoFinished)
                    return;
                BOOL completedOrFailed = NO;
                // If the task isn't complete yet, make sure that the input is actually ready for more media data.
                while ([self.assetWriterVideoInput isReadyForMoreMediaData] && !completedOrFailed)
                {
                    // Get the next video sample buffer, and append it to the output file.
                    CMSampleBufferRef sampleBuffer = [self.assetReaderVideoOutput copyNextSampleBuffer];
                    if (sampleBuffer != NULL)
                    {
                        BOOL success = [self.assetWriterVideoInput appendSampleBuffer:sampleBuffer];
                        CFRelease(sampleBuffer);
                        sampleBuffer = NULL;
                        completedOrFailed = !success;
                    }
                    else
                    {
                        completedOrFailed = YES;
                    }
                }
                if (completedOrFailed)
                {
                    // Mark the input as finished, but only if we haven't already done so, and then leave the dispatch group (since the video work has finished).
                    BOOL oldFinished = self.videoFinished;
                    self.videoFinished = YES;
                    if (oldFinished == NO)
                    {
                        [self.assetWriterVideoInput markAsFinished];
                    }
                    dispatch_group_leave(self.dispatchGroup);
                }
            }];
        }
        // Set up the notification that the dispatch group will send when the audio and video work have both finished.
        dispatch_group_notify(self.dispatchGroup, self.mainSerializationQueue, ^{
            __block BOOL finalSuccess = YES;
            __block NSError *finalError = nil;
            
            // Check to see if the work has finished due to cancellation.
            if (self.cancelled) {
                // If so, cancel the reader and writer.
                [self.assetReader cancelReading];
                [self.assetWriter cancelWriting];
                
                // Call the method to handle completion, and pass in the appropriate parameters to indicate whether reencoding was successful.
                [self readingAndWritingDidFinishSuccessfully:finalSuccess withError:finalError];
            } else {
                // If cancellation didn't occur, first make sure that the asset reader didn't fail.
                if ([self.assetReader status] == AVAssetReaderStatusFailed) {
                    finalSuccess = NO;
                    finalError = [self.assetReader error];

                    // Call the method to handle completion, and pass in the appropriate parameters to indicate whether reencoding was successful.
                    [self readingAndWritingDidFinishSuccessfully:finalSuccess withError:finalError];
                }
                
                // If the asset reader didn't fail, attempt to stop the asset writer and check for any errors.
                if (finalSuccess) {
                    [self.assetWriter finishWritingWithCompletionHandler:^{
                        finalSuccess = (self.assetWriter.status == AVAssetWriterStatusCompleted);
                        if (!finalSuccess) {
                            finalError = self.assetWriter.error;
                        }

                        // Call the method to handle completion, and pass in the appropriate parameters to indicate whether reencoding was successful.
                        [self readingAndWritingDidFinishSuccessfully:finalSuccess withError:finalError];
                    }];
                }
            }
        });
    }
    
    // Return success here to indicate whether the asset reader and writer were started successfully.
    return success;
}

- (void)readingAndWritingDidFinishSuccessfully:(BOOL)success withError:(NSError *)error {
    if (success) {
        // Reencoding was successful, reset booleans.
        self.cancelled = NO;
        self.videoFinished = NO;
        self.audioFinished = NO;
        BSLogCap(@"readingAndWritingDidFinishSuccessfully url: %@", self.outputURL);
 
        if (self.exportToMP3) {
#if IS_LAME_EXISTS
            [self toMp3];
#endif
        } else {
            if (self.success) {
                self.success(self.outputCAFURL);
            }
        }
    } else {
        // If the reencoding process failed, we need to cancel the asset reader and writer.
        [self.assetReader cancelReading];
        [self.assetWriter cancelWriting];

        BSLog(@"readingAndWritingDidFinishSuccessfully:NO error:%@", error);
        
        if (self.failure) {
            self.failure(error);
        }
    }
}

#pragma mark -MP3 converting

#if IS_LAME_EXISTS
- (void)toMp3 {
    NSString *cafFilePath = self.outputCAFURL.path;

    NSError *error;
    NSURL *mp3FileURL = [[self class] outputURLForAVFileType:AVFileTypeMPEGLayer3 error:error];
    if (!mp3FileURL) {
        if (self.failure) {
            self.failure(error);
        }
        
        return;
    }
    NSString *mp3FilePath = mp3FileURL.path;
    
    @try {
        int write;
        size_t read;
        
        FILE *pcm = fopen([cafFilePath cStringUsingEncoding:1], "rb");  //source
        fseek(pcm, 4 * 1024, SEEK_CUR);                                   //skip file header
        FILE *mp3 = fopen([mp3FilePath cStringUsingEncoding:1], "wb");  //output
        
        const int PCM_SIZE = 8192;
        const int MP3_SIZE = 8192;
        short int pcm_buffer[PCM_SIZE * 2];
        unsigned char mp3_buffer[MP3_SIZE];
        
        lame_t lame = lame_init();
        lame_set_in_samplerate(lame, 44100);
        lame_set_VBR(lame, vbr_default);
//        lame_set_quality(lame, 9);
        lame_init_params(lame);
        
        do {
            read = fread(pcm_buffer, 2 * sizeof(short int), PCM_SIZE, pcm);
            if (read == 0) {
                write = lame_encode_flush(lame, mp3_buffer, MP3_SIZE);
            } else {
                write = lame_encode_buffer_interleaved(lame, pcm_buffer, (int)read, mp3_buffer, MP3_SIZE);
            }
            fwrite(mp3_buffer, write, 1, mp3);
            
        } while (read != 0);
        
        lame_close(lame);
        fclose(mp3);
        fclose(pcm);
    }
    @catch (NSException *exception) {
        BSLog(@"%@", [exception description]);
        
        error = [NSError errorWithDomain:@"com.stasiuk.bogdan.mediaexplorer" code:0 userInfo:exception.userInfo];
    }
    @finally {
        [self convertMp3Finish:mp3FileURL error:error];
    }
}

- (void)convertMp3Finish:(NSURL *)mp3FileURL error:(NSError *)error {
    if (error) {
        BSLog(@"%@", error);
        
        if (self.failure) {
            self.failure(error);
        }
        
        return;
    }
    
    NSString *filePath = mp3FileURL.path;
    
    NSInteger fileSize =  [self getFileSize:filePath];
    NSString *fileSizeString = [NSString stringWithFormat:@"%ld kb", (long)fileSize / 1024];
    
    BSLog(@"%@ %@", filePath, fileSizeString);
    
    if (self.success) {
        self.success(mp3FileURL);
    }
}
#endif

- (NSInteger) getFileSize:(NSString*) path
{
    NSFileManager * filemanager = [NSFileManager new];
    if([filemanager fileExistsAtPath:path]){
        NSDictionary * attributes = [filemanager attributesOfItemAtPath:path error:nil];
        NSNumber *theFileSize;
        if ( (theFileSize = [attributes objectForKey:NSFileSize]) )
            return  [theFileSize intValue];
        else
            return -1;
    }
    else
    {
        return -1;
    }
}

@end
