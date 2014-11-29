//
//  PdSSyncAdmin.m
//  Pods
//
//  Created by Benoit Pereira da Silva on 12/11/2014.
//
//

#import "PdSSyncAdmin.h"
#import "AFNetworking.h"



@interface PdSSyncAdmin (){
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
        if(!_syncContext.finalHashMap){
            [NSException raise:@"PdSSyncException" format:@"PdSSyncContext should have a finalHashMap to be usable"];
        }
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
   // PdSSyncAdmin*__weak weakSelf=self;
    
    void (^executionBlock)(void) = ^(void) {
        [self hashMapsForTreesWithCompletionBlock:^(HashMap *sourceHashMap, HashMap *destinationHashMap, NSInteger statusCode) {
            if(sourceHashMap && destinationHashMap ){
                DeltaPathMap*dpm=[sourceHashMap deltaHashMapWithSource:sourceHashMap
                                                        andDestination:destinationHashMap];
                NSMutableArray*commands=[PdSCommandInterpreter commandsFromDeltaPathMap:dpm];
                if([commands count]>0){
                    [PdSCommandInterpreter interpreterWithBunchOfCommand:commands context:self->_syncContext
                                                           progressBlock:^(uint taskIndex, float progress) {
                                                               NSString*cmd=([commands count]>taskIndex)?[commands objectAtIndex:taskIndex]:@"POST CMD";
                                                               progressBlock(taskIndex,progress,cmd);
                                                           } andCompletionBlock:^(BOOL success, NSString *message) {
                                                               completionBlock(success,message);
                                                           }];
                }
            }else{
                completionBlock(NO,[NSString stringWithFormat:@"Failure on hashMapsForTreesWithCompletionBlock with statusCode %i",(int)statusCode]);
            }
        }];

    };
    
    
    if(self.syncContext.autoCreateTrees){
        [self touchTreesWithCompletionBlock:^(BOOL success, NSInteger statusCode) {
            if(success){
                executionBlock();
            }else{
                [self createTreesWithCompletionBlock:^(BOOL success, NSInteger statusCode) {
                    if(success){
                        // Recursive call
                        [self synchronizeWithprogressBlock:progressBlock andCompletionBlock:completionBlock];
                    }else{
                        
                    }
                }];
            }
        }];
    }else{
        executionBlock();
    }
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
        [self _createTreeLocalUrl:_syncContext.sourceBaseUrl
                    withId:_syncContext.sourceTreeId];
        
        [self _createTreeDistantUrl:_syncContext.destinationBaseUrl withId:_syncContext.destinationTreeId
                 andCompletionBlock:^(BOOL success, NSInteger statusCode) {
                      block(success,statusCode);
                 }];
    }else if (_syncContext.mode==SourceIsLocalDestinationIsLocal){
        if([self _createTreeLocalUrl:_syncContext.sourceBaseUrl
                              withId:_syncContext.sourceTreeId]&&
           [self _createTreeLocalUrl:_syncContext.destinationBaseUrl
                              withId:_syncContext.destinationTreeId]){
            block(YES,200);
        }else{
            block(NO,404);
        }
    }else if (_syncContext.mode==SourceIsDistantDestinationIsDistant){
        // CURRENTLY NOT SUPPORTED
    }
}


-(void)_createTreeDistantUrl:(NSURL*)baseUrl withId:(NSString*)identifier andCompletionBlock:(void (^)(BOOL success, NSInteger statusCode))block{
    NSMutableDictionary*parameters=[NSMutableDictionary dictionary];
    if(_syncContext.creationKey)
        [parameters setObject:_syncContext.creationKey forKey:@"key"];
    [parameters setObject:@"YO" forKey:@"SINGE"];
    AFHTTPRequestOperationManager *manager = [self _operationManager];
    NSString *stringURL=[[baseUrl absoluteString]stringByAppendingFormat:@"create/tree/%@",identifier];
    [manager POST:stringURL
       parameters: parameters
          success:^(AFHTTPRequestOperation *operation, id responseObject) {
              NSLog(@"%@",responseObject);//DEBUG WHY NO POST
              block(YES,operation.response.statusCode);
          } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
              block(NO,operation.response.statusCode);
          }];
    
}

