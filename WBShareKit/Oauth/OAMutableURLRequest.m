//
//  OAMutableURLRequest.m
//  OAuthConsumer
//
//  Created by Jon Crosby on 10/19/07.
//  Copyright 2007 Kaboomerang LLC. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.


#import "OAMutableURLRequest.h"


@interface OAMutableURLRequest (Private)
- (void)_generateTimestamp;
- (void)_generateNonce;
- (NSString *)_signatureBaseString;
@end

@implementation OAMutableURLRequest
@synthesize signature, nonce;

#pragma mark init

- (id)initWithURL:(NSURL *)aUrl
		 consumer:(OAConsumer *)aConsumer
			token:(OAToken *)aToken
            realm:(NSString *)aRealm
signatureProvider:(id<OASignatureProviding, NSObject>)aProvider 
{
    if (self = [super initWithURL:aUrl
					  cachePolicy:NSURLRequestReloadIgnoringCacheData
				  timeoutInterval:10.0])
	{    
		consumer = [aConsumer retain];
		
		// empty token for Unauthorized Request Token transaction
		if (aToken == nil)
			token = [[OAToken alloc] init];
		else
			token = [aToken retain];
		
		if (aRealm == nil)
			realm = [[NSString alloc] initWithString:@""];
		else 
			realm = [aRealm retain];
		
		// default to HMAC-SHA1
		if (aProvider == nil)
			signatureProvider = [[OAHMAC_SHA1SignatureProvider alloc] init];
		else 
			signatureProvider = [aProvider retain];
		
		[self _generateTimestamp];
		[self _generateNonce];
	}
    return self;
}

// Setting a timestamp and nonce to known
// values can be helpful for testing
- (id)initWithURL:(NSURL *)aUrl
		 consumer:(OAConsumer *)aConsumer
			token:(OAToken *)aToken
            realm:(NSString *)aRealm
signatureProvider:(id<OASignatureProviding, NSObject>)aProvider
            nonce:(NSString *)aNonce
        timestamp:(NSString *)aTimestamp 
{
	if (self = [super initWithURL:aUrl
					  cachePolicy:NSURLRequestReloadIgnoringCacheData
				  timeoutInterval:10.0])
	{    
		consumer = [aConsumer retain];
		
		// empty token for Unauthorized Request Token transaction
		if (aToken == nil)
			token = [[OAToken alloc] init];
		else
			token = [aToken retain];
		
		if (aRealm == nil)
			realm = [[NSString alloc] initWithString:@""];
		else 
			realm = [aRealm retain];
		
		// default to HMAC-SHA1
		if (aProvider == nil)
			signatureProvider = [[OAHMAC_SHA1SignatureProvider alloc] init];
		else 
			signatureProvider = [aProvider retain];
		
		timestamp = [aTimestamp retain];
		nonce = [aNonce retain];
	}
    return self;
}

- (void)dealloc
{
	[consumer release];
	[token release];
	[realm release];
	[signatureProvider release];
	[timestamp release];
	[nonce release];
	[extraOAuthParameters release];
	[super dealloc];
}

#pragma mark -
#pragma mark Public

- (void)setOAuthParameterName:(NSString*)parameterName withValue:(NSString*)parameterValue
{
	assert(parameterName && parameterValue);
	
	if (extraOAuthParameters == nil) {
		extraOAuthParameters = [NSMutableDictionary new];
	}
	
	[extraOAuthParameters setObject:parameterValue forKey:parameterName];
}

