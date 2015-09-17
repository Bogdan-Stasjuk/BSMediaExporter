//
//  NSFileManager+Helper.h
//
//  Created by Bogdan Stasjuk on 6/12/15.
//  Copyright (c) 2015 Bogdan Stasjuk. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface NSFileManager (Helper)

+ (BOOL)createFile:(NSString *)filepath;
+ (unsigned long long)fileSize:(NSString *)path;

/*!
 * @discussion creates URL to the 'filename' at home directory inside 'tmp' folder. Removes file if one already exists
 * @param filename Name of the file
 * @return URL to the file with filename or nil if file exists and can't be removed
 */
+ (NSURL *)getTmpURLWithFilename:(NSString *)filename;

@end
