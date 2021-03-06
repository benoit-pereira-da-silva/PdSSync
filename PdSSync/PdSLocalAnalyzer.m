//
//  PdSSynchronizer.m
//  PdSSyncCL
//
//  Created by Benoit Pereira da Silva on 26/11/2013.
//  Copyright (c) 2013 Pereira da Silva. All rights reserved.
//

#import "PdSLocalAnalyzer.h"

@interface PdSLocalAnalyzer(){
}
@end


@implementation PdSLocalAnalyzer

-(id)init{
    self=[super init];
    if(self){
        self.recomputeHash=NO;
        self.saveHashInAFile=YES;
    }
    return self;
}


/**
 *  Creates a dictionary with  relative paths as key and  CRC32 as value
 *
 *  @param url the folder url
 *  @param dataBlock if you define this block it will be used to extract the data from the file
 *  @param progressBlock the progress block
 *  @param completionBlock the completion block.
 *
 */
- (void)createHashMapFromLocalFolderURL:(NSURL*)folderURL
                              dataBlock:(NSData* (^)(NSString*path, NSUInteger index))dataBlock
                          progressBlock:(void(^)(NSString*hash,NSString*path, NSUInteger index))progressBlock
                     andCompletionBlock:(void(^)(HashMap*hashMap))completionBlock{
    
    NSString *folderPath=[folderURL path];
    PdSFileManager*fileManager=[PdSFileManager sharedInstance] ;
    HashMap*hashMap=[[HashMap alloc]init];
    if([fileManager fileExistsAtPath:folderPath]){
        NSArray*exclusion=@[@".DS_Store"];
        NSArray *keys = [NSArray arrayWithObject:NSURLIsDirectoryKey];
        NSDirectoryEnumerator *dirEnum =[fileManager enumeratorAtURL:folderURL
                                          includingPropertiesForKeys:keys
                                                             options:0
                                                        errorHandler:^BOOL(NSURL *url, NSError *error) {
                                                            NSLog(@"ERROR when enumerating  %@ %@",url, [error localizedDescription]);
                                                            return YES;
                                                        }];
        
        
        NSURL *file;
        int i=0;
        while ((file = [dirEnum nextObject])) {
            NSString *filePath=[NSString filteredFilePathFrom:[file absoluteString]];
            NSString *pathExtension=file.pathExtension;
            NSNumber *isDirectory;
            [file getResourceValue:&isDirectory
                            forKey:NSURLIsDirectoryKey error:nil];
            
            if([exclusion indexOfObject:[file lastPathComponent]]==NSNotFound
               && ![pathExtension isEqualToString:kPdSSyncHashFileExtension]
               && [filePath rangeOfString:kPdSSyncPrefixSignature].location==NSNotFound
               ){
                @autoreleasepool {
                    NSData *data=nil;
                    NSString*hashfile=[filePath stringByAppendingFormat:@".%@",kPdSSyncHashFileExtension];
                    NSString *relativePath=[filePath stringByReplacingOccurrencesOfString:[folderPath stringByAppendingString:@"/"] withString:@""];
                    if([isDirectory boolValue]){
                        relativePath=[relativePath stringByAppendingString:@"/"];
                    }
                    // we check if there is a file.extension.kPdSSyncHashFileExtension
                    if(!self.recomputeHash && [fileManager fileExistsAtPath:hashfile] ){
                        NSError*crc32ReadingError=nil;
                        NSString*crc32String=[NSString stringWithContentsOfFile:filePath
                                                                       encoding:NSUTF8StringEncoding
                                                                          error:&crc32ReadingError];
                        if(!crc32ReadingError){
                            progressBlock(crc32String,relativePath,i);
                        }else{
                            NSLog(@"ERROR when reading crc32 from %@ %@",filePath,[crc32ReadingError localizedDescription]);
                        }
                    }else{
                        if (dataBlock) {
                            data=dataBlock(filePath,i);
                        }else{
                            data=[NSData dataWithContentsOfFile:filePath];
                        }
                    }
                    uint32_t crc32=(uint32_t)[data crc32];
                    NSString*crc32String=[NSString stringWithFormat:@"%@",@(crc32)];
                    if (crc32==0){
                        // Include the folders.
                        // We use the relative path as CRC32
                        crc32=[[relativePath dataUsingEncoding:NSUTF8StringEncoding] crc32];
                    }
                    if(crc32!=0){
                        [hashMap setSyncHash:crc32String
                                     forPath:relativePath];
                        i++;
                        if(self.saveHashInAFile){
                            [self _writeCrc32:crc32String
                               toFileWithPath:filePath];
                        }
                        if(progressBlock)
                            progressBlock(crc32String,relativePath,i);
                    }
                }
            }
            
            if(!self.saveHashInAFile && [pathExtension isEqualToString:kPdSSyncHashFileExtension]){
                NSError*removeFile=nil;
                [fileManager removeItemAtPath:filePath error:&removeFile];
            }
        }
    }
    
    [self saveHashMap:hashMap
          toFolderUrl:folderURL];
    completionBlock(hashMap);
}



- (void)saveHashMap:(HashMap*)hashMap toFolderUrl:(NSURL*)folderURL{
    PdSFileManager*fileManager=[PdSFileManager sharedInstance] ;
    // We gonna create the hashmap folder
    NSString*hashMapFileP=[[folderURL absoluteString] stringByAppendingFormat:@"%@%@.%@",kPdSSyncMetadataFolder,kPdSSyncHashMashMapFileName,kPdSSyncHashFileExtension];
    [fileManager createRecursivelyRequiredFolderForPath:[hashMapFileP  filteredFilePath]];
    
    // Let s write the serialized HashMap file
    NSDictionary*dictionaryHashMap=[hashMap dictionaryRepresentation];
    NSString*json=[self _encodetoJson:dictionaryHashMap];
    NSError*error;
    hashMapFileP=[hashMapFileP filteredFilePath];
    [json writeToFile:hashMapFileP
           atomically:YES
             encoding:NSUTF8StringEncoding
                error:&error];
    if(error){
        NSLog(@"ERROR when writing hashmap to %@ %@", [error description],hashMapFileP);
        
    }

}



#pragma mark - private


- (BOOL)_writeCrc32:(NSString*)crc32 toFileWithPath:(NSString*)path{
    NSError *crc32WritingError=nil;
    NSString *crc32Path=[path stringByAppendingFormat:@".%@",kPdSSyncHashFileExtension];

    [crc32 writeToFile:crc32Path
                  atomically:YES
                    encoding:NSUTF8StringEncoding
                       error:&crc32WritingError];
    if(crc32WritingError){
        return NO;
    }else{
        return YES;
    }
}


- (NSString*)_encodetoJson:(id)object{
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:object
                                                       options:NSJSONWritingPrettyPrinted
                                                         error:&error];
    if (!jsonData) {
        return [error localizedDescription];
    } else {
        return [[NSString alloc]initWithBytes:[jsonData bytes]
                                       length:[jsonData length] encoding:NSUTF8StringEncoding];
    }
}



@end