- (void)prepare 
{
    // sign
	// Secrets must be urlencoded before concatenated with '&'
	// TODO: if later RSA-SHA1 support is added then a little code redesign is needed
	NSString *signClearText = [self _signatureBaseString];
	NSString *secret = [NSString stringWithFormat:@"%@&%@",
						[consumer.secret URLEncodedString],
						[token.secret URLEncodedString]];
    signature = [signatureProvider signClearText:signClearText
                                      withSecret:secret];
    
    // set OAuth headers
    NSString *oauthToken;
    if ([token.key isEqualToString:@""])
        oauthToken = @""; // not used on Request Token transactions
    else
        oauthToken = [NSString stringWithFormat:@"oauth_token=\"%@\", ", [token.key URLEncodedString]];
	
	NSMutableString *extraParameters = [NSMutableString string];
	
	// Adding the optional parameters in sorted order isn't required by the OAuth spec, but it makes it possible to hard-code expected values in the unit tests.
	for(NSString *parameterName in [[extraOAuthParameters allKeys] sortedArrayUsingSelector:@selector(compare:)])
	{
		[extraParameters appendFormat:@", %@=\"%@\"",
		 [parameterName URLEncodedString],
		 [[extraOAuthParameters objectForKey:parameterName] URLEncodedString]];
	}	
	
	//NSLog(@"%@",extraParameters);
    
    NSString *oauthHeader = [NSString stringWithFormat:@"OAuth realm=\"%@\", oauth_consumer_key=\"%@\", %@oauth_signature_method=\"%@\", oauth_signature=\"%@\", oauth_timestamp=\"%@\", oauth_nonce=\"%@\", oauth_version=\"1.0\"%@",
                             [realm URLEncodedString],
                             [consumer.key URLEncodedString],
                             oauthToken,
                             [[signatureProvider name] URLEncodedString],
                             [signature URLEncodedString],
                             timestamp,
                             nonce,
							 extraParameters];
	
	if (token.pin.length) oauthHeader = [oauthHeader stringByAppendingFormat: @", oauth_verifier=\"%@\"", token.pin];					//added for the Twitter OAuth implementation
    // NSLog(@"oauthHeader:%@", oauthHeader);
	[self setValue:oauthHeader forHTTPHeaderField:@"Authorization"];
}

#pragma mark -
#pragma mark Private

- (void)_generateTimestamp 
{
    timestamp = [[NSString stringWithFormat:@"%d", time(NULL)] retain];
}

- (void)_generateNonce 
{
    CFUUIDRef theUUID = CFUUIDCreate(NULL);
    CFStringRef string = CFUUIDCreateString(NULL, theUUID);
    NSMakeCollectable(theUUID);
    nonce = (NSString *)string;
}

- (NSString *)_signatureBaseString 
{
	NSArray *parameters = [self parameters];
    // OAuth Spec, Section 9.1.1 "Normalize Request Parameters"
    // build a sorted array of both request parameters and OAuth header parameters
    NSMutableArray *parameterPairs = [NSMutableArray  arrayWithCapacity:(6 + [parameters count])]; // 6 being the number of OAuth params in the Signature Base String
    
	[parameterPairs addObject:[[OARequestParameter requestParameterWithName:@"oauth_consumer_key" value:consumer.key] URLEncodedNameValuePair]];
	[parameterPairs addObject:[[OARequestParameter requestParameterWithName:@"oauth_signature_method" value:[signatureProvider name]] URLEncodedNameValuePair]];
	[parameterPairs addObject:[[OARequestParameter requestParameterWithName:@"oauth_timestamp" value:timestamp] URLEncodedNameValuePair]];
	[parameterPairs addObject:[[OARequestParameter requestParameterWithName:@"oauth_nonce" value:nonce] URLEncodedNameValuePair]];
	[parameterPairs addObject:[[OARequestParameter requestParameterWithName:@"oauth_version" value:@"1.0"] URLEncodedNameValuePair]];
    
    if (![token.key isEqualToString:@""]) {
        [parameterPairs addObject:[[OARequestParameter requestParameterWithName:@"oauth_token" value:token.key] URLEncodedNameValuePair]];
    }
	if (token.pin.length > 0) [parameterPairs addObject:[[OARequestParameter requestParameterWithName:@"oauth_verifier" value:token.pin] URLEncodedNameValuePair]];		//added for the Twitter OAuth implementation
    
    for (OARequestParameter *param in parameters) {
        [parameterPairs addObject:[param URLEncodedNameValuePair]];
    }
    
    NSArray *sortedPairs = [parameterPairs sortedArrayUsingSelector:@selector(compare:)];
    NSString *normalizedRequestParameters = [sortedPairs componentsJoinedByString:@"&"];
    // OAuth Spec, Section 9.1.2 "Concatenate Request Elements"
    NSString *ret = [NSString stringWithFormat:@"%@&%@&%@",
					 [self HTTPMethod],
					 [[[self URL] URLStringWithoutQuery] URLEncodedString],
					 [normalizedRequestParameters URLEncodedString]];
//	NSLog(@"base string:%@",ret);
    // NSLog(@"normalizedRequestParameters: %@, ret: %@",normalizedRequestParameters, ret);
	return ret;
}

