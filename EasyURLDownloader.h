//
//  EasyURLDownloader.h
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

@protocol EasyURLDownloaderNotifyProtocol<NSObject>
@optional
-(void) downloadForURL:(NSString*)url completeWithObject:(id)object tag:(NSInteger)tag;
-(void) downloadForURL:(NSString*)url failedWithError:(NSError*)error tag:(NSInteger)tag;
-(void) downloadForURL:(NSString*)url hasCompletedPercent:(float)percent tag:(NSInteger)tag;
-(void) downloadForURL:(NSString*)url startedWithResponse:(NSURLResponse*)response tag:(NSInteger)tag;
@end


@interface EasyURLDownloaderNotifyDelegate : NSObject {
	id<EasyURLDownloaderNotifyProtocol> delegate;
	NSMutableData *buffer;
	const NSString *type;
	NSString *urlString;
	long long expectedSize;
	unsigned int statusCode;
	NSInteger tag;
}

@property(readonly, assign) id<EasyURLDownloaderNotifyProtocol> delegate;
@property(readwrite, assign) NSInteger tag;


-(id) initWithDelegate:(id<EasyURLDownloaderNotifyProtocol>)d andURL:(NSString*)u;
-(id) initWithDelegate:(id<EasyURLDownloaderNotifyProtocol>)d andType:(const NSString*)t andURL:(NSString*)u;
-(void) appendData:(NSData*)data;
-(NSData*) data;
-(void) notifyRequestComplete:(NSURLRequest*)req;
-(void) notifyError:(NSError*)error;
-(void) notifyResponse:(NSURLResponse*)response;
@end

typedef enum EnumEasyURLOperationCacheBehavior {
	kEasyURLOperationNormalCache = 0,
	kEasyURLOperationNoCache = 1,
	kEasyURLOperationOnlyCache = 2
} EasyURLOperationCacheBehavior;

@interface EasyURLOperation : NSOperation {
	EasyURLDownloaderNotifyDelegate *recipient;
	NSDictionary * headers;
	NSMutableURLRequest *request;
	NSString *url;
	BOOL finished;
	BOOL running;
	BOOL cancelled;
	EasyURLOperationCacheBehavior cacheBehavior;
	NSURLResponse *responseToCache;
}

@property(readonly, retain) EasyURLDownloaderNotifyDelegate *recipient;
@property(readwrite, retain) NSDictionary * headers;

-(id) initWithDownload:(NSString*)url andRecipient:(EasyURLDownloaderNotifyDelegate*)r cacheBehavior:(EasyURLOperationCacheBehavior)nc;
-(void) connection:(NSURLConnection*)connection didFailWithError:(NSError*) error;
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response;
-(void) connectionDidFinishLoading:(NSURLConnection*)connection;
-(void) connection:(NSURLConnection*)connection didReceiveData:(NSData*) data;
-(NSCachedURLResponse*) connection:(NSURLConnection*)connection willCacheResponse:(NSCachedURLResponse*)response;
-(void) setFinished;


@end


extern const NSString * const kEasyURLDownloadTypeData;
extern const NSString * const kEasyURLDownloadTypeImage;
extern const NSString * const kEasyURLDownloadTypeDictionary;
extern const NSString * const kEasyURLDownloadTypeArray;

@interface EasyURLDownloader : NSObject {
	unsigned int maxConnections;
	NSOperationQueue *queue;
	BOOL isOperating;
	unsigned int currentlyDownloading;
	NSString * userAgent;
	NSString * applicationName;
}

@property(readwrite, assign) unsigned int maxConnections;
@property(readonly, assign) BOOL isOperating;
@property(readonly, assign) unsigned int currentlyDownloading;
@property(readwrite, retain) NSString * userAgent;
@property(readwrite, retain) NSString * applicationName;

+(EasyURLDownloader*) sharedDownloader;
+(void)cancelDownloadsFor:(id<EasyURLDownloaderNotifyProtocol>)delegate;

-(id) init;

-(void) startDownloading:(NSString*)url withDelegate:(id<EasyURLDownloaderNotifyProtocol>)delegate;
-(void) startDownloading:(NSString*)url withDelegate:(id<EasyURLDownloaderNotifyProtocol>)delegate forType:(const NSString*)type;
-(void) startDownloading:(NSString*)url withDelegate:(id<EasyURLDownloaderNotifyProtocol>)delegate forType:(const NSString*)type noCache:(BOOL)nc;
-(void) startDownloading:(NSString*)url withDelegate:(id<EasyURLDownloaderNotifyProtocol>)delegate forType:(const NSString*)type noCache:(BOOL)nc highPriority:(BOOL)b;

-(void) startDownloading:(NSString*)url withDelegate:(id<EasyURLDownloaderNotifyProtocol>)delegate tag:(NSInteger)tag;
-(void) startDownloading:(NSString*)url withDelegate:(id<EasyURLDownloaderNotifyProtocol>)delegate forType:(const NSString*)type tag:(NSInteger)tag;
-(void) startDownloading:(NSString*)url withDelegate:(id<EasyURLDownloaderNotifyProtocol>)delegate forType:(const NSString*)type noCache:(BOOL)nc tag:(NSInteger)tag;
-(void) startDownloading:(NSString*)url withDelegate:(id<EasyURLDownloaderNotifyProtocol>)delegate forType:(const NSString*)type noCache:(BOOL)nc highPriority:(BOOL)b tag:(NSInteger)tag;

-(void) startDownloading:(NSString *)url withDelegate:(id <EasyURLDownloaderNotifyProtocol>)delegate andHeaders:(NSDictionary *)headers tag:(NSInteger)tag;;
-(void) startDownloading:(NSString *)url withDelegate:(id <EasyURLDownloaderNotifyProtocol>)delegate andHeaders:(NSDictionary *)headers forType:(const NSString*)type tag:(NSInteger)tag;;
-(void) startDownloading:(NSString *)url withDelegate:(id <EasyURLDownloaderNotifyProtocol>)delegate andHeaders:(NSDictionary *)headers forType:(const NSString*)type noCache:(BOOL)nc tag:(NSInteger)tag;
-(void) startDownloading:(NSString *)url withDelegate:(id <EasyURLDownloaderNotifyProtocol>)delegate andHeaders:(NSDictionary *)headers forType:(const NSString*)type noCache:(BOOL)nc highPriority:(BOOL)b tag:(NSInteger)tag;

-(void) startDownloadingOnlyFromCache:(NSString*)url withDelegate:(id<EasyURLDownloaderNotifyProtocol>)delegate forType:(const NSString*)type;

-(void) observeValueForKeyPath:(NSString*)keypath ofObject:(id)object change:(NSDictionary*)change context:(void*)context;
-(void) cancelAllPendingDownloads;
-(void) cancelAllPendingDownloadsForDelegate:(id<EasyURLDownloaderNotifyProtocol>)delegate;
@end
