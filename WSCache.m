//
//  WSCache.m
//  Sharepeat
//
//  Created on 16/9/21.
//   2016年 XOR.
//

#import "WSCache.h"
#import <CommonCrypto/CommonDigest.h>

#define WSCache_cachePathDefault @"WSCache_CachePath"
#define WSCache_URLRequestTimeoutInterval 10

#ifdef WSCache_ShowLog
#ifndef CLog
#   define CLog(fmt, ...) {NSLog((@"[line: %d] " fmt), __LINE__, ##__VA_ARGS__);}
#endif
#else
#ifndef CLog
#   define CLog(...)
#endif
#endif


@interface WSCache()

@property (nonatomic) BOOL useMemory; // 是否使用 内存缓存,默认值NO;切换时不会清除已缓存的数据;重启后缓存失效;
@property (nonatomic) NSString *nameSpace; // 默认值nil;cache 空间的目录名称,可以多目录切换;磁盘缓存时,需符合磁盘文件命名规则(支持目录结构/)
@property (nonatomic) BOOL cache2Document; //磁盘缓存时 此选项有效,默认值NO; 默认(NO) temp目录缓存; YES: 保存到document目录中

@property (nonatomic) NSMutableDictionary *cachedDict; // 内存缓存时使用

@end

@implementation WSCache


+(instancetype)sharedObject
{
    static WSCache *cachedObject;
    static dispatch_once_t onceTag;
    dispatch_once(&onceTag, ^{
        cachedObject = [WSCache new];
    });
    return cachedObject;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _useMemory = NO;
        _cache2Document = NO;
        _nameSpace = WSCache_cachePathDefault;
    }
    return self;
}

-(instancetype)initWithNameSpace:(NSString *)nameSpace cache2Document:(BOOL)cache2Document useMemory:(BOOL)useMemory;
{
    self = [super init];
    if (self) {
        _useMemory = useMemory;
        _cache2Document = cache2Document;
        _nameSpace = nameSpace?:WSCache_cachePathDefault; //??? 自我回收
        _cachedDict = useMemory?[NSMutableDictionary new]:nil;
    }
    return self;
}

-(void)setNameSpace:(NSString *)nameSpace
{
    _nameSpace = nameSpace;
    if (!_nameSpace) {
        _nameSpace = WSCache_cachePathDefault;
    }
}

-(void)dealloc
{
    if (_cachedDict.count>0) {
        [_cachedDict removeAllObjects];
    }
    _cachedDict = nil;
}

