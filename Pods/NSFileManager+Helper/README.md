# NSFileManager+Helper
Helper methods for widening functionality of NSFileManager.


##Methods

```objc
+ (BOOL)createFile:(NSString *)filepath;
+ (unsigned long long)fileSize:(NSString *)path;

+ (NSURL *)getTmpURLWithFilename:(NSString *)filename;
```


Demo
====

Clone project and run it. You can find examples of usage at `ViewController.m`.


Compatibility
=============

This class has been tested back to iOS 7.0.


Installation
============

__Cocoapods__: `pod 'NSFileManager+Helper'`<br />
__Manual__: Copy the __NSFileManager+Helper__ folder in your project<br />

Import header in your project. .pch is a good place ;)

    #import "NSFileManager+Helper.h"

License
=======

This code is released under the MIT License. See the LICENSE file for
details.
