//
//  PdSSyncAdmin.m
//  Pods
//
//  Created by Benoit Pereira da Silva on 12/11/2014.
//
//

#import "PdSSyncAdmin.h"
#import "AFNetworking.h"

#define kRecursiveMaxNumberOfAttempts 2

@interface PdSSyncAdmin (){
    PdSFileManager *__weak _fileManager;
}
@end

@implementation PdSSyncAdmin

/**
 *  Initialize the admin facade with a contzext
 *
 *  @param context the context
 *
 *  @return the admin instance
 */
- (instancetype)initWithContext:(PdSSyncContext*)context{
    self=[super init];
    if(self){
        _syncContext=context;
        _fileManager=[PdSFileManager sharedInstance];
    }
    return self;
}

#pragma mark - Synchronization

/**
 *  Synchronizes the source to the destination
 *
 *  @param progressBlock   the progress block
 *  @param completionBlock the completionBlock
 */
-(void)synchronizeWithprogressBlock:(void(^)(uint taskIndex,float progress,NSString*message))progressBlock
                 andCompletionBlock:(void(^)(BOOL success,NSString*message))completionBlock{
    int attempts=0;
    [self _prepareAndSynchronizeWithprogressBlock:progressBlock
                               andCompletionBlock:completionBlock
                                  numberOfAttempt:attempts];
}


-(void)_prepareAndSynchronizeWithprogressBlock:(void(^)(uint taskIndex,float progress,NSString*message))progressBlock
                            andCompletionBlock:(void(^)(BOOL success,NSString*message))completionBlock
                               numberOfAttempt:(int)attempts{
    attempts++;
    if(attempts > kRecursiveMaxNumberOfAttempts){
        // This occurs if the recursive call fails.
        completionBlock(NO,[NSString stringWithFormat:@"Excessive number of attempts of synchronization %i",kRecursiveMaxNumberOfAttempts]);
        return;
    }
    if(self.syncContext.autoCreateTrees){
        [self touchTreesWithCompletionBlock:^(BOOL success, NSInteger statusCode) {
            if(success){
                [self _synchronizeWithprogressBlock:progressBlock
                                 andCompletionBlock:completionBlock];
                
            }else{
                [self createTreesWithCompletionBlock:^(BOOL success, NSInteger statusCode) {
                    if(success){
                        // Recursive call
                        [self _prepareAndSynchronizeWithprogressBlock:progressBlock
                                                   andCompletionBlock:completionBlock
                                                      numberOfAttempt:attempts];
                    }else{
                        completionBlock(NO,[NSString stringWithFormat:@"Failure on createTreesWithCompletionBlock autoCreateTrees==YES with statusCode %i",(int)statusCode]);
                    }
                }];
            }
        }];
    }else{
        [self _synchronizeWithprogressBlock:progressBlock
                         andCompletionBlock:completionBlock];
    }
}



