//
//  EasyCache.m
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

#import "EasyCache.h"
#import "EasyHTTPURLResponse.h"
#import "NSStringMD5.h"
#import "DateFormatterUtil.h"

#pragma mark Utility Methods

NSInteger fileCreationDateComparison(id a, id b, void *context) {
	NSFileManager *mgr = [NSFileManager defaultManager];
	NSError *error_a, *error_b;
	NSString *cdir = (NSString*) context;
	NSString *apath = [cdir stringByAppendingPathComponent:a], *bpath = [cdir stringByAppendingPathComponent:b];
	NSDictionary *a_attribs = [mgr attributesOfItemAtPath:apath error:&error_a], 
	*b_attribs = [mgr attributesOfItemAtPath:bpath error:&error_b];
	BOOL error = FALSE;
	if(error_a){
		NSLog(@"Error getting attributes for %@:%@", apath, error_a);
		error = TRUE;
	}
	if(error_b){
		NSLog(@"Error getting attributes for %@:%@", bpath, error_b);
		error = TRUE;
	}
	if(error){
		return 0;
	}
	NSDate *adate = [a_attribs objectForKey:NSFileCreationDate], 
	*bdate = [b_attribs objectForKey:NSFileCreationDate];
	NSComparisonResult dcompare = [adate compare:bdate];
	return dcompare;
}

const NSString *kEasyCacheKey = @"___EASYCACHEKEY",
               *kEasyCacheTimeKey = @"___EASYCACHEKEYTIME";
const NSString *kResponseArchiveDataKey = @"D",
				*kResponseArchiveResponseURLKey = @"RU",
			    *kResponseArchiveResponseMIMEKey = @"RM",
                *kResponseArchiveResponseExpectedContentLengthKey = @"RE",
                *kResponseArchiveResponseTextEncodingNameKey = @"RN",
                *kResponseArchiveResponseHeadersKey = @"RH",
                *kResponseArchiveResponseStatusKey = @"RS",
				*kResponseArchiveUserInfoKey = @"U",
				*kResponseArchiveStoragePolicyKey = @"S";

#pragma mark -
#pragma mark EasyCache

@implementation EasyCache

@synthesize autoFlushToDisk;

#pragma mark -
#pragma mark NSURLCache Methods

- (id)initWithMemoryCapacity:(NSUInteger)mc diskCapacity:(NSUInteger)dc diskPath:(NSString *)path {
	if(self = [super initWithMemoryCapacity:0 diskCapacity:0 diskPath:path]){
		cacheDir = [path retain];
		autoFlushToDisk = NO;
		memoryResponses = [[NSMutableArray alloc] init];
		[self setMemoryCapacity:mc];
		[self setDiskCapacity:dc];
		cacheTimeout = 300.0;
	}
	return self;
}

-(void) dealloc {
	if(autoFlushToDisk){
		[self flushCacheToDisk];
	}
	[memoryResponses release];
	[cacheDir release];
	[super dealloc];
}


- (NSUInteger)diskCapacity {
	return diskCacheSize;
}

- (void)setDiskCapacity:(NSUInteger)diskCapacity {
	if(diskCapacity == 0) return;
	if(diskCapacity < diskCacheSize){
		NSUInteger diff = diskCacheSize - diskCapacity;
		[self clearDiskCacheForSize:diff];
	}
	diskCacheSize = diskCapacity;
	
}

-(NSUInteger) memoryCapacity {
	return memoryCacheSize;
}

-(void)setMemoryCapacity:(NSUInteger)memoryCapacity {
	if(memoryCapacity == 0) return;
	if(memoryCapacity < memoryCacheSize){
		if(autoFlushToDisk){
			[self flushCacheToDisk];
		} else {
			NSUInteger diff = memoryCacheSize - memoryCapacity;
			NSArray *flushed;
			[self clearMemoryCacheForSize:diff toArray:&flushed];
			if(flushed){
				[flushed release];
			}
		}
	}
	memoryCacheSize = memoryCapacity;
	
}

// This value is not totally authentic.  The current memory usage is based on the total
// size of the response bodies, not the total memory usage of object miscellany, header
// fields, etc.  
- (NSUInteger)currentMemoryUsage {
	NSUInteger sz = 0;
	NSCachedURLResponse *cr;
	@synchronized(memoryResponses){
		for(cr in memoryResponses){
			sz += [[cr data] length];
		}
	}
	return sz;
}


