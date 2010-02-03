//
//  EasyURLDownloader.m
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

#import "EasyURLDownloader.h"
#import "Reachability.h"
#import "EasyCache.h"


const NSString * const kEasyURLDownloadTypeData = @"DATA";
const NSString * const kEasyURLDownloadTypeImage = @"IMAGE";
const NSString * const kEasyURLDownloadTypeDictionary = @"DICTIONARY";
const NSString * const kEasyURLDownloadTypeArray = @"ARRAY";

@implementation EasyURLDownloaderNotifyDelegate

@synthesize delegate;

-(id) initWithDelegate:(id)d andURL:(NSString*)u;{
	if(self = [super init]){
		delegate = [d retain];
		type = kEasyURLDownloadTypeData;
		buffer = [[NSMutableData alloc] init];
		urlString = [u retain];
	}
	return self;
}

-(id) initWithDelegate:(id)d andType:(NSString*)t andURL:(NSString*)u;{
	if(self = [super init]){
		delegate = [d retain];
		type = t;
		buffer = [[NSMutableData alloc] init];
		urlString = [u retain];
	}
	return self;
}

-(void) dealloc {
	[delegate release];
	[urlString release];
	[buffer release];
	[super dealloc];
}

-(void) appendData:(NSData*)data {
	[buffer appendData:data];
	if(expectedSize > 0){
		if([delegate respondsToSelector:@selector(downloadForURL:hasCompletedPercent:)]){
			float percent_complete = (double)[buffer length] / (double)expectedSize;
			[delegate downloadForURL:nil hasCompletedPercent:percent_complete];
		}
	}
}

-(NSData*) data {
	return [NSData dataWithData:buffer];
}

-(void) notifyResponse:(NSURLResponse*)response {
	NSHTTPURLResponse *r = (NSHTTPURLResponse*) response;
	statusCode = [r statusCode];
	expectedSize = [response expectedContentLength];
	if([delegate respondsToSelector:@selector(downloadForURL:startedWithResponse:)]){
		[delegate downloadForURL:urlString startedWithResponse:response];
	}
}

-(void) notifyRequestComplete:(NSURLRequest*)req{
	NSData *lb = buffer;
	if(statusCode == 304 && [buffer length] == 0){
		EasyCache *sc = (EasyCache*) [NSURLCache sharedURLCache];
		NSCachedURLResponse *resp = [sc cachedResponseForRequestIgnoringTimeout:req];
		if(resp){
			lb = [resp data];
		} 
	}
	BOOL hasFailureMethod = [delegate respondsToSelector:@selector(downloadForURL:failedWithError:)];
	if([delegate respondsToSelector:@selector(downloadForURL:completeWithObject:)]){
		if(type == kEasyURLDownloadTypeImage){
			UIImage *img = [[UIImage alloc] initWithData:lb];
			if(img){
				[delegate downloadForURL:urlString completeWithObject:img];
			} else if(hasFailureMethod) {
				[delegate downloadForURL:urlString failedWithError:nil];
			}
			[img release];
		} else if(type == kEasyURLDownloadTypeDictionary){
			CFReadStreamRef reader = CFReadStreamCreateWithBytesNoCopy(NULL, [lb bytes], [lb length], kCFAllocatorNull);
			CFPropertyListFormat fmt;
			CFStringRef error;
			CFReadStreamOpen(reader);
			CFPropertyListRef plist = CFPropertyListCreateFromStream(kCFAllocatorDefault, reader, [lb length], kCFPropertyListImmutable, &fmt, &error);
			CFReadStreamClose(reader);
			CFRelease(reader);
			if(error){
				if(hasFailureMethod){
					[delegate downloadForURL:urlString failedWithError:nil];
				}
				CFRelease(error);
			} else {
				[delegate downloadForURL:urlString completeWithObject:(id)plist];
				CFRelease(plist);
			}
		} else if(type == kEasyURLDownloadTypeArray){
			CFReadStreamRef reader = CFReadStreamCreateWithBytesNoCopy(NULL, [lb bytes], [lb length], kCFAllocatorNull);
			CFPropertyListFormat fmt;
			CFStringRef error = nil;
			CFReadStreamOpen(reader);
			CFPropertyListRef plist = CFPropertyListCreateFromStream(kCFAllocatorDefault, reader, [lb length], kCFPropertyListImmutable, &fmt, &error);
			CFReadStreamClose(reader);
			CFRelease(reader);
			if(error){
				if(hasFailureMethod){
					[delegate downloadForURL:urlString failedWithError:nil];
				}
				CFRelease(error);
			} else {
				[delegate downloadForURL:urlString completeWithObject:(id)plist];
				CFRelease(plist);
			}
		}  else if(type == @"CUSTOM"){

		} else {
			[delegate downloadForURL:urlString completeWithObject:lb];
		}
	} 
}