- (void)_synchronizeWithprogressBlock:(void(^)(uint taskIndex,float progress,NSString*message))progressBlock
                   andCompletionBlock:(void(^)(BOOL success,NSString*message))completionBlock{
    
    
    [self hashMapsForTreesWithCompletionBlock:^(HashMap *sourceHashMap, HashMap *destinationHashMap, NSInteger statusCode) {
        if(sourceHashMap && destinationHashMap ){
            
            NSString*s=[NSString stringWithFormat:@"\nSource: %@\n",[sourceHashMap dictionaryRepresentation]];
            NSString*d=[NSString stringWithFormat:@"\nDestination: %@\n",[destinationHashMap dictionaryRepresentation]];
            progressBlock(-1,0.f,[NSString stringWithFormat:@"\n\n\n----SYNCRONIZATION-----\n\n"]);
            progressBlock(-1,0.f,s);
            progressBlock(-1,0.f,d);
            
            DeltaPathMap*dpm=[sourceHashMap deltaHashMapWithSource:sourceHashMap
                                                    andDestination:destinationHashMap
                                                        withFilter:self.filteringBlock];
            
            NSMutableArray*commands=[PdSCommandInterpreter commandsFromDeltaPathMap:dpm];
            
            
            
            PdSCommandInterpreter*interpreter= [PdSCommandInterpreter interpreterWithBunchOfCommand:commands context:self->_syncContext
                                                                                      progressBlock:^(uint taskIndex, float progress) {
                                                                                          NSString*cmd=([commands count]>taskIndex)?[commands objectAtIndex:taskIndex]:@"POST CMD";
                                                                                          progressBlock(taskIndex,progress,cmd);
                                                                                      } andCompletionBlock:^(BOOL success, NSString *message) {
                                                                                          completionBlock(success,message);
                                                                                      }];
            
            interpreter.finalizationDelegate=self.finalizationDelegate;
            
            progressBlock(-1,0.f,[NSString stringWithFormat:@"\nDictionary representation of DeltaPathMap\n%@",[dpm dictionaryRepresentation]]);
            NSMutableString*cmdString=[NSMutableString string];
            [cmdString appendString:@"\n\n** Commands to be executed : **\n"];
            for (NSString*cmd in commands) {
                NSString*tmpCmdString=[NSString stringWithFormat:@"%@\n",[cmd copy]];
                tmpCmdString=[tmpCmdString stringByReplacingOccurrencesOfString:@"[0," withString:@"PdSCreate ["];
                tmpCmdString=[tmpCmdString stringByReplacingOccurrencesOfString:@"[1," withString:@"PdSUpdate ["];
                tmpCmdString=[tmpCmdString stringByReplacingOccurrencesOfString:@"[2," withString:@"PdSMove ["];
                tmpCmdString=[tmpCmdString stringByReplacingOccurrencesOfString:@"[3," withString:@"PdSCopy ["];
                tmpCmdString=[tmpCmdString stringByReplacingOccurrencesOfString:@"[4," withString:@"PdSDelete ["];
                [cmdString appendString:tmpCmdString];
            }
            [cmdString appendString:@"\n"];
            progressBlock(-1,0.f,cmdString);
            
            
        }else{
            BOOL sourceHashMapIsNil=(!sourceHashMap);
            BOOL destinationHashMapIsNil=(!destinationHashMap);
            NSString *m=[NSString stringWithFormat:@"Failure on hashMapsForTreesWithCompletionBlock with statusCode %i source HashMap Is Nil : %@ destination HashMap Is Nil %@" ,(int)statusCode,sourceHashMapIsNil?@"YES":@"NO",destinationHashMapIsNil?@"YES":@"NO"];
            completionBlock(NO,m);
        }
    }];
}



#pragma mark - Advanced actions


/**
 *  Proceed to installation of the Repository
 *
 *  @param context the context
 *  @param block   the completion block
 */
- (void)installWithCompletionBlock:(void (^)(BOOL success, NSInteger statusCode))block{
    if(_syncContext.mode==SourceIsLocalDestinationIsDistant){
        NSMutableDictionary*parameters=[NSMutableDictionary dictionary];
        if(_syncContext.creationKey)
            [parameters setObject:_syncContext.creationKey forKey:@"key"];
        AFHTTPRequestOperationManager *manager = [self _operationManager];
        [manager POST:[[_syncContext.destinationBaseUrl absoluteString]stringByAppendingFormat:@"install/"]
           parameters: parameters
              success:^(AFHTTPRequestOperation *operation, id responseObject) {
                  block(YES,operation.response.statusCode);
              } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                  block(NO,operation.response.statusCode);
              }];
    }else if (_syncContext.mode==SourceIsLocalDestinationIsLocal){
        // CURRENTLY NOT SUPPORTED
    }else if (_syncContext.mode==SourceIsDistantDestinationIsDistant){
        // CURRENTLY NOT SUPPORTED
    }
}

/**
 *  Creates a tree
 *  @param block      the completion block
 */
