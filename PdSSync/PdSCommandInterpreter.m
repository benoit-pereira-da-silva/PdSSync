//
//  PdSCommandInterpreter.m
//  PdSSync
//
//  Created by Benoit Pereira da Silva on 11/03/2014.
//

// This Current implementation relies on http://cocoadocs.org/docsets/AFNetworking/2.2.0/

#import "AFNetworking.h"
#import "PdSCommandInterpreter.h"
#include <stdarg.h>


#warning NEED TO QUALIFY Path issue on iOS (filtering createRecursive path)
#define kUSELowerMemoryApproach YES


NSString * const PdSSyncInterpreterWillFinalize = @"PdSSyncInterpreterWillFinalize";
NSString * const PdSSyncInterpreterHasFinalized = @"PdSSyncInterpreterHasFinalized";

// We have removed a fix inspired by https://github.com/AFNetworking/AFNetworking/issues/1398
// Some servers responds a 411 status when there is no content length
// We donnot  want to patch as it is related to an Apple related bug.
// Fix the issue server side


typedef void(^ProgressBlock_type)(uint taskIndex,float progress);
typedef void(^CompletionBlock_type)(BOOL success,NSString*message);

@interface PdSCommandInterpreter (){
    CompletionBlock_type             _completionBlock;
    ProgressBlock_type               _progressBlock;
    PdSFileManager                  *_fileManager;
    AFHTTPSessionManager            *_HTTPsessionManager;
    NSMutableArray                  *_allCommands;
    BOOL                            _sanitizeAutomatically;
    BOOL                            _hasBeenInterrupted;
    int                             _messageCounter;
    
}
@property (nonatomic,strong)NSOperationQueue *queue;
@end

@implementation PdSCommandInterpreter

@synthesize bunchOfCommand  = _bunchOfCommand;
@synthesize context         = _context;

/**
 *
 *
 *  @param bunchOfCommand  the bunch of command
 *  @param context         the interpreter context
 *  @param progressBlock   the progress block
 *  @param completionBlock te completion block
 *
 *  @return the interpreter
 */
+ (PdSCommandInterpreter*)interpreterWithBunchOfCommand:(NSArray*)bunchOfCommand
                                                context:(PdSSyncContext*)context
                                          progressBlock:(void(^)(uint taskIndex,float progress))progressBlock
                                     andCompletionBlock:(void(^)(BOOL success,NSString*message))completionBlock{
    return [[PdSCommandInterpreter alloc] initWithBunchOfCommand:bunchOfCommand
                                                         context:context
                                                   progressBlock:progressBlock
                                              andCompletionBlock:completionBlock];
}

/**
 *   The dedicated initializer.
 *
 *  @param bunchOfCommand  the bunch of command
 *  @param context         the interpreter context
 *  @param progressBlock   the progress block
 *  @param completionBlock te completion block
 *
 *  @return the interpreter
 */
- (instancetype)initWithBunchOfCommand:(NSArray*)bunchOfCommand
                               context:(PdSSyncContext*)context
                         progressBlock:(void(^)(uint taskIndex,float progress))progressBlock
                    andCompletionBlock:(void(^)(BOOL success,NSString*message))completionBlock;{
    self=[super init];
    if(self){
        self->_bunchOfCommand=[bunchOfCommand copy];
        self->_context=context;
        self->_progressBlock=progressBlock?[progressBlock copy]:nil;
        self->_completionBlock=completionBlock?[completionBlock copy]:nil;
        self->_fileManager=[PdSFileManager sharedInstance];
        self->_progressCounter=0;
        self->_messageCounter=0;
        self->_sanitizeAutomatically=YES;
        if(self->_context.mode==SourceIsDistantDestinationIsDistant ){
            [NSException raise:@"TemporaryException"
                        format:@"SourceIsDistantDestinationIsDistant is currently not supported"];
        }
        if(self->_context.mode==SourceIsLocalDestinationIsLocal ){
            [NSException raise:@"TemporaryException"
                        format:@"SourceIsLocalDestinationIsLocal is currently not supported"];
        }
        if([context isValid] && _bunchOfCommand){
            self.queue=[[NSOperationQueue alloc] init];
            self.queue.name=[NSString stringWithFormat:@"com.pereira-da-silva.PdSSync.CommandInterpreter.%@",@([self hash])];
            [self.queue setMaxConcurrentOperationCount:1];// Sequential
            [self _setUpManager];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self _run];
            });
        }else{
            if(self->_completionBlock){
                _completionBlock(NO,@"sourceUrl && destinationUrl && bunchOfCommand && finalHashMap are required");
            }
        }
    }
    return self;
}


+(id)encodeCreate:(NSString*)source destination:(NSString*)destination{
    if(source && destination){
        return [NSString stringWithFormat:@"[%@,\"%@\",\"%@\"]", @(PdSCreate),destination,source];
    }
    return nil;
}

+(id)encodeUpdate:(NSString*)source destination:(NSString*)destination{
    if(source && destination){
        return [NSString stringWithFormat:@"[%@,\"%@\",\"%@\"]", @(PdSUpdate),destination,source];
    }
    return nil;
}

+(id)encodeCopy:(NSString*)source destination:(NSString*)destination{
    if(source && destination){
        return [NSString stringWithFormat:@"[%@,\"%@\",\"%@\"]",@(PdSCopy),destination,source];
    }else{
        return nil;
    }
}