- (NSUInteger)currentDiskUsage {
	NSFileManager *mgr = [NSFileManager defaultManager];
	NSError *error = nil;
	NSArray *files = [mgr contentsOfDirectoryAtPath:cacheDir error:&error];
	NSUInteger sz = -1;
	if(error){
		NSLog(@"Could not get directory contents: %@", [error description]);
		error = nil;
	} else {
		sz = 0;
		NSString *entry;
		NSDictionary *attribs;
		NSString *path;
		for(entry in files){
			path = [cacheDir stringByAppendingPathComponent:entry];
			attribs = [mgr attributesOfItemAtPath:path error:&error];
			if(error){
				NSLog(@"Could not get file attributes for %@: %@", path, [error description]);
				error = nil;
			} else {
				sz += [[attribs objectForKey:NSFileSize] unsignedIntValue];
			}
		}
	}
	return sz;
}

- (void)removeCachedResponseForRequest:(NSURLRequest *)request {
	NSString *key = [EasyCache keyForRequest:request];
	NSCachedURLResponse *resp;
	@synchronized(memoryResponses){
		NSMutableArray *toRemove = [[NSMutableArray alloc] init];
		for(resp in memoryResponses){
			NSString *otherKey = [[resp userInfo] objectForKey:kEasyCacheKey];
			if([key isEqualToString:otherKey]){
				[toRemove addObject:resp];
				stats.memoryDeletions++;
			}
		}
		[memoryResponses removeObjectsInArray:toRemove];
		[toRemove release];
	}
	NSFileManager *mgr = [NSFileManager defaultManager];
	NSString *path = [cacheDir stringByAppendingPathComponent:key];
	if([mgr fileExistsAtPath:path]){
		NSError *err = nil;
		[mgr removeItemAtPath:path error:&err];
		if(err){
			NSLog(@"Cannot remove old cache item %@", err);
		} else {
			stats.fileDeletions++;
		}
	}
}

- (void)removeAllCachedResponses {
	@synchronized(memoryResponses){
		stats.memoryDeletions += [memoryResponses count];
		[memoryResponses removeAllObjects];
	}
	NSFileManager *mgr = [NSFileManager defaultManager];
	NSError *error = nil;
	NSString *entry;
	NSArray *files = [mgr contentsOfDirectoryAtPath:cacheDir error:&error];
	//BOOL cleared = FALSE;
	if(error){
		NSLog(@"Could not get directory contents %@", [error description]);
		error = nil;
	} else {
		BOOL deleteError = FALSE;
		NSString *path;
		for(entry in files){
			path = [cacheDir stringByAppendingPathComponent:entry];
			[mgr removeItemAtPath:path error:&error];
			if(error){
				deleteError = TRUE;
				NSLog(@"Could not delete file %@", [error description]);
				error = nil;
			} else {
				stats.fileDeletions++;
			}
		}
		//cleared = !deleteError;
	}
}

- (void)storeCachedResponse:(NSCachedURLResponse *)origResponse forRequest:(NSURLRequest *)request {
	// Workaround for a weird bug. Caching AdMarvel responses seems to cause intermittent
	// crashes, and since we don't have the source for the AdMarvel API, we can't see
	// what it's doing that might cause that.
	if ([[[request URL] host] isEqual:@"ads.admarvel.com"])
		return;

	NSCachedURLResponse *cachedResponse = origResponse;
	BOOL needs_a_release = FALSE;
	BOOL disk_ok = [cachedResponse storagePolicy] == NSURLCacheStorageAllowed;
	BOOL memory_ok = disk_ok || [cachedResponse storagePolicy] == NSURLCacheStorageAllowedInMemoryOnly;
	NSDictionary *userinfo = [cachedResponse userInfo];
	NSString *key = nil;
	if(userinfo){
		key = [userinfo objectForKey:(NSString*)kEasyCacheKey];
	}
	if(!key){
		NSDate *dt = [[NSDate alloc] init];
		if(!userinfo){
			userinfo = [[NSDictionary alloc] initWithObjectsAndKeys:[EasyCache keyForRequest:request], (NSString*)kEasyCacheKey, 
						dt, (NSString*) kEasyCacheTimeKey, 
						nil];
			cachedResponse = [[NSCachedURLResponse alloc] initWithResponse:[cachedResponse response] 
																	  data:[cachedResponse data] 
																  userInfo:userinfo 
															 storagePolicy:[cachedResponse storagePolicy]];
			[userinfo release];
			needs_a_release = TRUE;
		} else {
			NSMutableDictionary *d = [[NSMutableDictionary alloc] initWithDictionary:userinfo];
			[d setObject:[EasyCache keyForRequest:request] forKey:(NSString*)kEasyCacheKey];
			[d setObject:dt forKey:(NSString*)kEasyCacheTimeKey];
			cachedResponse = [[NSCachedURLResponse alloc] initWithResponse:[cachedResponse response] 
																	   data:[cachedResponse data] 
																   userInfo:d
															  storagePolicy:[cachedResponse storagePolicy]];
			[d release];
			needs_a_release = TRUE;
		}
		[dt release];
	}
	if(memory_ok){
		[self storeResponse:cachedResponse forKeyInMemory:key];
	} else if(disk_ok){
		[self storeResponse:cachedResponse forKeyInDisk:key];
	}
	if(needs_a_release){
		[cachedResponse release];
	}
}

