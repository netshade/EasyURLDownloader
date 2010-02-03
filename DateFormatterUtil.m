//
//  DateFormatterUtil.m
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

#import "DateFormatterUtil.h"


@implementation DateFormatterUtil

+(DateFormatterUtil*)sharedFormatter {
	static DateFormatterUtil *sf;
	if(!sf){
		sf = [[DateFormatterUtil alloc] init];
	}
	return sf;
}

-(id) init {
	if(self = [super init]){
		formatters = [[NSMutableDictionary alloc] init];
	}
	return self;
}

-(void) dealloc {
	[formatters release];
	[super dealloc];
}

-(NSDateFormatter*) formatterForFormat:(NSString*)format {
	NSDateFormatter *fmt = (NSDateFormatter*)[formatters objectForKey:format];
	if(!fmt){
		fmt = [[NSDateFormatter alloc] init];
		[fmt setDateFormat:format];
		[formatters setObject:fmt forKey:format];
		[fmt release];
	}
	return fmt;
}

-(NSDate*) dateFromString:(NSString*)str withFormat:(NSString*)format {
	NSDateFormatter *fmt = [self formatterForFormat:format];
	return [fmt dateFromString:str];
}

-(NSString*) stringFromDate:(NSDate*)dt withFormat:(NSString*)format {
	NSDateFormatter *fmt = [self formatterForFormat:format];
	return [fmt stringFromDate:dt];
}

@end