+(id)encodeMove:(NSString*)source destination:(NSString*)destination{
    if(source && destination){
        return [NSString stringWithFormat:@"[%@,\"%@\",\"%@\"]", @(PdSMove),destination,source];
    }else{
        return nil;
    }
}

+(id)encodeRemove:(NSString*)destination{
    if(destination){
        return [NSString stringWithFormat:@"[%@,\"%@\"]", @(PdSDelete),destination];
    }else{
        return nil;
    }
}


#pragma mark - private methods

- (void)_run{
    _hasBeenInterrupted=NO;
    if(_sanitizeAutomatically){
        [self _sanitize:@""];
    }
    
    if([_bunchOfCommand count]>0){
        PdSCommandInterpreter * __weak weakSelf=self;
        NSMutableArray*__block creativeCommands=[NSMutableArray array];
        _allCommands=[NSMutableArray array];
        
        // First pass we dicriminate creative for un creative commands
        // Creative commands requires for example download or an upload.
        // Copy or move are "not creative" as we move or copy a existing resource
        for (id encodedCommand in _bunchOfCommand) {
            NSArray*cmdAsAnArray=[self _encodedCommandToArray:encodedCommand];
            if (!_hasBeenInterrupted) {
                
                
                if(cmdAsAnArray){
                    if([[cmdAsAnArray objectAtIndex:0] intValue]==PdSCreate||
                       [[cmdAsAnArray objectAtIndex:0] intValue]==PdSUpdate){
                        [creativeCommands addObject:cmdAsAnArray];
                    }
                    [_allCommands addObject:cmdAsAnArray];
                }
                if(![encodedCommand isKindOfClass:[NSString class]]){
                    [self _interruptOnFault:[NSString stringWithFormat:@"Illegal command %@",encodedCommand]];
                }
            }
        }
        if (!_hasBeenInterrupted) {
            for (NSArray*cmd in creativeCommands) {
                [self->_queue addOperationWithBlock:^{
                    [weakSelf _runCommandFromArrayOfArgs:cmd];
                }];
            }
            
            [_queue addOperationWithBlock:^{
                [[NSNotificationCenter defaultCenter] postNotificationName:PdSSyncInterpreterWillFinalize
                                                                    object:self];
            }];
            [_queue addOperationWithBlock:^{
                if(self.finalizationDelegate){
                    [self.finalizationDelegate readyForFinalization:self];
                }else{
                    [self finalize];
                }
            }];
        }
    }else{
        if(_sanitizeAutomatically){
            dispatch_async(dispatch_get_main_queue(), ^{
                [self _sanitize:@""];
            });
        }
        _completionBlock(YES,@"There was no command to execute");
    }
}


/**
 * Called by the delegate to conclude the operations
 */
- (void)finalize{
    // The creative commands will produce UNPREFIXING temp files
    // The "unCreative" commands will be executed during finalization
    [self _finalizeWithCommands:_allCommands];
    if(_sanitizeAutomatically){
        [self _sanitize:@""];
    }
}


-(void)_sanitize:(NSString*)relativePath{
    if (self->_context.mode==SourceIsDistantDestinationIsLocal||
        self->_context.mode==SourceIsLocalDestinationIsLocal){
        // SANITIZE LOCALLY
        NSString *folderPath=[self _absoluteLocalPathFromRelativePath:relativePath
                                                           toLocalUrl:_context.destinationBaseUrl
                                                           withTreeId:_context.destinationTreeId
                                                            addPrefix:NO];
        
        NSArray *keys = [NSArray arrayWithObject:NSURLIsDirectoryKey];
        NSDirectoryEnumerator *dirEnum =[_fileManager enumeratorAtURL:[NSURL URLWithString:folderPath]
                                           includingPropertiesForKeys:keys
                                                              options:0
                                                         errorHandler:^BOOL(NSURL *url, NSError *error) {
                                                             [self _progressMessage:@"ERROR when enumerating  %@ %@",url, [error localizedDescription]];
                                                             return YES;
                                                         }];
        NSURL *file;
        NSError*removeFileError=nil;
        while ((file = [dirEnum nextObject])) {
            NSString *filePath=[file absoluteString];
            if([self _filePathDeletionAllowed:filePath]){
                [_fileManager removeItemAtPath:[filePath filteredFilePath]
                                         error:&removeFileError];
            }
        }
        
        if(!removeFileError){
            [self _nextCommand];
        }else{
            [self _interruptOnFault:@"Sanitizing error"];
        }
    }
}


- (BOOL)_filePathDeletionAllowed:(NSString*)path{
    NSArray*exclusion=@[@".DS_Store"];
    NSInteger minPrefixedLength=30+[kPdSSyncPrefixSignature length];
    if([[path lastPathComponent] length]>minPrefixedLength&&
       [exclusion indexOfObject:[path lastPathComponent]]==NSNotFound&&
       [[path lastPathComponent] rangeOfString:kPdSSyncPrefixSignature].location!=NSNotFound &&
       ![[path substringFromIndex:[path length]-1] isEqualToString:@"/"]
       ){
        return YES;
    }else{
        return NO;
    }
}