- (NSCachedURLResponse *)cachedResponseForRequest:(NSURLRequest *)request {
	NSCachedURLResponse *r = [self cachedResponseForRequestIgnoringTimeout:request];
	if(r){
		NSHTTPURLResponse *httpr = (NSHTTPURLResponse*)[r response];
		NSDate *cachedDate = (NSDate*) [[r userInfo] objectForKey:(NSString*)kEasyCacheTimeKey];
		if(!cachedDate){
			NSString *dateStr = [[httpr allHeaderFields] objectForKey:@"Date"];
			if(dateStr){
				cachedDate = [[DateFormatterUtil sharedFormatter] dateFromString:dateStr withFormat:@"EEE, dd MMM yyyy HH:mm:ss zzz"];
			}
		}
		if(cachedDate){
			NSDate *now = [[NSDate alloc] init];
			NSTimeInterval diff = [now timeIntervalSinceDate:cachedDate];
			[now release];
			if(diff > cacheTimeout){
				stats.totalMisses++;
				stats.totalHits--;
				return nil;
			} 
		}
	}
	return r;
}

#pragma mark -
#pragma mark Internal Methods


const NSUInteger diskCacheSize = 10485760; // 10M
const NSUInteger memoryCacheSize = 2097152; //  2M
const NSString *kURLCacheDir = @"easycache";

+(void) initCache {
	static BOOL wasInit;
	if(!wasInit){
		NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
		NSString *cache_path = [NSString stringWithFormat:@"%@/%@/", [dirs objectAtIndex:0], kURLCacheDir];
		NSFileManager *fm = [NSFileManager defaultManager];
		if(![fm fileExistsAtPath:cache_path]){
			[fm createDirectoryAtPath:cache_path attributes:nil];
		}
		EasyCache *initCache = [[EasyCache alloc] initWithMemoryCapacity:memoryCacheSize 
															diskCapacity:diskCacheSize 
																diskPath:cache_path];
		[NSURLCache setSharedURLCache:initCache];
		[initCache release];		
		wasInit = YES;
	}
}


- (NSCachedURLResponse *)cachedResponseForRequestIgnoringTimeout:(NSURLRequest *)request {
	NSString *key = [EasyCache keyForRequest:request];
	NSCachedURLResponse *r = [self responseFromMemoryCacheForKey:key];
	if(!r){
		stats.memoryMisses++;
		r = [self responseFromDiskCacheForKey:key]; // possible memory leak
		if(r){
			[self storeResponse:r forKeyInMemory:key];
			[r release];
			stats.diskHits++;
		} else {
			stats.diskMisses++;
		}
	} else {
		stats.memoryHits++;
	}
	if(r){
		stats.totalHits++;
	} else {
		stats.totalMisses++;
	}
	return [[r copy] autorelease];
}

-(void) touchRequest:(NSURLRequest*)req {
	NSCachedURLResponse *resp = [self cachedResponseForRequestIgnoringTimeout:req];
	if(resp){
		NSMutableDictionary *d = [[NSMutableDictionary alloc] initWithDictionary:[resp userInfo]];
		NSDate *n = [[NSDate alloc] init];
		[d setObject:n forKey:kEasyCacheTimeKey];
		[n release];
		NSCachedURLResponse *c = [[NSCachedURLResponse alloc] initWithResponse:[resp response] 
																		  data:[resp data] 
																	  userInfo:d 
																 storagePolicy:[resp storagePolicy]];
		[d release];
		[self storeCachedResponse:c forRequest:req];
		[c release];
	}
}