- (void)createTreesWithCompletionBlock:(void (^)(BOOL success, NSInteger statusCode))block{
    if(_syncContext.mode==SourceIsLocalDestinationIsDistant){
        if([self _createOrConfirmTreeLocalUrl:_syncContext.sourceBaseUrl
                              withId:_syncContext.sourceTreeId]){
            
            [self _createTreeDistantUrl:_syncContext.destinationBaseUrl
                                 withId:_syncContext.destinationTreeId
                     andCompletionBlock:^(BOOL success, NSInteger statusCode) {
                         block(success,statusCode);
                     }];
        }else{
            block(NO,404);
        }
    }else if(_syncContext.mode==SourceIsDistantDestinationIsLocal){
        if([self _createOrConfirmTreeLocalUrl:_syncContext.destinationBaseUrl
                              withId:_syncContext.destinationTreeId]){
            
            [self _createTreeDistantUrl:_syncContext.sourceBaseUrl
                                 withId:_syncContext.destinationTreeId
                     andCompletionBlock:^(BOOL success, NSInteger statusCode) {
                         block(success,statusCode);
                     }];
        }else{
            block(NO,404);
        }
    }else if (_syncContext.mode==SourceIsLocalDestinationIsLocal){
        if([self _createOrConfirmTreeLocalUrl:_syncContext.sourceBaseUrl
                              withId:_syncContext.sourceTreeId]&&
           [self _createOrConfirmTreeLocalUrl:_syncContext.destinationBaseUrl
                              withId:_syncContext.destinationTreeId]){
               block(YES,200);
           }else{
               block(NO,404);
           }
    }else if (_syncContext.mode==SourceIsDistantDestinationIsDistant){
        // CURRENTLY NOT SUPPORTED
    }
}


-(void)_createTreeDistantUrl:(NSURL*)baseUrl withId:(NSString*)identifier
          andCompletionBlock:(void (^)(BOOL success, NSInteger statusCode))block{
    NSMutableDictionary*parameters=[NSMutableDictionary dictionary];
    if(_syncContext.creationKey)
        [parameters setObject:_syncContext.creationKey forKey:@"key"];
    AFHTTPRequestOperationManager *manager = [self _operationManager];
    NSString *stringURL=[[baseUrl absoluteString]stringByAppendingFormat:@"create/tree/%@",identifier];
    [manager POST:stringURL
       parameters: parameters
          success:^(AFHTTPRequestOperation *operation, id responseObject) {
              block(YES,operation.response.statusCode);
          } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
              block(NO,operation.response.statusCode);
          }];
    
}

-(BOOL)_createOrConfirmTreeLocalUrl:(NSURL*)baseUrl
                    withId:(NSString*)identifier{
    NSString*p=[baseUrl absoluteString];
    p=[p stringByAppendingFormat:@"%@/",identifier];
    if ([_fileManager fileExistsAtPath:[p filteredFilePath]]) {
        return YES;
    }
    [_fileManager createRecursivelyRequiredFolderForPath:p];
    // By default we create a void hashmap.
    HashMap*hashMap=[[HashMap alloc] init];
    PdSLocalAnalyzer*analyzer=[[PdSLocalAnalyzer alloc] init];
    analyzer.saveHashInAFile=NO;
    [analyzer saveHashMap:hashMap toFolderUrl:[NSURL URLWithString:p]];
    return YES;
}




/**
 *  Touches the trees (changes the public ID )
 *
 *  @param block      the completion block
 */
- (void)touchTreesWithCompletionBlock:(void (^)(BOOL success, NSInteger statusCode))block{
    if(_syncContext.mode==SourceIsLocalDestinationIsDistant){
        if( [self _touchLocalUrl:_syncContext.sourceBaseUrl
                   andTreeWithId:_syncContext.sourceTreeId]){
            [self _touchDistantUrl:_syncContext.destinationBaseUrl
                    withTreeWithId:_syncContext.destinationTreeId
                andCompletionBlock:^(BOOL success, NSInteger statusCode) {
                    block(success,statusCode);
                }];
        }else{
            block(NO,404);
        }
    }else if (_syncContext.mode==SourceIsDistantDestinationIsLocal){
        if([self _touchLocalUrl:_syncContext.destinationBaseUrl
                  andTreeWithId:_syncContext.destinationTreeId]){
            [self _touchDistantUrl:_syncContext.sourceBaseUrl
                    withTreeWithId:_syncContext.sourceTreeId
                andCompletionBlock:^(BOOL success, NSInteger statusCode) {
                    block(success,statusCode);
                }];
        }else{
            block(NO,404);
        }
        
    }else if (_syncContext.mode==SourceIsLocalDestinationIsLocal){
        if([self _touchLocalUrl:_syncContext.sourceBaseUrl andTreeWithId:_syncContext.sourceTreeId]&&
           [self _touchLocalUrl:_syncContext.destinationBaseUrl andTreeWithId:_syncContext.destinationTreeId]){
            block(YES,200);
        }else{
            block(NO,404);
        }
    }else if (_syncContext.mode==SourceIsDistantDestinationIsDistant){
        // CURRENTLY NOT SUPPORTED
    }
}

