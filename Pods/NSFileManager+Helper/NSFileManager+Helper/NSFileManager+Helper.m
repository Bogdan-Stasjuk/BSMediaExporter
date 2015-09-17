//
//  NSFileManager+Helper.m
//
//  Created by Bogdan Stasjuk on 6/12/15.
//  Copyright (c) 2015 Bogdan Stasjuk. All rights reserved.
//

#import "NSFileManager+Helper.h"


#define BSLog(fmt, ...) NSLog((@"%s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)


@implementation NSFileManager (Helper)

+ (NSURL *)getTmpURLWithFilename:(NSString *)filename {
    NSString *tmpFolder = [NSHomeDirectory() stringByAppendingPathComponent:@"tmp"];
    NSString *tmpPathToFile = [tmpFolder stringByAppendingPathComponent:filename];
    if ([[[self class] defaultManager] fileExistsAtPath:tmpPathToFile]) {
        NSError *error;
        if (![[NSFileManager defaultManager] removeItemAtPath:tmpPathToFile error:&error]) {
            BSLog(@"[[NSFileManager defaultManager] removeItemAtPath:%@ error:%@]", tmpPathToFile, error);
            
            return nil;
        }
    }
    
    return [NSURL fileURLWithPath:tmpPathToFile];
}

+ (BOOL)createFile:(NSString *)filepath {
  if (![[[self class] defaultManager] fileExistsAtPath:filepath]) {
    if (![[[self class] defaultManager] createFileAtPath:filepath contents:nil attributes:nil]) {
      BSLog(@"Could not create file \"%@\". Error's code: %d. Error's message: %s", filepath, errno, strerror(errno));

      return NO;
    }
  }
  
  return YES;
}

+ (unsigned long long)fileSize:(NSString *)path {
  NSError *error;
  NSDictionary *attributes = [[[self class] defaultManager] attributesOfItemAtPath:path error:&error];
  if (attributes) {
    return [attributes fileSize];
  } else {
    BSLog(@"[[NSFileManager defaultManager] attributesOfItemAtPath:%@ error:%@]", path, error);

    return 0;
  }
}

@end