// Returns an array WHICH MUST BE released by the receiver
-(void) clearMemoryCacheForSize:(NSUInteger)bytes toArray:(NSArray**)flush{
	(*flush) = nil;
	NSUInteger reclaimed = 0;
	NSCachedURLResponse *resp;
	NSMutableArray *toRemove = [[NSMutableArray alloc] init];
	@synchronized(memoryResponses){
		for(resp in memoryResponses){
			if(reclaimed < bytes){
				[toRemove addObject:resp];
				reclaimed += [[resp data] length];
				if(reclaimed >= bytes){
					break;
				}
			}
		}
		if(reclaimed >= bytes){
			stats.memoryDeletions += [toRemove count];
			[memoryResponses removeObjectsInArray:toRemove];
		} else {
			[toRemove removeAllObjects];
		}
	}
	(*flush) = toRemove;
}

-(BOOL) clearDiskCacheForSize:(NSUInteger)bytes {
	if(bytes > diskCacheSize){
		return FALSE;
	}
	NSFileManager *mgr = [NSFileManager defaultManager];
	NSError *error = nil;
	NSArray *files = nil;
	@synchronized(self){
		files = [mgr contentsOfDirectoryAtPath:cacheDir error:&error];
	}
	long long reclaimed = 0;
	BOOL cleared = FALSE;
	if(error){
		NSLog(@"Could not get directory contents: %@", [error description]);
		[error release];
		error = nil;
	} else {
		NSString *entry, *path;
		NSDictionary *attribs;
		NSArray *bydate = [files sortedArrayUsingFunction:fileCreationDateComparison context:cacheDir];
		NSMutableArray *delete = [[NSMutableArray alloc] init];
		@synchronized(self){
			for(entry in bydate){
				path = [cacheDir stringByAppendingPathComponent:entry];
				attribs = [mgr attributesOfItemAtPath:path error:&error];
				if(error){
					NSLog(@"Could not get file attributes for %@: %@", path, [error description]);
					error = nil;
				} else {
					reclaimed += [[attribs objectForKey:NSFileSize] longLongValue];
					[delete addObject:path];
					if(reclaimed >= bytes){
						break;
					}
				}
			}
		}
		if(reclaimed >= bytes){
			BOOL deleteError = FALSE;
			for(entry in delete){
				[mgr removeItemAtPath:entry error:&error];
				if(error){
					deleteError = TRUE;
					NSLog(@"Could not delete item %@", [error description]);
					error = nil;
				} else {
					stats.fileDeletions++;
				}
			}
			cleared = !deleteError;
		}
		[delete release];
	}
	return cleared;
}


-(BOOL) canFitInDisk:(NSUInteger)attempted {
	NSUInteger csz = [self currentDiskUsage];
	if(diskCacheSize < csz){
		return NO;
	} else {
		NSUInteger diff = diskCacheSize - csz;
		return attempted <= diff;
	}
}

-(BOOL) canFitInMemory:(NSUInteger)attempted {
	NSUInteger csz = [self currentMemoryUsage];
	if(memoryCacheSize < csz){
		return NO;
	} else {
		NSUInteger diff = memoryCacheSize - csz;
		return attempted <= diff;
	}	
}

+(NSString*) keyForRequest:(NSURLRequest*)req {
	NSMutableString *cacheKey = [[NSMutableString alloc] initWithString:[[req URL] absoluteString]];
	[cacheKey appendFormat:@"-%@", [req HTTPMethod]];
	NSDictionary *headers = [req allHTTPHeaderFields];
	NSArray *ks = [[headers allKeys] sortedArrayUsingSelector:@selector(compare:)];
	NSString *key, *val;
	for(key in ks){
		if([key isEqualToString:@"If-None-Match"] || [key isEqualToString:@"If-Modified-Since"] || [key isEqualToString:@"Accept-Encoding"]) continue;
		val = [headers objectForKey:key];
		if(!val) continue;
		[cacheKey appendFormat:@"-%@-%@", key, NSStringAsMD5(val)]; 
	}
	if([[req HTTPBody] length] > 0){
		[cacheKey appendFormat:@"-%@", NSDataAsMD5([req HTTPBody])]; 
	}
	NSString *actualCache = NSStringAsMD5(cacheKey);
	[cacheKey release];

	return actualCache;
}