-(void) notifyError:(NSError*)error {
	if([delegate respondsToSelector:@selector(downloadForURL:failedWithError:)]){
		[delegate downloadForURL:urlString failedWithError:error];
	}
}

@end

@implementation EasyURLOperation

@synthesize recipient;

-(id) initWithDownload:(NSString*)u andRecipient:(EasyURLDownloaderNotifyDelegate*)r cacheBehavior:(EasyURLOperationCacheBehavior)nc{
	if(self = [super init]){
		url = [u retain];
		recipient = [r retain];
		request = nil;
		finished = FALSE;
		running = FALSE;
		cancelled = FALSE;
		cacheBehavior = nc;
		responseToCache = nil;
	}
	return self;
}

-(void) dealloc {
	if(responseToCache){
		[responseToCache release];
	}
	if(request){
		[request release];
	}
	[recipient release];
	[url release];
	[super dealloc];
}

-(void) cancel {
	[self willChangeValueForKey:@"isCancelled"];
	cancelled = TRUE;
	[self didChangeValueForKey:@"isCancelled"];
}

-(BOOL) isCancelled {
	return cancelled;
}

-(NSString*) description {
	return [NSString stringWithFormat:@"(EasyURLOperation:%@, cacheBehavior:%i, running:%s, cancelled:%s, finished:%s)", 
			url, 
			cacheBehavior,
			(running) ? "YES" : "NO",
			(cancelled) ? "YES" : "NO",
	        (finished) ? "YES" : "NO"];
}

