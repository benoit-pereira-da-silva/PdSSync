//
//  DeltaHashMap.m
//  PdSSync
//
//  Created by Benoit Pereira da Silva on 15/02/2014.
//
//

#import "DeltaPathMap.h"
NSString* const similarPathsKey=@"similarPaths";
NSString* const createdPathsKey=@"createdPaths";
NSString* const deletedPathsKey=@"deletedPaths";
NSString* const updatedPathsKey=@"updatedPaths";

@implementation DeltaPathMap

/**
 *  Returns a new instance of a deltaHashMap;
 *
 *  @return a deltaHashMap instance
 */
+(DeltaPathMap*)deltaHasMap{
    DeltaPathMap*instance=[[DeltaPathMap alloc]init];
    instance.similarPaths=[NSMutableArray array];
    instance.createdPaths=[NSMutableArray array];
    instance.updatedPaths=[NSMutableArray array];
    instance.deletedPaths=[NSMutableArray array];
    return instance;
}




/**
 *  Returns a dictionary representation of the DeltaPathMap
 *
 *  @return the dictionary
 */
- (NSDictionary*)dictionaryRepresentation{
    return @{ similarPathsKey:_similarPaths,
             createdPathsKey:_createdPaths,
             deletedPathsKey:_deletedPaths,
             updatedPathsKey:_deletedPaths
            };
}





@end