- (NSString *)generateNonce {
	// Just a simple implementation of a random number between 123400 and 9999999
	return [NSString stringWithFormat:@"%u", arc4random() % (9999999 - 123400) + 123400];
}

- (NSString *)txBaseString
{
    NSArray *parameters = [self parameters];
    
    
    // OAuth Spec, Section 9.1.1 "Normalize Request Parameters"
    // build a sorted array of both request parameters and OAuth header parameters
    NSMutableArray *parameterPairs = [NSMutableArray  arrayWithCapacity:(6 + [parameters count])]; // 6 being the number of OAuth params in the Signature Base String
    
	[parameterPairs addObject:[[OARequestParameter requestParameterWithName:@"oauth_consumer_key" value:consumer.key] URLEncodedNameValuePair]];
	[parameterPairs addObject:[[OARequestParameter requestParameterWithName:@"oauth_signature_method" value:[signatureProvider name]] URLEncodedNameValuePair]];
	[parameterPairs addObject:[[OARequestParameter requestParameterWithName:@"oauth_timestamp" value:timestamp] URLEncodedNameValuePair]];
	[parameterPairs addObject:[[OARequestParameter requestParameterWithName:@"oauth_nonce" value:[self generateNonce]] URLEncodedNameValuePair]];
	[parameterPairs addObject:[[OARequestParameter requestParameterWithName:@"oauth_version" value:@"1.0"] URLEncodedNameValuePair]];
//    [parameterPairs addObject:[[OARequestParameter requestParameterWithName:@"oauth_callback" value:CallBackURL] URLEncodedNameValuePair]];
    
//    [parameterPairs addObject:[[OARequestParameter requestParameterWithName:@"oauth_signature" value:_signature] URLEncodedNameValuePair]];
    
    if (![token.key isEqualToString:@""]) {
        [parameterPairs addObject:[[OARequestParameter requestParameterWithName:@"oauth_token" value:token.key] URLEncodedNameValuePair]];
    }
	if (token.pin.length > 0) [parameterPairs addObject:[[OARequestParameter requestParameterWithName:@"oauth_verifier" value:token.pin] URLEncodedNameValuePair]];		//added for the Twitter OAuth implementation
    
    for (OARequestParameter *param in parameters) {
        [parameterPairs addObject:[param URLEncodedNameValuePair]];
    }
    
//    NSLog(@"%@,%@",parameters,parameterPairs);
    
    NSArray *sortedPairs = [parameterPairs sortedArrayUsingSelector:@selector(compare:)];
    NSString *normalizedRequestParameters = [sortedPairs componentsJoinedByString:@"&"];
    // OAuth Spec, Section 9.1.2 "Concatenate Request Elements"
    NSString *ret = [NSString stringWithFormat:@"%@",
					 normalizedRequestParameters];
    
    NSString *txret = [NSString stringWithFormat:@"%@&%@&%@",
					 [self HTTPMethod],
					 [[[self URL] URLStringWithoutQuery] URLEncodedString],
					 [normalizedRequestParameters URLEncodedString]];
//	NSLog(@"base string:%@",txret);
    // NSLog(@"norma
    
    NSString *signClearText = txret;
	NSString *secret = [NSString stringWithFormat:@"%@&%@",
						[consumer.secret URLEncodedString],
						[token.secret URLEncodedString]];
    NSString *_signature = [signatureProvider signClearText:signClearText
                                                 withSecret:secret];
    
    return [NSString stringWithFormat:@"%@&oauth_signature=%@",ret,[_signature URLEncodedString]];
}