-(void)_touchDistantUrl:(NSURL*)baseUrl withTreeWithId:(NSString*)identifier andCompletionBlock:(void (^)(BOOL success, NSInteger statusCode))block{
    NSMutableDictionary*parameters=[NSMutableDictionary dictionary];
    if(_syncContext.creationKey)
        [parameters setObject:_syncContext.creationKey forKey:@"key"];
    AFHTTPRequestOperationManager *manager = [self _operationManager];
    [manager POST:[[baseUrl absoluteString]stringByAppendingFormat:@"touch/tree/%@/",identifier]
       parameters: parameters
          success:^(AFHTTPRequestOperation *operation, id responseObject) {
              block(YES,operation.response.statusCode);
          } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
              block(NO,operation.response.statusCode);
          }];
    
}

-(BOOL)_touchLocalUrl:(NSURL*)baseUrl
        andTreeWithId:(NSString*)identifier{
    NSString*p=[baseUrl absoluteString];
    p=[p stringByAppendingString:identifier];
    BOOL treeExists=[_fileManager fileExistsAtPath:[p filteredFilePath]];
    return treeExists;
}


/**
 *  Returns the source and destination hashMaps for a given tree
 *
 *  @param block      the result block
 */
-(void)hashMapsForTreesWithCompletionBlock:(void (^)(HashMap*sourceHashMap,HashMap*destinationHashMap,NSInteger statusCode))block{
    PdSSyncAdmin*__block weakSelf=self;
    if(_syncContext.mode==SourceIsLocalDestinationIsDistant){
        [weakSelf _distantHashMapForUrl:_syncContext.destinationBaseUrl
                          andTreeWithId:_syncContext.destinationTreeId
                    withCompletionBlock:^(HashMap *hashMap, NSInteger statusCode) {
                        PdSSyncAdmin* strongSelf=weakSelf;
                        HashMap*sourceHashMap=[strongSelf  _localHashMapForUrl:strongSelf->_syncContext.sourceBaseUrl
                                                                 andTreeWithId:strongSelf->_syncContext.sourceTreeId];
                        
                        HashMap*destinationHashMap=hashMap;
                        [strongSelf->_syncContext setFinalHashMap:sourceHashMap];
                        if(!destinationHashMap && statusCode==404){
                            // There is currently no destination hashMap let's create a void one.
                            destinationHashMap=[[HashMap alloc] init];
                        }
                        block(sourceHashMap,destinationHashMap,statusCode);
                    }];
    }else if (_syncContext.mode==SourceIsDistantDestinationIsLocal){
        [weakSelf _distantHashMapForUrl:_syncContext.sourceBaseUrl
                          andTreeWithId:_syncContext.sourceTreeId
                    withCompletionBlock:^(HashMap *hashMap, NSInteger statusCode) {
                        PdSSyncAdmin* strongSelf=weakSelf;
                        HashMap*sourceHashMap=hashMap;
                        HashMap*destinationHashMap=[strongSelf  _localHashMapForUrl:strongSelf->_syncContext.destinationBaseUrl
                                                                      andTreeWithId:strongSelf->_syncContext.destinationTreeId];
                        
                        [strongSelf->_syncContext setFinalHashMap:sourceHashMap];
                        if(!sourceHashMap && statusCode==404){
                            destinationHashMap=[[HashMap alloc] init];
                        }
                        block(sourceHashMap,destinationHashMap,statusCode);
                    }];
        
    }else if (_syncContext.mode==SourceIsLocalDestinationIsLocal){
        HashMap*sourceHashMap=[weakSelf _localHashMapForUrl:_syncContext.sourceBaseUrl
                                              andTreeWithId:_syncContext.sourceTreeId];
        _syncContext.finalHashMap=sourceHashMap;
        HashMap*destinationHashMap=[weakSelf _localHashMapForUrl:_syncContext.destinationBaseUrl
                                                   andTreeWithId:_syncContext.sourceTreeId];
        if(!destinationHashMap){
            // There is currently no destination hashMap let's create a void one.
            destinationHashMap=[[HashMap alloc] init];
        }
        if(sourceHashMap && destinationHashMap){
            block(sourceHashMap,destinationHashMap,200);
        }else{
            block(sourceHashMap,destinationHashMap,404);
        }
    }else if (_syncContext.mode==SourceIsDistantDestinationIsDistant){
        // CURRENTLY NOT SUPPORTED
    }
    
    
}