// save
- (BOOL)saveData:(NSData*)data withKey:(NSString *)key
{
    //check errors
    if (key==nil) {
        return NO;
    }
    
    if (_useMemory) {
        NSMutableDictionary *namedDict = [_cachedDict objectForKey:_nameSpace];
        if (!namedDict) {
            namedDict = [NSMutableDictionary new];
            [_cachedDict setObject:namedDict forKey:_nameSpace];
        }
        if (data) {
            if (!namedDict) {
                namedDict = [NSMutableDictionary new];
                [_cachedDict setObject:namedDict forKey:_nameSpace];
            }
            [namedDict setObject:data forKey:key];
        }else{
            if (namedDict) {
                [namedDict removeObjectForKey:key];
            }
        }
        
        return YES;
    }
    
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *keyHash = [self MD5String:key];
    NSString *keyPath = [self filePathForKey:keyHash];
    if (data.length==0) { // delete
        BOOL isDir = NO;
        NSError *error;
        if ([fm fileExistsAtPath:keyPath isDirectory:&isDir] && !isDir){
            NSString *dataHash = [NSString stringWithContentsOfFile:keyPath encoding:NSUTF8StringEncoding error:&error];
            if (dataHash) { // check data
                NSString *dataFolderPath = [self filePathForKey:dataHash];
                NSArray *contents = [fm contentsOfDirectoryAtPath:dataFolderPath error:&error];
                if (contents.count<=2) {//need delete data
                    BOOL result = [fm removeItemAtPath:dataFolderPath error:&error];
                    if (result) {
                        CLog(@"remove cached data[key:%@] ok",key);
                    }else{
                        CLog(@"remove cached data[key:%@] error:%@",key,error);
                        return NO;
                    }
                }else{ // delete data->key reference
                    NSString *keyRefPath = [dataFolderPath stringByAppendingPathComponent:keyHash];
                    if ([fm fileExistsAtPath:keyRefPath]) {
                        BOOL result = [fm removeItemAtPath:keyRefPath error:&error];
                        if (result) {
                            CLog(@"remove data->key reference[key:%@] ok",key);
                        }else{
                            CLog(@"remove data[key:%@] error:%@",key,error);
                            return NO;
                        }
                    }
                }
                
            }
            
            // remove key->data file
            if ([fm fileExistsAtPath:keyPath]) {
                BOOL result = [fm removeItemAtPath:keyPath error:&error];
                if (!result) {
                    CLog(@"remove reference data[key:%@] error:%@",key,error);
                    return NO;
                }
            }
            CLog(@"remove reference data[key:%@] ok",key);
            return YES;
        }
        
        CLog(@"no data cached");
        return YES;
    }
    
    
    // normal
    NSString *dataHash = [self MD5Data:data];
    NSString *dataFolderPath = [self filePathForKey:dataHash];
    NSString *dataPath = [dataFolderPath stringByAppendingPathComponent:dataHash];
    NSString *keyRefPath = [dataFolderPath stringByAppendingPathComponent:keyHash];
    
    NSError *error;
    BOOL isDir;
    if ([fm fileExistsAtPath:dataPath isDirectory:&isDir] && !isDir) { // exist
        BOOL result = [keyHash writeToFile:keyRefPath atomically:YES encoding:NSUTF8StringEncoding error:&error];
        if (!result) {
            CLog(@"cache data[key:%@] reference fail:%@",key,error);
            return NO;
        }
        
        result = [dataHash writeToFile:keyPath atomically:YES encoding:NSUTF8StringEncoding error:&error];
        if (result) {
            CLog(@"cache reference data[key:%@] ok",key);
            return YES;
        }else{
            CLog(@"save key->data[key:%@] error:%@ ",key,error);
            return NO;
        }
        
    }else{ // add new file
        if(![fm fileExistsAtPath:dataFolderPath isDirectory:&isDir] || !isDir){
            BOOL result = [fm createDirectoryAtPath:dataFolderPath withIntermediateDirectories:YES attributes:nil error:&error];
            if (!result) {
                CLog(@"create cacheFolder fail:%@",error);
                return NO;
            }
        }
        //    BOOL result = [fm createFileAtPath:dataPath contents:data attributes:nil];
        BOOL result = [data writeToFile:dataPath options:NSDataWritingWithoutOverwriting error:&error];
        if (result) {
            CLog(@"save new data[key:%@] ok",key);
            // write key->data reference
            result = [keyHash writeToFile:keyRefPath atomically:YES encoding:NSUTF8StringEncoding error:&error];
            // write data->key reference
            result = [dataHash writeToFile:keyPath atomically:YES encoding:NSUTF8StringEncoding error:&error];
            if (result) {
                CLog(@"cache new data[key:%@] ok",key);
                return YES;
            }else{
                CLog(@"save key->data[key:%@] error:%@ ",key,error);
                return NO;
            }
        }else{
            CLog(@"save new data[key:%@] error:%@",key,error);
            return NO;
        }
        
    }
    
    CLog(@"unknow error");
    return NO;
}


-(BOOL)saveObject:(id)object withKey:(NSString *)key
{
    if (key==nil) {
        return NO;
    }
    //  if ([object isKindOfClass:[NSCoder class]]) {
    if (object) {
        NSData *objData = [NSKeyedArchiver archivedDataWithRootObject:object];
        return [self saveData:objData withKey:key];
    }
    return [self saveData:nil withKey:key];
    //  }
    //  CLog(@"object is not kind of class: NSCoder ");
    //  return NO;
}


// read
- (NSData *)getDataForKey:(NSString *)key
{
    /**
     // 清理多余的数据
     static BOOL isCheckedCacheDisk = NO;
     if (!isCheckedCacheDisk) {
     NSFileManager *manager = [NSFileManager defaultManager];
     NSArray *contents = [manager contentsOfDirectoryAtPath:[self cachePath] error:nil];
     if (contents.count >= kSDMaxCacheFileAmount) {
     [manager removeItemAtPath:[self cachePath] error:nil];
     }
     isCheckedCacheDisk = YES;
     }
     */
    
    if (key==nil) {
        return nil;
    }
    
    if (_useMemory) {
        NSMutableDictionary *namedDict = [_cachedDict objectForKey:_nameSpace];
        return [namedDict objectForKey:key];
    }
    
    NSString *keyHash = [self MD5String:key];
    NSString *keyPath = [self filePathForKey:keyHash];
    
    //  NSString *dataHash = [self MD5Data:data];
    //  NSString *dataFolderPath = [self filePathForKey:dataHash];
    //  NSString *dataPath = [dataFolderPath stringByAppendingPathComponent:dataHash];
    //  NSString *keyRefPath = [dataFolderPath stringByAppendingPathComponent:keyHash];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    
    NSError *error;
    BOOL isDir;
    if ([fm fileExistsAtPath:keyPath isDirectory:&isDir] && !isDir) {
        NSString *dataHash = [NSString stringWithContentsOfFile:keyPath encoding:NSUTF8StringEncoding error:&error];
        if (error) {
            CLog(@"get data[key:%@] reference error:%@",key,error);
        }
        if (dataHash) {
            NSString *dataFolderPath = [self filePathForKey:dataHash];
            NSString *dataPath = [dataFolderPath stringByAppendingPathComponent:dataHash];
            NSData *data = [NSData dataWithContentsOfFile:dataPath options:NSDataReadingMappedIfSafe error:&error];
            CLog(@"get cached data[key:%@] %@ ",key,(data?@"ok":@"no data"));
            return data;
        }
    }
    return nil;
}