- (NSString *)txPhotoBaseString
{
    NSArray *parameters = [self parameters];
    
    
    // OAuth Spec, Section 9.1.1 "Normalize Request Parameters"
    // build a sorted array of both request parameters and OAuth header parameters
    NSMutableArray *parameterPairs = [NSMutableArray  arrayWithCapacity:(6 + [parameters count])]; // 6 being the number of OAuth params in the Signature Base String
    
	[parameterPairs addObject:[[OARequestParameter requestParameterWithName:@"oauth_consumer_key" value:consumer.key] URLEncodedNameValuePair]];
	[parameterPairs addObject:[[OARequestParameter requestParameterWithName:@"oauth_signature_method" value:[signatureProvider name]] URLEncodedNameValuePair]];
	[parameterPairs addObject:[[OARequestParameter requestParameterWithName:@"oauth_timestamp" value:timestamp] URLEncodedNameValuePair]];
	[parameterPairs addObject:[[OARequestParameter requestParameterWithName:@"oauth_nonce" value:[self generateNonce]] URLEncodedNameValuePair]];
	[parameterPairs addObject:[[OARequestParameter requestParameterWithName:@"oauth_version" value:@"1.0"] URLEncodedNameValuePair]];
    //    [parameterPairs addObject:[[OARequestParameter requestParameterWithName:@"oauth_callback" value:CallBackURL] URLEncodedNameValuePair]];
    
    //    [parameterPairs addObject:[[OARequestParameter requestParameterWithName:@"oauth_signature" value:_signature] URLEncodedNameValuePair]];
    
    if (![token.key isEqualToString:@""]) {
        [parameterPairs addObject:[[OARequestParameter requestParameterWithName:@"oauth_token" value:token.key] URLEncodedNameValuePair]];
    }
	if (token.pin.length > 0) [parameterPairs addObject:[[OARequestParameter requestParameterWithName:@"oauth_verifier" value:token.pin] URLEncodedNameValuePair]];		//added for the Twitter OAuth implementation
    
    for (OARequestParameter *param in parameters) {
        [parameterPairs addObject:[param URLEncodedNameValuePair]];
    }
    
//    NSLog(@"%@,%@",parameters,parameterPairs);
    
    NSArray *sortedPairs = [parameterPairs sortedArrayUsingSelector:@selector(compare:)];
    NSMutableString *normalizedRequestParameters = [[[NSMutableString alloc] init] autorelease];
    
    NSString *boundary = @"WBShareKit";
    NSString *boundarystr = [NSString stringWithFormat:@"\r\n--%@\r\n", boundary];
    NSString *formDataTemplate = @"\r\n--%@\r\nContent-Disposition: form-data; name=\"%@\"\r\n\r\n%@";
    for (NSString *str in sortedPairs) {
        NSArray *arr = [str componentsSeparatedByString:@"="];
        NSString *value = [arr lastObject];
        NSString *key = [arr objectAtIndex:0];
        NSString *formItem = [NSString stringWithFormat:formDataTemplate, boundary, key, value];
        [normalizedRequestParameters appendString:formItem];
        
    }
    [normalizedRequestParameters appendString:boundarystr];
    // OAuth Spec, Section 9.1.2 "Concatenate Request Elements"
//    NSString *ret = [NSString stringWithFormat:@"%@",
//					 normalizedRequestParameters];
//    
    NSString *txret = [NSString stringWithFormat:@"%@&%@&%@",
                       [self HTTPMethod],
                       [[[self URL] URLStringWithoutQuery] URLEncodedString],
                       [normalizedRequestParameters URLEncodedString]];
//	NSLog(@"base string:%@",txret);
    // NSLog(@"norma
    
    NSString *signClearText = txret;
	NSString *secret = [NSString stringWithFormat:@"%@&%@",
						[consumer.secret URLEncodedString],
						[token.secret URLEncodedString]];
    NSString *_signature = [signatureProvider signClearText:signClearText
                                                 withSecret:secret];
    
    NSString *formItem = [NSString stringWithFormat:formDataTemplate, boundary, @"oauth_signature", [_signature URLEncodedString]];
    [normalizedRequestParameters appendString:formItem];
    [normalizedRequestParameters appendString:boundarystr];
    
    return normalizedRequestParameters;
}

@end