-(HashMap*)_localHashMapForUrl:(NSURL*)url
                 andTreeWithId:(NSString*)identifier{
    NSString*hashMapRelativePath=[NSString stringWithFormat:@"%@%@/%@%@.%@",[url absoluteString],identifier,kPdSSyncMetadataFolder,kPdSSyncHashMashMapFileName,kPdSSyncHashFileExtension];
    hashMapRelativePath=[hashMapRelativePath filteredFilePath];
    NSURL *hashMapUrl=[NSURL fileURLWithPath:hashMapRelativePath];
    NSData *data=[NSData dataWithContentsOfURL:hashMapUrl];
    NSError*__block errorJson=nil;
    @try {
        // We use mutable containers and leaves by default.
        id __block result=nil;
        result=[NSJSONSerialization JSONObjectWithData:data
                                               options:NSJSONReadingMutableContainers|NSJSONReadingMutableLeaves|NSJSONReadingAllowFragments
                                                 error:&errorJson];
        if([result isKindOfClass:[NSDictionary class]]){
            return [HashMap fromDictionary:result];
        }
    }
    @catch (NSException *exception) {
        NSLog(@"%@",exception);
    }
    // There is no hashMap
    [_fileManager createRecursivelyRequiredFolderForPath:hashMapRelativePath];
    return [[HashMap alloc] init];// Return a void HashMap
}

-(void)_distantHashMapForUrl:(NSURL*)url
               andTreeWithId:(NSString*)identifier
         withCompletionBlock:(void (^)(HashMap*hashMap,NSInteger statusCode))block{
    NSMutableDictionary*parameters=[NSMutableDictionary dictionary];
    if(_syncContext.creationKey)
        [parameters setObject:_syncContext.creationKey forKey:@"key"];
    [parameters setObject:@(NO) forKey:@"redirect"];
    [parameters setObject:@(YES) forKey:@"returnValue"];
    AFHTTPRequestOperationManager *manager = [self _operationManager];
    //manager.requestSerializer=[AFJSONRequestSerializer serializer];
    NSString *URLString=[[url absoluteString]stringByAppendingFormat:@"hashMap/tree/%@/",identifier];
    [manager GET:URLString
      parameters: parameters
         success:^(AFHTTPRequestOperation *operation, id responseObject) {
             if( [responseObject isKindOfClass:[NSDictionary class]]){
                 HashMap*hashMap=[HashMap fromDictionary:responseObject];
                 block(hashMap,operation.response.statusCode);
             }else{
                 block(nil,PdSStatusErrorHashMapDeserializationTypeMissMatch);
             }
         } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
             block(nil, operation.response.statusCode);
         }];
}


#pragma  mark - Operation manager configuration

-(AFHTTPRequestOperationManager*)_operationManager{
    AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
    manager.securityPolicy.allowInvalidCertificates = YES;
    return manager;
}

@end