-(void) main {
	[self willChangeValueForKey:@"isExecuting"];
	{
		running = TRUE;
	}
	NSAutoreleasePool *threadpool = [[NSAutoreleasePool alloc] init];
	[self didChangeValueForKey:@"isExecuting"];
	NSURL *original_request = [[NSURL alloc] initWithString:url];
	NSString *host = [original_request host];
	NSURLRequestCachePolicy cp = NSURLRequestUseProtocolCachePolicy;
	Reachability *r = [Reachability sharedReachability];
	[r setHostName:host]; // ip
	BOOL cannotReach = [r remoteHostStatus] == NotReachable;
	if(!cannotReach){
		cp = (cacheBehavior == kEasyURLOperationNoCache) ? NSURLRequestReloadIgnoringLocalAndRemoteCacheData : NSURLRequestUseProtocolCachePolicy; // 
	} else {
		cp = NSURLRequestReturnCacheDataDontLoad;
	} 
	request = [[NSMutableURLRequest alloc] initWithURL:original_request];// initWithURL:urlobj cachePolicy:cp timeoutInterval:10.0];
	[request setTimeoutInterval:10.0];
	[request setValue:host forHTTPHeaderField:@"Host"];
	[request setValue:[[EasyURLDownloader sharedDownloader] userAgent] forHTTPHeaderField:@"User-Agent"];
	[request setValue:[[EasyURLDownloader sharedDownloader] applicationName] forHTTPHeaderField:@"X-Application"];
	NSURLCache *sc = [NSURLCache sharedURLCache];
	BOOL isEasyCache = [sc isKindOfClass:[EasyCache class]];
	if(cacheBehavior == kEasyURLOperationNormalCache || cacheBehavior == kEasyURLOperationOnlyCache){
		NSCachedURLResponse *resp;
		if(isEasyCache && (cannotReach || cacheBehavior == kEasyURLOperationOnlyCache)){
			resp = [(EasyCache*)sc cachedResponseForRequestIgnoringTimeout:request];
		} else {
			resp = [sc cachedResponseForRequest:request];
		}
		if(resp){
			NSURLResponse *r = [resp response];
			NSData *d = [resp data];
			NSURLRequest *re = request;
			{
				[recipient performSelectorOnMainThread:@selector(notifyResponse:) withObject:r waitUntilDone:YES];
				[recipient performSelectorOnMainThread:@selector(appendData:) withObject:d waitUntilDone:YES];
				[recipient performSelectorOnMainThread:@selector(notifyRequestComplete:) withObject:re waitUntilDone:NO];
			}
			[original_request release];
			[threadpool release];
			[self setFinished];
			return;
		} else if(cacheBehavior == kEasyURLOperationNormalCache){
			/*
			 Conditional get support
			 */
			if(isEasyCache){
				resp = [(EasyCache*)sc cachedResponseForRequestIgnoringTimeout:request];
			} else {
				resp = [sc cachedResponseForRequest:request];
			}
			if(resp){
				NSHTTPURLResponse *real_response = (NSHTTPURLResponse*)[resp response];
				NSDictionary *h = [real_response allHeaderFields];
				NSString *etag;
				if(etag = [h objectForKey:@"Etag"]){
					[request addValue:etag forHTTPHeaderField:@"If-None-Match"];
				} 
				NSString *lm;
				if(lm = [h objectForKey:@"Last-Modified"]){
					[request addValue:lm forHTTPHeaderField:@"If-Modified-Since"];
				}
			}
			[request setValue:@"gzip" forHTTPHeaderField:@"Accept-Encoding"];
		} else if(cacheBehavior == kEasyURLOperationOnlyCache){
			[original_request release];
			[threadpool release];
			[self setFinished];
			return;
		}
	}
	[original_request release];
	/*
		Rationale for maintaining a thread /just/ to respond to NSURLConnection delegate responses:
	 
		Apple's documentation for NSURLConnection states that by opening a separate thread to handle
	    the NSURLConnection response will provide a more responsive experience. The alternative, opening
	    the connection off the main thread and waiting for the connection to return, does not respond nearly
		as quickly as might be desired.
	 */
	NSURLConnection *c = [[NSURLConnection alloc] initWithRequest:request delegate:self];
	BOOL got_input;
	while(![self isFinished] && ![self isCancelled]){
		got_input = [[NSRunLoop	currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
		if(!got_input){
			break;
		}
		[threadpool drain];
	}
	[threadpool release];
	[c release];
	if(![self isFinished]){
		[self setFinished];
	}
	[self willChangeValueForKey:@"isExecuting"];
	running = FALSE;
	[self didChangeValueForKey:@"isExecuting"];
}

-(BOOL) isExecuting {
	return running;
}

-(BOOL) isFinished {
	return finished;
}

-(BOOL) isConcurrent {
	return NO;
}

-(void) connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
	if(responseToCache) [responseToCache release];
	responseToCache = [response retain];
	[recipient performSelectorOnMainThread:@selector(notifyResponse:) withObject:response waitUntilDone:YES];
}

-(void) connection:(NSURLConnection*)c didReceiveData:(NSData*) data {
	[recipient performSelectorOnMainThread:@selector(appendData:) withObject:data waitUntilDone:YES];
}

-(NSCachedURLResponse*) connection:(NSURLConnection*)connection willCacheResponse:(NSCachedURLResponse*)response {
	NSDate *dt = [[NSDate alloc] init];
	NSDictionary *d = [[NSDictionary alloc] initWithObjectsAndKeys:[EasyCache keyForRequest:request], (NSString*)kEasyCacheKey, 
					   dt, (NSString*)kEasyCacheTimeKey,
					   nil];
	[dt release];
	NSCachedURLResponse *resp = [[[NSCachedURLResponse alloc] 
								 initWithResponse:[response response] 
								 data:[response data] 
								 userInfo:d
								 storagePolicy:NSURLCacheStorageAllowed] autorelease];
	[d release];
	response = nil;
	return resp;
}

-(void) connection:(NSURLConnection*)c didFailWithError:(NSError*) error {
	[recipient performSelectorOnMainThread:@selector(notifyError:) withObject:error waitUntilDone:YES];
	[self setFinished];
}

-(void) connectionDidFinishLoading:(NSURLConnection*)c {
	[recipient performSelectorOnMainThread:@selector(notifyRequestComplete:) withObject:request waitUntilDone:NO];
	NSHTTPURLResponse *resp = (NSHTTPURLResponse*) responseToCache;
	if([resp statusCode] == 200){
		NSDate *dt = [[NSDate alloc] init];
		NSDictionary *d = [[NSDictionary alloc] initWithObjectsAndKeys:[EasyCache keyForRequest:request], (NSString*)kEasyCacheKey, 
						   dt, (NSString*)kEasyCacheTimeKey,
						   nil];
		[dt release];
		NSCachedURLResponse *cresp = [[NSCachedURLResponse alloc] initWithResponse:responseToCache 
																			  data:[recipient data]
																		  userInfo:d
																	 storagePolicy:NSURLCacheStorageAllowed];
		[d release];
		[[NSURLCache sharedURLCache] storeCachedResponse:cresp forRequest:request];
		[cresp release];
	} else if([resp statusCode] == 304){
		EasyCache *sc = (EasyCache*) [NSURLCache sharedURLCache];
		[sc touchRequest:request];
	}
	[self setFinished];
}

-(void) setFinished {
	[self willChangeValueForKey:@"isFinished"];
	finished = TRUE;
	[self didChangeValueForKey:@"isFinished"];
}


@end



@implementation EasyURLDownloader

@synthesize maxConnections;
@synthesize isOperating;
@synthesize currentlyDownloading;
@synthesize userAgent;
@synthesize applicationName;

+(EasyURLDownloader*) sharedDownloader {
	static EasyURLDownloader *downloader;
	if(!downloader){
		downloader = [[EasyURLDownloader alloc] init];
		[EasyCache initCache];
	}
	return downloader;
}

+(void)cancelDownloadsFor:(id<EasyURLDownloaderNotifyProtocol>)delegate {
	[[EasyURLDownloader sharedDownloader] cancelAllPendingDownloadsForDelegate:delegate];
}

-(id) init {
	if(self = [super init]){
		maxConnections = 3;
		currentlyDownloading = 0;
		isOperating = FALSE;
		userAgent = [[NSString alloc] initWithString:@"Mozilla/5.0 (iPhone; U; CPU like Mac OS X; en)"];
		applicationName = [[NSString alloc] initWithString:@"iPhone App"];
		queue = [[NSOperationQueue alloc] init];
		[queue setMaxConcurrentOperationCount:maxConnections];
		[queue addObserver:self 
				forKeyPath:@"operations" 
				   options:NSKeyValueObservingOptionNew 
				   context:NULL];
	}
	return self;
}

-(void) dealloc {
	[queue setSuspended:YES];
	[queue cancelAllOperations];
	[queue release];
	[userAgent release];
	[applicationName release];
	[super dealloc];
}

-(void) observeValueForKeyPath:(NSString*)keypath ofObject:(id)object change:(NSDictionary*)change context:(void*)context {
	if([keypath isEqual:@"operations"]){
		NSArray *ops = [change objectForKey:NSKeyValueChangeNewKey];
		[self willChangeValueForKey:@"currentlyDownloading"];
		[self willChangeValueForKey:@"isOperating"];
		currentlyDownloading = [ops count];
		isOperating = currentlyDownloading > 0;
		[self didChangeValueForKey	:@"currentlyDownloading"];
		[self didChangeValueForKey:@"isOperating"];
	}
	// docs state that super should be called
	// causes crash though
	//[super observeValueForKeyPath:keypath ofObject:object change:change context:context];
}

-(void) setMaxConnections:(unsigned int)max {
	maxConnections = max;
	[queue setMaxConcurrentOperationCount:max];
}

-(void) startDownloading:(NSString*)url withDelegate:(id<EasyURLDownloaderNotifyProtocol>)delegate {
	[self startDownloading:url withDelegate:delegate forType:kEasyURLDownloadTypeData noCache:NO highPriority:NO];
}

-(void) startDownloading:(NSString*)url withDelegate:(id<EasyURLDownloaderNotifyProtocol>)delegate forType:(const NSString*)type {
	[self startDownloading:url withDelegate:delegate forType:type noCache:NO highPriority:NO];
}

-(void) startDownloading:(NSString*)url withDelegate:(id<EasyURLDownloaderNotifyProtocol>)delegate forType:(const NSString*)type noCache:(BOOL)nc {
	[self startDownloading:url withDelegate:delegate forType:type noCache:nc highPriority:NO];
}

-(void) startDownloading:(NSString*)url withDelegate:(id<EasyURLDownloaderNotifyProtocol>)delegate forType:(const NSString*)type noCache:(BOOL)nc highPriority:(BOOL)b {
	EasyURLDownloaderNotifyDelegate *mydelegate = [[EasyURLDownloaderNotifyDelegate alloc] initWithDelegate:delegate andType:type andURL:url];
	EasyURLOperation *op = [[EasyURLOperation alloc] initWithDownload:url andRecipient:mydelegate cacheBehavior:((nc) ? kEasyURLOperationNoCache : kEasyURLOperationNormalCache)];
	if(b){
		[op setQueuePriority:NSOperationQueuePriorityVeryHigh];
	}
	[queue addOperation:op];
	[op release];
	[mydelegate release];
}

-(void) startDownloadingOnlyFromCache:(NSString*)url withDelegate:(id<EasyURLDownloaderNotifyProtocol>)delegate forType:(const NSString*)type {
	EasyURLDownloaderNotifyDelegate *mydelegate = [[EasyURLDownloaderNotifyDelegate alloc] initWithDelegate:delegate andType:type andURL:url];
	EasyURLOperation *op = [[EasyURLOperation alloc] initWithDownload:url andRecipient:mydelegate cacheBehavior:kEasyURLOperationOnlyCache];
	[queue addOperation:op];
	[op release];
	[mydelegate release];
}

-(void) cancelAllPendingDownloads {
	[queue cancelAllOperations];
}

-(void) cancelAllPendingDownloadsForDelegate:(id<EasyURLDownloaderNotifyProtocol>)delegate {
	EasyURLOperation *op;
	EasyURLDownloaderNotifyDelegate *de;
	NSArray *ops = [queue operations];
	for(op in ops){
		de = [op recipient];
		if([de delegate] == delegate){
			[op cancel];
		}
	}
}


@end
