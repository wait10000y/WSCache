//
//  WSCache.h
//  Sharepeat
//
//  Created on 16/9/21.
//   2016年 XOR.
//


/*
 
 // 单例模式
 WSCache *cacheUtil = [WSCache sharedObject];
 // 自定义模式
 //  WSCache *cacheUtil = [[WSCache alloc] initWithNameSpace:@"WSCache_testSpace" cache2Document:NO useMemory:NO];
 
 NSString *cacheKey = @"cacheSearchKey";
 
 NSData *cachedData = [cacheUtil getDataForKey:cacheKey];
 id cachedObj = [cacheUtil getObjectForKey:cacheKey];
 UIImage *cachedImg = [cacheUtil getImageForKey:cacheKey];
 // 返回缓存中查找的image; callback传回的网络请求后的结果(如果是结果正确image会被更新到缓存)
 UIImage *cachedImg2 = [cacheUtil getImageForKey:cacheKey withUrl:[NSURL URLWithString:@""] callback:^(BOOL operRes, UIImage *dataObj, NSError *errorMsg) {
 if(operRes){
 
 }
 }];
 
 [cacheUtil saveData:nil withKey:cacheKey];
 [cacheUtil saveImage:nil withKey:cacheKey];
 [cacheUtil saveObject:nil withKey:cacheKey];
 
 
 UIImage *img = [cacheUtil getImageForKey:cacheKey];
 NSLog(@"--- load cached image[key:%@]:%@ ----",cacheKey,(img)?@"ok":@"no cached");
 if (!img) {
 img = [UIImage imageNamed:@"demo_image"];
 [cacheUtil saveImage:img withKey:cacheKey];
 }
 
 
 
 
 
 // ---- 结构体保存方法: ----
 // assume ImaginaryNumber defined:
 typedef struct {
 float real;
 float imaginary;
 } ImaginaryNumber;
 
 
 ImaginaryNumber miNumber;
 miNumber.real = 1.1;
 miNumber.imaginary = 1.41;
 
 NSValue *miValue = [NSValue valueWithBytes: &miNumber
 withObjCType:@encode(ImaginaryNumber)];
 
 
 ImaginaryNumber miNumber2;
 [miValue getValue:&miNumber2];
 
 // ---- 结构体 直接转换成data ----
 NSData *data = [NSData dataWithBytes:&miNumber length:sizeof(miNumber)];
 
 // NSData to ImaginaryNumber
 [data getBytes:&miNumber length:sizeof(miNumber)];
 
 
 
 // ---- cString 保存方法: ----
 char *myCString = "This is a string.";
 NSValue *theValue = [NSValue valueWithBytes:&myCString withObjCType:@encode(char **)];
 
 
 // ---- 其他数据 转换方法 ----
 NSString *NSStringFromCGPoint( CGPoint point);
 NSString *NSStringFromCGSize( CGSize size);
 NSString *NSStringFromCGRect( CGRect rect);
 NSString *NSStringFromCGAffineTransform( CGAffineTransform transform);
 NSString *NSStringFromUIEdgeInsets( UIEdgeInsets insets);
 NSString *NSStringFromUIOffset( UIOffset offset);
 
 
 
 */


#import <Foundation/Foundation.h>

//#define WSCache_ShowLog 1 // 是否显示调试日志
@class UIImage;
@interface WSCache : NSObject


+(instancetype)sharedObject;

-(instancetype)initWithNameSpace:(NSString *)nameSpace cache2Document:(BOOL)cache2Document useMemory:(BOOL)useMemory;

- (BOOL)saveData:(NSData*)data withKey:(NSString *)key;
// 使用序列化保存
-(BOOL)saveObject:(id)object withKey:(NSString *)key;

- (NSData *)getDataForKey:(NSString *)key;
-(id)getObjectForKey:(NSString*)key;

-(BOOL)clearAllData;


@end



// operRes:下载是否成功, data:返回的数据内容,error:错误提示
typedef void(^WSCacheDownloadBlock)(BOOL operRes,id dataObj,NSError *errorMsg);
@interface WSCache (netData)

// 从网络获取数据,如果已经有缓存更新缓存;每次调用都会从网络请求更新一次;
// 返回当前缓存的数据,如果缓存不存在返回nil;
// block 返回网络请求的结果.
-(NSData *)getDataForKey:(NSString*)key withUrl:(NSURL*)theUrl callback:(WSCacheDownloadBlock)theBlock;

@end


#import <UIKit/UIKit.h>
@interface WSCache (UIImage)

-(BOOL)saveImage:(UIImage*)image withKey:(NSString *)key;
-(UIImage*)getImageForKey:(NSString*)key;

// 从网络获取图片,如果已经有缓存更新缓存;每次调用都会从网络请求更新一次;
// 返回当前缓存的照片,如果缓存不存在返回nil;
// block 返回网络请求的结果.
-(UIImage *)getImageForKey:(NSString*)key withUrl:(NSURL*)theUrl callback:(WSCacheDownloadBlock)theBlock;

@end


/**
 
 NSString *service = @"ceshiKeychain";
 id savedData = @[@(100),@(201),@"zfc"];
 [WSCache saveKeychainData:savedData service:service];
 NSLog(@"测试Keychain结果: 保存数据:%@ , service:%@ ",savedData,service);
 
 
 
 NSString *service = @"ceshiKeychain";
 id data = [WSCache getKeychainQuery:service];
 id data2 = [WSCache loadKeychainData:service];
 NSLog(@"测试Keychain结果: 读取数据 service:%@ , getKeychainQuery:%@ , loadKeychainData:%@ ",service,data,data2);
 
 */
@interface WSCache (keyChain)

+ (NSMutableDictionary *)getKeychainQuery:(NSString *)service;
+ (void)saveKeychainData:(id)data service:(NSString *)service;

+ (id)loadKeychainData:(NSString *)service;
+ (void)deleteKeychainData:(NSString *)service;

@end