- (void)_successFullEnd{
    dispatch_async(dispatch_get_main_queue(), ^{
        _completionBlock(YES,nil);
        [[NSNotificationCenter defaultCenter] postNotificationName:PdSSyncInterpreterHasFinalized
                                                            object:self];
    });
}


- (void)_interruptOnFault:(NSString*)faultMessage{
    [self _progressMessage:@"INTERUPT ON FAULT %@",faultMessage];
    // This method is never called on reachability issues.
    [self->_queue cancelAllOperations];
    self->_hasBeenInterrupted=YES;
    self->_completionBlock(NO,faultMessage);
}


- (NSArray*)_encodedCommandToArray:(NSString*)encoded{
    NSData *data = [encoded dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error;
    id cmd = [NSJSONSerialization JSONObjectWithData:data
                                             options:0
                                               error:&error];
    if(error && !encoded){
        // We stop the process on any error
        [self _interruptOnFault:[NSString stringWithFormat:@"Cmd deserialization failed %@ : %@",encoded,[error localizedDescription]]];
    }
    if(cmd && [cmd isKindOfClass:[NSArray class]] && [cmd count]>0){
        return cmd;
    }else{
        [self _interruptOnFault:[NSString stringWithFormat:@"Invalid command (encoding) : %@, %@",encoded,cmd]];
    }
    return nil;
}


-(void)_runCommandFromArrayOfArgs:(NSArray*)cmd{
    
    [self _commandInProgress];
    if(cmd && [cmd isKindOfClass:[NSArray class]] && [cmd count]>0){
        int cmdName=[[cmd objectAtIndex:0] intValue];
        NSString*arg1= [cmd count]>1?[cmd objectAtIndex:1]:nil;
        NSString*arg2=[cmd count]>2?[cmd objectAtIndex:2]:nil;
        switch (cmdName) {
            case (PdSCreate):{
                if(arg1 && arg2){
                    [self _runCreateOrUpdate:arg2 destination:arg1];
                }else{
                    [self _interruptOnFault:[NSString stringWithFormat:@"Invalid command PdSCreate : %i arg1:%@ arg2:%@",cmdName,arg1?arg1:@"nil",arg2?arg2:@"nil"]];
                }
                break;
            }
            case (PdSUpdate):{
                if(arg1 && arg2){
                    [self _runCreateOrUpdate:arg2 destination:arg1];
                }else{
                    [self _interruptOnFault:[NSString stringWithFormat:@"Invalid command PdSUpdate : %i arg1:%@ arg2:%@",cmdName,arg1?arg1:@"nil",arg2?arg2:@"nil"]];
                }
                break;
            }
            case (PdSCopy):{
                if(arg1 && arg2){
                    [self _runCopy:arg2 destination:arg1];
                }else{
                    [self _interruptOnFault:[NSString stringWithFormat:@"Invalid command PdSCopy : %i arg1:%@ arg2:%@",cmdName,arg1?arg1:@"nil",arg2?arg2:@"nil"]];
                }
                break;
            }
            case (PdSMove):{
                if(arg1 && arg2){
                    [self _runMove:arg2 destination:arg1];
                }else{
                    [self _interruptOnFault:[NSString stringWithFormat:@"Invalid command PdSMove : %i arg1:%@ arg2:%@",cmdName,arg1?arg1:@"nil",arg2?arg2:@"nil"]];
                }
                break;
            }
            case (PdSDelete):{
                if(arg1){
                    [self _runDelete:arg1];
                }else{
                    [self _interruptOnFault:[NSString stringWithFormat:@"Invalid command PdSDelete : %i arg1:%@ ",cmdName,arg1?arg1:@"nil"]];
                }
                break;
            }
            default:
                [self _interruptOnFault:[NSString stringWithFormat:@"The command default %i is currently not supported",cmdName]];
                break;
        }
    }else{
        [self _interruptOnFault:[NSString stringWithFormat:@"Invalid command global %@",cmd?cmd:@"nil"]];
    }
}


- (void)_commandInProgress{
    [_queue setSuspended:YES];
}

- (void)_nextCommand{
    dispatch_async(dispatch_get_main_queue(), ^{
        _progressCounter++;
        [_queue setSuspended:NO];
    });
}




#pragma  mark - command runtime


-(void)_runCreateOrUpdate:(NSString*)source destination:(NSString*)destination{
    //NSLog(@"_runCreateOrUpdate %@", [_context contextDescription]);
    if((self->_context.mode==SourceIsLocalDestinationIsDistant)){
        // UPLOAD
        //_context.destinationBaseUrl;
        PdSCommandInterpreter *__weak weakSelf=self;
        NSURL *sourceURL=[_context.sourceBaseUrl URLByAppendingPathComponent:[ NSString stringWithFormat:@"%@/%@",_context.sourceTreeId,source]];
        NSString *URLString =[[_context.destinationBaseUrl absoluteString] stringByAppendingFormat:@"uploadFileTo/tree/%@/",_context.destinationTreeId];
        NSDictionary *parameters = @{
                                     @"syncIdentifier": _context.syncID,
                                     @"destination":destination,
                                     @"doers":@"",
                                     @"undoers":@""};// @todo find a solution for doers / undoers if possible
        
        NSMutableURLRequest *request = [[AFHTTPRequestSerializer serializer] multipartFormRequestWithMethod:@"POST"
                                                                                                  URLString:URLString
                                                                                                 parameters:parameters
                                                                                  constructingBodyWithBlock:^(id<AFMultipartFormData> formData) {
                                                                                      NSString*lastChar=[source substringFromIndex:[source length]-1];
                                                                                      if(![lastChar isEqualToString:@"/"]){
                                                                                          [formData appendPartWithFileURL:sourceURL
                                                                                                                     name:@"source"
                                                                                                                 fileName:[destination lastPathComponent]
                                                                                                                 mimeType:@"application/octet-stream"
                                                                                                                    error:nil];
                                                                                      }else{
                                                                                          // It is a folder.
                                                                                      }
                                                                                      [self _progressMessage:@"Uploading %@", [sourceURL absoluteString]];
                                                                                  } error:nil];
        
        NSProgress* progress=nil;
        NSURLSessionUploadTask *uploadTask = [_HTTPsessionManager uploadTaskWithStreamedRequest:request
                                                                                       progress:&progress
                                                                              completionHandler:^(NSURLResponse *response, id responseObject, NSError *error) {
                                                                                  /*
                                                                                   [progress removeObserver:weakSelf
                                                                                   forKeyPath:@"fractionCompleted"
                                                                                   context:NULL];
                                                                                   */
                                                                                  
                                                                                  if ([(NSHTTPURLResponse*)response statusCode]!=201 && error) {
                                                                                      NSString *msg=[NSString stringWithFormat:@"Error when uploading %@",[weakSelf _stringFromError:error]];
                                                                                      [weakSelf _interruptOnFault:msg];
                                                                                  } else {
                                                                                      [weakSelf _nextCommand];
                                                                                  }
                                                                              }];
        
        
        /*
         [progress addObserver:self
         forKeyPath:@"fractionCompleted"
         options:NSKeyValueObservingOptionNew
         context:NULL];*/
        
        [uploadTask resume];
        
        
        
    }else if (self->_context.mode==SourceIsDistantDestinationIsLocal){
        
        PdSCommandInterpreter *__weak weakSelf=self;
        
        // If it is a folder we gonna create it directly
        
        BOOL isAFolder= [[destination substringFromIndex:[destination length]-1] isEqualToString:@"/"];
        if(isAFolder){
            NSString*localFolderPath=[self _absoluteLocalPathFromRelativePath:destination
                                                                   toLocalUrl:_context.destinationBaseUrl
                                                                   withTreeId:_context.destinationTreeId
                                                                    addPrefix:NO];
            if([_fileManager createRecursivelyRequiredFolderForPath:localFolderPath]){
                [self _nextCommand];
            }else{
                NSString *msg=[NSString stringWithFormat:@"Error when creating %@",localFolderPath];
                [self _interruptOnFault:msg];
                return;
            }
            
        }else{
            // DOWNLOAD
            NSString*treeId=_context.sourceTreeId;
            // Decompose in a GET for the URI then a download task
            
            
            NSString *URLString =[[_context.sourceBaseUrl absoluteString] stringByAppendingFormat:@"file/tree/%@/",treeId];
            NSDictionary *parameters = @{
                                         @"path": [source copy],
                                         @"redirect":@"false",
                                         @"returnValue":@"false"
                                         };
            
            [_HTTPsessionManager GET:URLString
                          parameters:parameters
                             success:^(NSURLSessionDataTask *task, id responseObject) {
                                 NSDictionary*d=(NSDictionary*)responseObject;
                                 NSString*uriString=[d objectForKey:@"uri"];
                                 [self _progressMessage:@"Downloading %@ \nFrom %@", uriString,URLString];
                                 if(uriString && [uriString isKindOfClass:[NSString class]]){
                                     [weakSelf _download:uriString toDestination:[destination copy]];
                                 }else{
                                     [weakSelf _interruptOnFault:[NSString stringWithFormat:@"Missing url in response of %@",task.currentRequest.URL.absoluteString]];
                                 }
                             } failure:^(NSURLSessionDataTask *task, NSError *error) {
                                 [self _progressMessage:@"FAILURE before GET File @URI %@", URLString];
                                 [weakSelf _interruptOnFault:[weakSelf _stringFromError:error]];
                             }];
            
            
        }
        
        ;
        
        
    }else if (self->_context.mode==SourceIsLocalDestinationIsLocal){
        // It is a copy
        [self _runCopy:source destination:destination];
    }else if (self->_context.mode==SourceIsDistantDestinationIsDistant){
        // CURRENTLY NOT SUPPORTED
    }
}


- (void)_download:(NSString*)uriString toDestination:(NSString*)destination{
    NSURLRequest *fileRequest=[NSURLRequest requestWithURL:[NSURL URLWithString:uriString]
                                               cachePolicy:NSURLRequestUseProtocolCachePolicy
                                           timeoutInterval:3600];
    
    NSString*__block p=[self _absoluteLocalPathFromRelativePath:destination
                                                     toLocalUrl:_context.destinationBaseUrl
                                                     withTreeId:_context.destinationTreeId
                                                      addPrefix:YES];
    [_fileManager createRecursivelyRequiredFolderForPath:[p filteredFilePath]];
    PdSCommandInterpreter *__weak weakSelf=self;
    
    if(kUSELowerMemoryApproach){
        // SIMPLE REQUEST
        AFHTTPRequestOperation *downloadRequest = [[AFHTTPRequestOperation alloc] initWithRequest:fileRequest];
        [downloadRequest setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
            @autoreleasepool {
                NSData *data = [[NSData alloc] initWithData:responseObject];
                NSError*error=nil;
                [data writeToFile:[p filteredFilePath]
                          options:NSDataWritingAtomic
                            error:&error];
                if(error){
                    NSString *msg=[NSString stringWithFormat:@"Error during downloadRequest when writing %@ %@",p,[weakSelf _stringFromError:error]];
                    [weakSelf _interruptOnFault:msg];
                }else{
                    [weakSelf _nextCommand];
                }
            }
        } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
            [weakSelf _interruptOnFault:[weakSelf _stringFromError:error]];
        }];
        [downloadRequest start];
        
    }else{
        // DOWNLOAD TASK ARE FAILING (DUE TO MEMORY ISSUES on IOS WITH XCODE6 + Debugger.)
        
        NSProgress* progress=nil;
        NSURLSessionDownloadTask *downloadTask = [_HTTPsessionManager downloadTaskWithRequest:fileRequest
                                                                                     progress:&progress
                                                                                  destination:^NSURL *(NSURL *targetPath, NSURLResponse *response) {
                                                                                      PdSCommandInterpreter *__strong strongSelf=weakSelf;
                                                                                      if([_fileManager fileExistsAtPath:[NSString filteredFilePathFrom:p]]){
                                                                                          [strongSelf _progressMessage:@"DownloadTask Deleting:%@ ",p];
                                                                                          if([strongSelf _filePathDeletionAllowed:p]){
                                                                                              NSError*error=nil;
                                                                                              [_fileManager removeItemAtPath:[NSString filteredFilePathFrom:p] error:&error];
                                                                                              if(error){
                                                                                                  NSString *msg=[NSString stringWithFormat:@"Non blocking Error during download task when removing %@ %@",p,[self _stringFromError:error]];
                                                                                                  [strongSelf _progressMessage:msg];
                                                                                              }
                                                                                          }
                                                                                      }
                                                                                      
                                                                                      return [NSURL URLWithString:p];
                                                                                  } completionHandler:^(NSURLResponse *response, NSURL *filePath, NSError *error) {
                                                                                      
                                                                                      PdSCommandInterpreter *__strong strongSelf=weakSelf;
                                                                                      
                                                                                      if(error){                                                                                                                   [strongSelf _interruptOnFault:[strongSelf _stringFromError:error]];
                                                                                          
                                                                                      }else{
                                                                                          [strongSelf _nextCommand];
                                                                                      }
                                                                                      
                                                                                  }];
        
        [downloadTask resume];
    }
}


