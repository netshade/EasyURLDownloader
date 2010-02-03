//
//  EasyCache.h
//
// Copyright (c) 2010 StarMedia
// 
// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use,
// copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following
// conditions:
// 
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
// 
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
// OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
// HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
// WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
// OTHER DEALINGS IN THE SOFTWARE.
//

#import <Foundation/Foundation.h>

typedef struct {
	NSUInteger memoryHits;
	NSUInteger memoryMisses;
	NSUInteger diskHits;
	NSUInteger diskMisses;
	NSUInteger totalHits;
	NSUInteger totalMisses;
	NSUInteger memoryFlushes;
	NSUInteger memoryDeletions;
	NSUInteger fileDeletions;
} CacheStats;

@interface EasyCache : NSURLCache {
	NSUInteger diskCacheSize;
	NSUInteger memoryCacheSize;
	BOOL autoFlushToDisk;
	NSString *cacheDir;
	NSMutableArray *memoryResponses;
	CacheStats stats;
	NSTimeInterval cacheTimeout;
}

@property(nonatomic, assign) BOOL autoFlushToDisk;

+(void) initCache;
+(NSString*) keyForRequest:(NSURLRequest*)req;
- (NSCachedURLResponse *)cachedResponseForRequestIgnoringTimeout:(NSURLRequest *)request;
-(void) clearMemoryCacheForSize:(NSUInteger)bytes toArray:(NSArray**)flush;
-(BOOL) clearDiskCacheForSize:(NSUInteger)bytes;
-(void) flushCacheToDisk;
-(void) storeResponse:(NSCachedURLResponse*)response forKeyInMemory:(NSString*)key;
-(void) storeResponse:(NSCachedURLResponse*)response forKeyInDisk:(NSString*)key;
-(NSCachedURLResponse*) responseFromDiskCacheForKey:(NSString*)key;
-(NSCachedURLResponse*) responseFromMemoryCacheForKey:(NSString*)key;
-(BOOL) canFitInDisk:(NSUInteger)attempted;
-(BOOL) canFitInMemory:(NSUInteger)attempted;
-(void) touchRequest:(NSURLRequest*)req;
-(void) encodeResponse:(NSCachedURLResponse*)response intoData:(NSData**)data;
-(void) decodeResponse:(NSString*)path intoCachedResponse:(NSCachedURLResponse**)response;
-(void) printStats;
-(BOOL) isAddressCached:(NSString*)url;


@end

extern const NSString *kEasyCacheKey;
extern const NSString *kEasyCacheTimeKey;