-(NSCachedURLResponse*) responseFromDiskCacheForKey:(NSString*)key{
	NSFileManager *mgr = [NSFileManager defaultManager];
	NSString *path = [cacheDir stringByAppendingPathComponent:key];
	NSCachedURLResponse *r = nil;
	if([mgr fileExistsAtPath:path]){
		[self decodeResponse:path intoCachedResponse:&r];
	}
	return [[r copy] autorelease];
}

-(NSCachedURLResponse*) responseFromMemoryCacheForKey:(NSString*)key{
	NSUInteger i;
	NSCachedURLResponse *candidate, *response = nil;
	NSString *candidateKey;
	@synchronized(memoryResponses){
		for(i = 0; i < [memoryResponses count]; i++){
			candidate = [memoryResponses objectAtIndex:i];
			NSDictionary *u = [candidate userInfo];
			if(!u) continue;
			candidateKey = [u objectForKey:(NSString*)kEasyCacheKey];
			if(candidateKey && [candidateKey isEqualToString:key]){
				response = candidate;
				break;
			}
		}
	}
	return response;
}

-(void) storeResponse:(NSCachedURLResponse*)response forKeyInMemory:(NSString*)key {
	NSUInteger sz = [[response data] length];
	if(sz < memoryCacheSize){
		if(![self canFitInMemory:sz]){ 
			NSArray *toFlush;
			[self clearMemoryCacheForSize:sz toArray:&toFlush];
			if(toFlush){
				NSCachedURLResponse *toStore;
				NSString *flushKey;
				for(toStore in toFlush){
					if(flushKey = [[toStore userInfo] objectForKey:(NSString*)kEasyCacheKey]){
						[self storeResponse:toStore forKeyInDisk:flushKey];
					}
				}
				[toFlush release];
				stats.memoryFlushes++;
			}
		}
		NSCachedURLResponse *candidate = nil;
		NSDictionary *d = nil;
		NSString *k = nil;
		unsigned int i;
		BOOL replaced = NO;
		@synchronized(memoryResponses){
			for(i = 0; i < [memoryResponses count]; i++){
				candidate = [memoryResponses objectAtIndex:i];
				d = [candidate userInfo];
				if(k = [d objectForKey:kEasyCacheKey]){
					if([k isEqualToString:key]){
						[memoryResponses replaceObjectAtIndex:i withObject:response];
						replaced = YES;
						break;
					}
				}
			}
			if(!replaced){
				[memoryResponses addObject:response];
			}
		}
	}
}

-(void) storeResponse:(NSCachedURLResponse*)response forKeyInDisk:(NSString*)key {
	NSData *rootObj;
	[self encodeResponse:response intoData:&rootObj];
	if(rootObj){
		NSUInteger sz = [rootObj length];
		NSString *path;
		if(sz < diskCacheSize){
			if(![self canFitInDisk:sz]){
				[self clearDiskCacheForSize:sz];
			}
			path = [cacheDir stringByAppendingPathComponent:key];
			[rootObj writeToFile:path atomically:YES];
		}
		[rootObj release];
	}
}

// receiver responsible for releasing
-(void) encodeResponse:(NSCachedURLResponse*)response intoData:(NSData**)data{
	(*data) = nil;
	NSData *d = [response data];
	NSMutableData *rootObj = [[NSMutableData alloc] init];
	NSKeyedArchiver *ark = [[NSKeyedArchiver alloc] initForWritingWithMutableData:rootObj];
	[ark setOutputFormat:NSPropertyListBinaryFormat_v1_0];
	[ark encodeBytes:[d bytes] length:[d length] forKey:(NSString*)kResponseArchiveDataKey];
	NSHTTPURLResponse *real_response = (NSHTTPURLResponse*)[response response];
	[ark encodeObject:[real_response URL] forKey:(NSString*)kResponseArchiveResponseURLKey];
	[ark encodeObject:[real_response MIMEType] forKey:(NSString*)kResponseArchiveResponseMIMEKey];
	[ark encodeInt:[real_response expectedContentLength] forKey:(NSString*)kResponseArchiveResponseExpectedContentLengthKey];
	[ark encodeObject:[real_response textEncodingName] forKey:(NSString*)kResponseArchiveResponseTextEncodingNameKey];
	[ark encodeObject:[real_response allHeaderFields] forKey:(NSString*)kResponseArchiveResponseHeadersKey];
	[ark encodeInt:[real_response statusCode] forKey:(NSString*)kResponseArchiveResponseStatusKey];
	//[ark encodeObject:(NSHTTPURLResponse*)[response response] forKey:(NSString*)kResponseArchiveResponseKey];
	// above caused leaks
	[ark encodeObject:[response userInfo] forKey:(NSString*)kResponseArchiveUserInfoKey];
	[ark encodeInt:[response storagePolicy] forKey:(NSString*)kResponseArchiveStoragePolicyKey];
	[ark finishEncoding];
	[ark release];
	(*data) = rootObj;
	
}