- (void)_finalizeWithCommands:(NSArray*)commands{
    if((self->_context.mode==SourceIsLocalDestinationIsDistant)||
       self->_context.mode==SourceIsDistantDestinationIsDistant){
        
        // CALL the PdSync Service
        // Write the Hashmap to a file
        // @todo could be crypted.
        
        NSString* hashMapTempFilename = [NSString stringWithFormat:@"%f.hashmap", [NSDate timeIntervalSinceReferenceDate]];
        NSURL* hashMapTempFileUrl = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:hashMapTempFilename]];
        
        NSString*jsonHashMap=[self _encodetoJson:[_context.finalHashMap dictionaryRepresentation]];
        NSError*error=nil;
        
        [jsonHashMap writeToURL:hashMapTempFileUrl
                     atomically:YES encoding:NSUTF8StringEncoding
                          error:&error];
        
        PdSCommandInterpreter *__weak weakSelf=self;
        
        NSString *URLString =[[_context.destinationBaseUrl absoluteString] stringByAppendingFormat:@"finalizeTransactionIn/tree/%@/",_context.destinationTreeId];
        NSDictionary *parameters = @{
                                     @"syncIdentifier": _context.syncID,
                                     @"commands":[self  _encodetoJson:commands]
                                     };
        
        NSMutableURLRequest *request = [[AFHTTPRequestSerializer serializer] multipartFormRequestWithMethod:@"POST"
                                                                                                  URLString:URLString
                                                                                                 parameters:parameters
                                                                                  constructingBodyWithBlock:^(id<AFMultipartFormData> formData) {
                                                                                      [formData appendPartWithFileURL:hashMapTempFileUrl
                                                                                                                 name:@"hashmap"
                                                                                                             fileName:[hashMapTempFileUrl lastPathComponent]
                                                                                                             mimeType:@"application/octet-stream"
                                                                                                                error:nil];
                                                                                  } error:nil];
        
        NSProgress* progress=nil;
        NSURLSessionUploadTask *uploadTask = [_HTTPsessionManager uploadTaskWithStreamedRequest:request
                                                                                       progress:&progress
                                                                              completionHandler:^(NSURLResponse *response, id responseObject, NSError *error) {
                                                                                  /*
                                                                                   [progress removeObserver:weakSelf
                                                                                   forKeyPath:@"fractionCompleted"
                                                                                   context:NULL];
                                                                                   */
                                                                                  if ([(NSHTTPURLResponse*)response statusCode]!=200 && error) {
                                                                                      NSString *msg=[NSString stringWithFormat:@"Error when finalizing %@ ",[self _stringFromError:error]];
                                                                                      [self _interruptOnFault:msg];
                                                                                  } else {
                                                                                      [weakSelf _successFullEnd];
                                                                                  }
                                                                              }];
        /*
         [progress addObserver:self
         forKeyPath:@"fractionCompleted"
         options:NSKeyValueObservingOptionNew
         context:NULL];
         */
        
        [uploadTask resume];
        
    }else if (self->_context.mode==SourceIsDistantDestinationIsLocal||
              self->_context.mode==SourceIsLocalDestinationIsLocal){
        // EXECUTE CREATIVES COMMANDS
        NSError*error=nil;
        
        // SORT THE COMMANDS By PdSSyncCommand value order
        // Creation and Update will be done before Moves, Copies and Updates
        // PdSCreate   = 0 ,
        // PdSUpdate   = 1 ,
        // PdSMove     = 2 ,
        // PdSCopy     = 3 ,
        // PdSDelete   = 4
        
        NSArray*sortedCommand=[commands sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
            NSArray*a1=(NSArray*)obj1;
            NSArray*a2=(NSArray*)obj2;
            if ([[a1 objectAtIndex:PdSCommand] integerValue] > [[a2 objectAtIndex:PdSCommand] integerValue]){
                return NSOrderedDescending;
            }else{
                return NSOrderedAscending;
            }
        }];
        //NSLog(@"sortedCommand %@",sortedCommand);
        for (NSArray *cmd in sortedCommand) {
            NSString *destination=[cmd objectAtIndex:PdSDestination];
            NSUInteger command=[[cmd objectAtIndex:PdSCommand] integerValue];
            BOOL isAFolder=[[destination substringFromIndex:[destination length]-1] isEqualToString:@"/"];
            NSString*destinationPrefixedFilePath=[self _absoluteLocalPathFromRelativePath:destination
                                                                               toLocalUrl:_context.destinationBaseUrl
                                                                               withTreeId:_context.destinationTreeId
                                                                                addPrefix:YES];
            NSString*destinationFileWithoutPrefix=[self _absoluteLocalPathFromRelativePath:destination
                                                                                toLocalUrl:_context.destinationBaseUrl
                                                                                withTreeId:_context.destinationTreeId
                                                                                 addPrefix:NO];
            
            
            if(command==PdSCreate || command==PdSUpdate){
                if(!isAFolder){
                    
                    [_fileManager createRecursivelyRequiredFolderForPath:[destinationFileWithoutPrefix filteredFilePath]];
                    
                    
                    // UN PREFIX
                    [_fileManager moveItemAtPath:[destinationPrefixedFilePath filteredFilePath]
                                          toPath:[destinationFileWithoutPrefix filteredFilePath]
                                           error:&error];
                    
                    
                    if(error){
                        [self _progressMessage:@"Error on moveItemAtPath \nfrom %@ \nto %@ \n%@ ",[destinationPrefixedFilePath filteredFilePath],[destinationFileWithoutPrefix filteredFilePath],[error description]];
                        [self _interruptOnFault:[error description]];
                        return;
                        error=nil;
                    }
                }
                
            }
            
            if(command==PdSMove){
                NSString *source=[cmd objectAtIndex:PdSSource];
                [self _runMove:source
                   destination:destination];
            }
            
            if(command==PdSCopy){
                NSString *source=[cmd objectAtIndex:PdSSource];
                [self _runCopy:source
                   destination:destination];
            }
            
            if(command==PdSDelete){
                [self _runDelete:destination];
            }
            
            
        }
        // Write the Hash Map
        NSString*jsonHashMap=[self _encodetoJson:[_context.finalHashMap dictionaryRepresentation]];
        
        
        NSString*relativePathOfHashMapFile=[_context.destinationTreeId stringByAppendingFormat:@"/%@%@.%@",kPdSSyncMetadataFolder,kPdSSyncHashMashMapFileName,kPdSSyncHashFileExtension];
        NSURL *hashMapFileUrl=[_context.destinationBaseUrl URLByAppendingPathComponent:relativePathOfHashMapFile];
        [jsonHashMap writeToURL:hashMapFileUrl
                     atomically:YES encoding:NSUTF8StringEncoding
                          error:&error];
        
        if(error){
            [self _interruptOnFault:[error description]];
            return;
        }else{
            _completionBlock(YES,nil);
            [[NSNotificationCenter defaultCenter] postNotificationName:PdSSyncInterpreterHasFinalized
                                                                object:self];
        }
        
        
    }
}