-(NSString *)getDataPathForKey:(NSString *)key
{
    if (key==nil) {
        return nil;
    }
    NSString *keyHash = [self MD5String:key];
    NSString *keyPath = [self filePathForKey:keyHash];
    NSString *dataHash = [NSString stringWithContentsOfFile:keyPath encoding:NSUTF8StringEncoding error:nil];
    if (dataHash) {
        NSString *dataFolderPath = [self filePathForKey:dataHash];
        NSString *dataPath = [dataFolderPath stringByAppendingPathComponent:dataHash];
        
        BOOL isDir;
        if ([[NSFileManager defaultManager] fileExistsAtPath:dataPath isDirectory:&isDir] && !isDir) {
            return dataPath;
        }
    }
    return nil;
}


-(id)getObjectForKey:(NSString*)key
{
    NSString *dataPath = [self getDataPathForKey:key];
    return [NSKeyedUnarchiver unarchiveObjectWithFile:dataPath];
}

-(BOOL)clearAllData
{
    if (_useMemory) {
        [_cachedDict removeObjectForKey:_nameSpace];
        return YES;
    }
    
    NSString *filesPath = [self cachePath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:filesPath]) {
        NSError *error;
        BOOL result = [[NSFileManager defaultManager] removeItemAtPath:filesPath error:&error];
        if (!result || error) {
            CLog(@"clearAllData error:%@ ",error);
            return NO;
        }
    }
    return YES;
}


// tools
- (NSString *)filePathForKey:(NSString *)string
{
    NSString *basePath = [self cachePath];
    return (string.length >0)?[basePath stringByAppendingPathComponent:string]:basePath;
}

- (NSString *)cachePath
{
    NSString *path;
    if(_cache2Document){
        path = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
        path = [path stringByAppendingPathComponent:@"WSCache"];
    }else{
        path =[NSSearchPathForDirectoriesInDomains(NSCachesDirectory,NSUserDomainMask,YES) lastObject];
    }
    path = [path stringByAppendingPathComponent:_nameSpace?:WSCache_cachePathDefault];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        NSError *error;
        BOOL isOK = [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error];
        if (error || !isOK) {
            CLog(@"get cachePath error:%@",error);
            return nil;
        }
    }
    return path;
}

- (NSString *)MD5String:(NSString *)string
{
    const char *str = [string UTF8String];
    unsigned char r[CC_MD5_DIGEST_LENGTH];
    CC_MD5(str, (CC_LONG)strlen(str), r);
    return [NSString stringWithFormat:@"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
            r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9], r[10], r[11], r[12], r[13], r[14], r[15]];
}

- (NSString *) MD5Data:(NSData*)data
{
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    CC_MD5([data bytes], (CC_LONG)[data length], result);
    NSMutableString *hash = [NSMutableString string];
    for (int i = 0; i < 16; i++)
        [hash appendFormat:@"%02X", result[i]];
    [hash lowercaseString];
    return hash;
    
    /*
     unsigned char hash[CC_SHA1_DIGEST_LENGTH];
     (void) CC_SHA1( [data bytes], (CC_LONG)[data length], hash );
     return ( [NSData dataWithBytes: hash length: CC_MD5_DIGEST_LENGTH] );
     */
}


@end



@implementation WSCache (netData)



// 加载数据期间,切换space时数据会存储到新的space空间(单例模式下)
-(NSData *)getDataForKey:(NSString*)key withUrl:(NSURL*)theUrl callback:(WSCacheDownloadBlock)theBlock
{
    NSData *data = [self getDataForKey:key];
    if (theUrl) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            //      NSData *urlData = [NSData dataWithContentsOfURL:theUrl options:NSDataReadingMappedIfSafe error:&error];
            NSHTTPURLResponse *response = nil;
            NSError *error = nil;
            NSURLRequest *request = [NSURLRequest requestWithURL:theUrl cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:WSCache_URLRequestTimeoutInterval];
            NSData *urlData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
            
            BOOL isOk = NO;
            if([response isKindOfClass:[NSHTTPURLResponse class]]){
                if (response.statusCode>=200 && response.statusCode<300) {
                    isOk = YES;
                }
            }else{
                isOk = !error;
            }
            
            if (isOk) {
                [self saveData:urlData withKey:key];
            }else{
                error = error?:[NSError errorWithDomain:@"get data error" code:response.statusCode userInfo:nil];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                theBlock(isOk,urlData,error);
            });
            
        });
    }
    return data;
}


