# BSMediaExporter
Class for exporting and converting media files.
It was tested for M4A input and MPEG4AAC or LinearPCM output.
Also LinearPCM output can be converted to MP3 if you'll add LAME.framework to your project.


##Properties
```objc
@property (copy, nonatomic) void (^success)(NSURL *exportedURL);
@property (copy, nonatomic) void (^failure)(NSError *error);
@property (assign, readonly, nonatomic) CGFloat progress;
```


##Methods
```objc
+ (NSURL *)outputURLForAVFileType:(NSString *)avFileType error:(NSError *)error;
- (void)exportAsset:(AVAsset *)asset toAudioFormat:(AudioFormatID)audioFormatID;
- (void)exportAssetToMP3:(AVAsset *)asset;
```


##Project uses next pods:

```objc
pod 'BSMacros'
pod 'BSAudioFileHelper'
pod 'NSFileManager+Helper'
```


Compatibility
=============

This class has been tested back to iOS 7.0.


Installation
============

__CocoaPods__: `pod 'BSMediaExporter'`<br />
__Manual__: Copy the __BSMediaExporter__ folder in your project<br />

Import header in your project.

    #import "BSMediaExporter.h"

License
=======

This code is released under the MIT License. See the LICENSE file for
details.