- (NSString*)_stringFromError:(NSError*)error{
    NSMutableString*result=[NSMutableString string];
    NSData *d=[[error userInfo] objectForKey:AFNetworkingOperationFailingURLResponseDataErrorKey];
    if(d && [d length]>0){
        [result appendFormat:@" JSONResponseSerializerWithDataKey : %@",[[NSString alloc] initWithBytes:[d bytes]
                                                                                                 length:[d length]
                                                                                               encoding:NSUTF8StringEncoding]];
        
    }
    if([error localizedDescription]){
        [result appendFormat:@" debugDescription : %@",[error localizedDescription]];
    }
    if([error debugDescription]){
        [result appendFormat:@" debugDescription : %@",[error debugDescription]];
    }
    
    return result;
}


-(void)_runCopy:(NSString*)source destination:(NSString*)destination{
    if((self->_context.mode==SourceIsLocalDestinationIsDistant)){
        //DONE DURING FINALIZATION
    }else if (self->_context.mode==SourceIsDistantDestinationIsLocal||
              self->_context.mode==SourceIsLocalDestinationIsLocal){
        // COPY LOCALLY
        
        NSString*absoluteSource=[self _absoluteLocalPathFromRelativePath:source
                                                              toLocalUrl:_context.destinationBaseUrl
                                                              withTreeId:_context.destinationTreeId
                                                               addPrefix:NO];
        NSString*absoluteDestination=[self _absoluteLocalPathFromRelativePath:destination
                                                                   toLocalUrl:_context.destinationBaseUrl
                                                                   withTreeId:_context.destinationTreeId
                                                                    addPrefix:NO];
        
        NSError*error=nil;
        
        
        [_fileManager createRecursivelyRequiredFolderForPath:[absoluteDestination filteredFilePath]];
        
        [_fileManager copyItemAtPath:[absoluteSource filteredFilePath]
                              toPath:[absoluteDestination filteredFilePath]
                               error:&error];
        if(error){
            if(![_fileManager fileExistsAtPath:[absoluteDestination filteredFilePath]]){
                // NSFileManagerDelegate seems not to handle correctly this case
                [self _progressMessage:@"Error on copyItemAtPath \nfrom %@ \nto %@ \n%@ ",[absoluteSource filteredFilePath],[absoluteDestination filteredFilePath],[error description]];
                [self _interruptOnFault:[error description]];
                
            }
        }
        
    }else if (self->_context.mode==SourceIsDistantDestinationIsDistant){
        // CURRENTLY NOT SUPPORTED
    }
}