@end

@implementation WSCache (UIImage)

-(BOOL)saveImage:(UIImage*)image withKey:(NSString *)key
{
    if(key==nil){
        return NO;
    }
    NSData *imgData = UIImagePNGRepresentation(image);
    if (imgData.length>0) {
        return [self saveData:imgData withKey:key];
    }
    // error
    CLog(@"prese image error");
    return NO;
}


-(UIImage*)getImageForKey:(NSString*)key
{
    NSString *imgPath = [self getDataPathForKey:key];
    return [UIImage imageWithContentsOfFile:imgPath];
}

// 加载数据期间,切换space时数据会存储到新的space空间(单例模式下)
-(UIImage*)getImageForKey:(NSString*)key withUrl:(NSURL*)theUrl callback:(WSCacheDownloadBlock)theBlock
{
    UIImage *image = [self getImageForKey:key];
    if (theUrl) {
        
        [self getDataForKey:key withUrl:theUrl callback:^(BOOL operRes, NSData *urlData, NSError *errorMsg) {
            if (operRes) {
                UIImage *urlImage;
                if (urlData.length>0) {
                    urlImage = [UIImage imageWithData:urlData];
                    if (!urlImage) {
                        [self saveData:nil withKey:key];
                        NSLog(@"cound not parse imageData:%@ , error:%@",theUrl,errorMsg);
                    }
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    theBlock(YES,urlImage,errorMsg);
                });
            }else{
                dispatch_async(dispatch_get_main_queue(), ^{
                    theBlock(NO,nil,errorMsg);
                });
            }
        }];
    }
    return image;
}


@end


/**
 
 需要导入Security.framework
 
 */
@implementation WSCache (keyChain)

+ (NSMutableDictionary *)getKeychainQuery:(NSString *)service {
    return [NSMutableDictionary dictionaryWithObjectsAndKeys:
            (__bridge_transfer id)kSecClassGenericPassword,(__bridge_transfer id)kSecClass,
            service, (__bridge_transfer id)kSecAttrService,
            service, (__bridge_transfer id)kSecAttrAccount,
            (__bridge_transfer id)kSecAttrAccessibleAfterFirstUnlock,(__bridge_transfer id)kSecAttrAccessible,
            nil];
}

+ (void)saveKeychainData:(id)data service:(NSString *)service {
    //Get search dictionary
    NSMutableDictionary *keychainQuery = [self getKeychainQuery:service];
    //Delete old item before add new item
    SecItemDelete((__bridge_retained CFDictionaryRef)keychainQuery);
    //Add new object to search dictionary(Attention:the data format)
    [keychainQuery setObject:[NSKeyedArchiver archivedDataWithRootObject:data] forKey:(__bridge_transfer id)kSecValueData];
    //Add item to keychain with the search dictionary
    SecItemAdd((__bridge_retained CFDictionaryRef)keychainQuery, NULL);
}

+ (id)loadKeychainData:(NSString *)service {
    id ret = nil;
    NSMutableDictionary *keychainQuery = [self getKeychainQuery:service];
    //Configure the search setting
    [keychainQuery setObject:(id)kCFBooleanTrue forKey:(__bridge_transfer id)kSecReturnData];
    [keychainQuery setObject:(__bridge_transfer id)kSecMatchLimitOne forKey:(__bridge_transfer id)kSecMatchLimit];
    CFDataRef keyData = NULL;
    if (SecItemCopyMatching((__bridge_retained CFDictionaryRef)keychainQuery, (CFTypeRef *)&keyData) == noErr) {
        @try {
            ret = [NSKeyedUnarchiver unarchiveObjectWithData:(__bridge_transfer NSData *)keyData];
        } @catch (NSException *e) {
            NSLog(@"Unarchive of %@ failed: %@", service, e);
        } @finally {
        }
    }
    return ret;
}

+ (void)deleteKeychainData:(NSString *)service {
    NSMutableDictionary *keychainQuery = [self getKeychainQuery:service];
    SecItemDelete((__bridge_retained CFDictionaryRef)keychainQuery);
}

@end