// receiver responsible for releasing
-(void) decodeResponse:(NSString*)path intoCachedResponse:(NSCachedURLResponse**)response {
	(*response) = nil;
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSData *d = [[NSData alloc] initWithContentsOfFile:path];
	NSKeyedUnarchiver *u = [[NSKeyedUnarchiver alloc] initForReadingWithData:d];
	NSUInteger len;
	const uint8_t*  bytes = [u decodeBytesForKey:(NSString*)kResponseArchiveDataKey returnedLength:&len];
	NSURL *url = [u decodeObjectForKey:(NSString*)kResponseArchiveResponseURLKey];
	NSString *mime = [u decodeObjectForKey:(NSString*)kResponseArchiveResponseMIMEKey];
	NSInteger contentLength = [u decodeIntForKey:(NSString*)kResponseArchiveResponseExpectedContentLengthKey];
	NSString *textName = [u decodeObjectForKey:(NSString*)kResponseArchiveResponseTextEncodingNameKey];
	NSDictionary *headers = [u decodeObjectForKey:(NSString*)kResponseArchiveResponseHeadersKey];
	NSInteger code = [u decodeIntForKey:(NSString*) kResponseArchiveResponseStatusKey];
	EasyHTTPURLResponse *actualResponse = [[EasyHTTPURLResponse alloc] initWithURL:url
																		  MIMEType:mime
															 expectedContentLength:contentLength
																  textEncodingName:textName
																	  headerFields:headers
																		statusCode:code];

	NSDictionary *userInfo = [u decodeObjectForKey:(NSString*)kResponseArchiveUserInfoKey];
	NSURLCacheStoragePolicy policy = [u decodeIntForKey:(NSString*)kResponseArchiveStoragePolicyKey];
	NSData * actual_data = [[NSData alloc] initWithBytes:bytes length:len];
	[u finishDecoding];
	[u release];
	[d release];
	NSDictionary *dict = [[NSDictionary alloc] initWithDictionary:userInfo];
	[pool release];
 	NSCachedURLResponse *resp = [[NSCachedURLResponse alloc] initWithResponse:actualResponse
																		 data:actual_data 
  																	 userInfo:dict 
																 storagePolicy:policy];
	[dict release];
	[actual_data release];
	[actualResponse release];
	(*response) = resp;
}

-(BOOL) isAddressCached:(NSString*)url {
	NSURL *uobj = [[NSURL alloc] initWithString:url];
	NSURLRequest *req = [[NSURLRequest alloc] initWithURL:uobj];
	NSCachedURLResponse *resp = [self cachedResponseForRequestIgnoringTimeout:req];
	BOOL has_data = resp != nil;
	[req release];
	[uobj release];
	return has_data;
}

-(void) printStats {
	NSLog(@"CACHE: MEMORY(%i hits, %i misses, %i deletions, %i flushes) FILE(%i hits, %i misses, %i deletions) TOTAL(%i hits, %i misses)",
	       stats.memoryHits,
			stats.memoryMisses,
			stats.memoryDeletions,
			stats.memoryFlushes,
			stats.diskHits,
			stats.diskMisses,
			stats.fileDeletions,
			stats.totalHits,
		  stats.totalMisses);
}

-(void) flushCacheToDisk {
	NSCachedURLResponse *toFlush;
	NSString *key;
	[self printStats];
	@synchronized(memoryResponses){
		for(toFlush in memoryResponses){
			key = [[toFlush userInfo] objectForKey:kEasyCacheKey];
			[self storeResponse:toFlush forKeyInDisk:key];
		}
		[memoryResponses removeAllObjects];
	}
}



@end