-(void)_runMove:(NSString*)source destination:(NSString*)destination{
    if((self->_context.mode==SourceIsLocalDestinationIsDistant)){
        //DONE DURING FINALIZATION
    }else if (self->_context.mode==SourceIsDistantDestinationIsLocal||
              self->_context.mode==SourceIsLocalDestinationIsLocal){
        // MOVE LOCALLY
        
        NSString*absoluteSource=[self _absoluteLocalPathFromRelativePath:source
                                                              toLocalUrl:_context.destinationBaseUrl
                                                              withTreeId:_context.destinationTreeId
                                                               addPrefix:NO];
        
        NSString*absoluteDestination=[self _absoluteLocalPathFromRelativePath:destination
                                                                   toLocalUrl:_context.destinationBaseUrl
                                                                   withTreeId:_context.destinationTreeId
                                                                    addPrefix:NO];
        
        NSError*error=nil;
        [_fileManager moveItemAtPath:[absoluteSource filteredFilePath]
                              toPath:[absoluteDestination filteredFilePath]
                               error:&error];
        if(error){
            if(![_fileManager fileExistsAtPath:[absoluteDestination filteredFilePath]]){
                [self _progressMessage:@"Error on moveItemAtPath \nfrom %@ \nto %@ \n%@ ",[absoluteSource filteredFilePath],[absoluteDestination filteredFilePath],[error description]];
                [self _interruptOnFault:[error description]];
            }
        }
        
        
    }else if (self->_context.mode==SourceIsDistantDestinationIsDistant){
        // CURRENTLY NOT SUPPORTED
    }
}