-(BOOL)_createTreeLocalUrl:(NSURL*)baseUrl withId:(NSString*)identifier{
    return YES;
}




/**
 *  Touches the trees (changes the public ID )
 *
 *  @param block      the completion block
 */
- (void)touchTreesWithCompletionBlock:(void (^)(BOOL success, NSInteger statusCode))block{
    if(_syncContext.mode==SourceIsLocalDestinationIsDistant){
        [self _touchLocalUrl:_syncContext.sourceBaseUrl andTreeWithId:_syncContext.sourceTreeId];
        [self _touchDistantUrl:_syncContext.destinationBaseUrl
                withTreeWithId:_syncContext.destinationTreeId
            andCompletionBlock:^(BOOL success, NSInteger statusCode) {
                block(success,statusCode);
            }];
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

-(BOOL)_touchLocalUrl:(NSURL*)baseUrl andTreeWithId:(NSString*)identifier{
    return YES;
}




/**
 *  Returns the source and destination hashMaps for a given tree
 *
 *  @param block      the result block
 */
-(void)hashMapsForTreesWithCompletionBlock:(void (^)(HashMap*sourceHashMap,HashMap*destinationHashMap,NSInteger statusCode))block{  
    PdSSyncAdmin*__weak weakSelf=self;
    if(_syncContext.mode==SourceIsLocalDestinationIsDistant||_syncContext.mode==SourceIsDistantDestinationIsDistant){
        [weakSelf _distantHashMapForTreeWithId:_syncContext.destinationTreeId
                           withCompletionBlock:^(HashMap *hashMap, NSInteger statusCode) {
                                   PdSSyncAdmin* strongSelf=weakSelf;
                                   HashMap*sourceHashMap=[strongSelf  _localHashMapForSourceUrl:strongSelf->_syncContext.sourceBaseUrl
                                                                                  andTreeWithId:strongSelf->_syncContext.sourceTreeId];
                               
                                   HashMap*destinationHashMap=hashMap;
                                   [strongSelf->_syncContext setFinalHashMap:sourceHashMap];
                                   if(!destinationHashMap && statusCode==404){
                                       // There is currently no destination hashMap let's create a void one.
                                       destinationHashMap=[[HashMap alloc] init];
                                   }
                                   block(sourceHashMap,destinationHashMap,statusCode);
                           }];
    }else if (_syncContext.mode==SourceIsLocalDestinationIsLocal){
        HashMap*sourceHashMap=[weakSelf _localHashMapForSourceUrl:_syncContext.sourceBaseUrl
                                                    andTreeWithId:_syncContext.sourceTreeId];
        _syncContext.finalHashMap=sourceHashMap;
        HashMap*destinationHashMap=[weakSelf _localHashMapForSourceUrl:_syncContext.destinationBaseUrl
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
    }
    
}

-(HashMap*)_localHashMapForSourceUrl:(NSURL*)url andTreeWithId:(NSString*)identifier{
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
    return nil;
}

-(void)_distantHashMapForTreeWithId:(NSString*)identifier
                withCompletionBlock:(void (^)(HashMap*hashMap,NSInteger statusCode))block{
    NSMutableDictionary*parameters=[NSMutableDictionary dictionary];
    if(_syncContext.creationKey)
        [parameters setObject:_syncContext.creationKey forKey:@"key"];
    [parameters setObject:@(NO) forKey:@"redirect"];
    [parameters setObject:@(YES) forKey:@"returnValue"];
    AFHTTPRequestOperationManager *manager = [self _operationManager];
    NSString *URLString=[[_syncContext.destinationBaseUrl absoluteString]stringByAppendingFormat:@"hashMap/tree/%@/",identifier];
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