-(void)_runDelete:(NSString*)destination{
    if((self->_context.mode==SourceIsLocalDestinationIsDistant)){
        //DONE DURING FINALIZATION
    }else if (self->_context.mode==SourceIsDistantDestinationIsLocal||
              self->_context.mode==SourceIsLocalDestinationIsLocal){
        // DELETE LOCALLY
        NSString*absoluteDestination=[self _absoluteLocalPathFromRelativePath:destination
                                                                   toLocalUrl:_context.destinationBaseUrl
                                                                   withTreeId:_context.destinationTreeId
                                                                    addPrefix:NO];
        
        if([_fileManager fileExistsAtPath:[absoluteDestination filteredFilePath]]){
            NSError*error=nil;
            [_fileManager removeItemAtPath:[absoluteDestination filteredFilePath] error:&error];
            if(error){
                [self _progressMessage:@"Error on removeItemAtPath \nfrom %@ \n%@ ",[absoluteDestination filteredFilePath],[error description]];
                [self _interruptOnFault:[error description]];
            }
        }
    }else if (self->_context.mode==SourceIsDistantDestinationIsDistant){
        // CURRENTLY NOT SUPPORTED
    }
}


- (NSString*)_absoluteLocalPathFromRelativePath:(NSString*)relativePath
                                     toLocalUrl:(NSURL*)localUrl
                                     withTreeId:(NSString*)treeID
                                      addPrefix:(BOOL)addPrefix{
    if(!addPrefix || [[relativePath substringFromIndex:[relativePath length]-1] isEqualToString:@"/"]){
        // We donnot prefix the folders.
        return [NSString stringWithFormat:@"%@%@/%@",[localUrl absoluteString],treeID,relativePath];
    }else{
        NSMutableArray*components=[NSMutableArray arrayWithArray:[relativePath componentsSeparatedByString:@"/"]];
        NSString*lastComponent=(NSString*)[components lastObject];
        lastComponent=[NSString stringWithFormat:@"%@%@",self->_context.syncID,lastComponent];
        [components replaceObjectAtIndex:[components count]-1 withObject:lastComponent];
        NSString*prefixedRelativePath=[components componentsJoinedByString:@"/"];
        NSString*path= [NSString stringWithFormat:@"%@%@/%@",[localUrl absoluteString],treeID,prefixedRelativePath];
        path=[path stringByReplacingOccurrencesOfString:@" " withString:@"%20"];
        return path;
    }
}



#pragma mark -


+ (NSMutableArray*)commandsFromDeltaPathMap:(DeltaPathMap*)deltaPathMap{
    
    /*
     PdSCreate   = 0 , // W destination and source
     PdSUpdate   = 1 , // W destination and source
     PdSMove     = 2 , // R source W destination
     PdSCopy     = 3 , // R source W destination
     PdSDelete   = 4   // W source
     
     */
    
    NSMutableArray*commands=[NSMutableArray array];
    for (NSString*identifier in deltaPathMap.createdPaths) {
        [commands addObject:[PdSCommandInterpreter encodeCreate:identifier destination:identifier]];
    }
    for (NSString*identifier in deltaPathMap.updatedPaths) {
        [commands addObject:[PdSCommandInterpreter encodeUpdate:identifier destination:identifier]];
    }
    for (NSArray*movementArray in deltaPathMap.movedPaths) {
        NSString*source=[movementArray objectAtIndex:1];
        NSString*destination=[movementArray objectAtIndex:0];
        [commands addObject:[PdSCommandInterpreter encodeMove:source destination:destination]];
    }
    for (NSArray*copiesArray in deltaPathMap.copiedPaths) {
        NSString*source=[copiesArray objectAtIndex:1];
        NSString*destination=[copiesArray objectAtIndex:0];
        [commands addObject:[PdSCommandInterpreter encodeCopy:source destination:destination]];
    }
    for (NSString*identifier in deltaPathMap.deletedPaths) {
        [commands addObject:[PdSCommandInterpreter encodeRemove:identifier]];
    }
    return commands;
}


#pragma mark - KVO


- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context{
    if ( object && [keyPath isEqualToString:@"fractionCompleted"] ) {
        if(_progressBlock){
            NSProgress *progress = (NSProgress *)object;
            float f=progress.fractionCompleted;
            self->_progressBlock(_progressCounter,f);
        }
    }else{
        [super observeValueForKeyPath:keyPath
                             ofObject:object
                               change:change
                              context:context];
    }
}

#pragma mark - AFNetworking


// We currently support ONE MANAGER ONLY
// @todo SourceIsDistantDestinationIsDistant

- (BOOL)_setUpManager{
    if(self->_context.mode!=SourceIsLocalDestinationIsLocal &&
       self->_context.mode!=SourceIsDistantDestinationIsDistant){
        //_SessionManager
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
        if(self->_context.mode==SourceIsLocalDestinationIsDistant ){
            _HTTPsessionManager=[[AFHTTPSessionManager alloc]initWithBaseURL:_context.destinationBaseUrl sessionConfiguration:configuration];
        }else if(self->_context.mode==SourceIsDistantDestinationIsLocal){
            _HTTPsessionManager=[[AFHTTPSessionManager alloc]initWithBaseURL:_context.sourceBaseUrl sessionConfiguration:configuration];
        }
        if(_HTTPsessionManager){
            
            AFJSONRequestSerializer*r=[AFJSONRequestSerializer serializer];
            [_HTTPsessionManager setRequestSerializer:r];
            _HTTPsessionManager.responseSerializer = [[AFJSONResponseSerializer alloc]init];
            NSSet*acceptable= [NSSet setWithArray:@[@"application/json",@"text/html"]];
            [_HTTPsessionManager.responseSerializer setAcceptableContentTypes:acceptable];
            // REACHABILITY SUPPORT
            NSOperationQueue *operationQueue = _HTTPsessionManager.operationQueue;
            [_HTTPsessionManager.reachabilityManager setReachabilityStatusChangeBlock:^(AFNetworkReachabilityStatus status) {
                switch (status) {
                    case AFNetworkReachabilityStatusReachableViaWWAN:
                    case AFNetworkReachabilityStatusReachableViaWiFi:
                        [operationQueue setSuspended:NO];
                        break;
                    case AFNetworkReachabilityStatusNotReachable:
                    default:
                        [operationQueue setSuspended:YES];
                        break;
                }
            }];
            return YES;
        }
    }
    return NO;
}

- (NSString*)_encodetoJson:(id)object{
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:object
                                                       options:0
                                                         error:&error];
    if (!jsonData) {
        return [error localizedDescription];
    } else {
        return [[NSString alloc]initWithBytes:[jsonData bytes]
                                       length:[jsonData length] encoding:NSUTF8StringEncoding];
        
    }
}



- (void)_progressMessage:(NSString*)format, ... {
    _messageCounter++;
    if(self.finalizationDelegate){
        va_list vl;
        va_start(vl, format);
        NSString* message = [[NSString alloc] initWithFormat:format
                                                   arguments:vl];
        [self.finalizationDelegate progressMessage:[NSString stringWithFormat:@"%i# %@",_messageCounter,message]];
        va_end(vl);
        
    }
    
}


@end