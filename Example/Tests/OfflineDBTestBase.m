//
//  OfflineDBTestBase.m
//  AWSWrapper
//
//  Created by Stan Liu on 02/08/2017.
//  Copyright © 2017 lyc2345. All rights reserved.
//

#import "OfflineDBTestBase.h"

@interface OfflineDB (Test)

-(NSArray *)bookmarkDB;

-(NSArray *)historyDB;

-(BOOL)setBookmarkDB:(NSArray *)records;

-(BOOL)setHistoryDB:(NSArray *)records;

+(NSDictionary *)bookmarkShadow;

+(NSDictionary *)historyShadow;

+(BOOL)setBookmarkShadow:(NSDictionary *)records;

+(BOOL)setHistoryShadow:(NSDictionary *)records;

@end

@implementation OfflineDB (Test)

NSString * const __BOOKMARKS_LIST_TEST = @"__BOOKMARKS_LIST_TEST";
NSString * const __HISTORY_LIST_TEST = @"__HISTORY_LIST_TEST";
NSString * const __BOOKMARK_SHADOW_TEST = @"__BOOKMARK_SHADOW_TEST";
NSString * const __HISTORY_SHADOW_TEST = @"__HISTORY_SHADOW_TEST";


-(NSArray *)bookmarkDB {
  return [[NSUserDefaults standardUserDefaults] arrayForKey: __BOOKMARKS_LIST_TEST];
}

-(NSArray *)historyDB {
  return [[NSUserDefaults standardUserDefaults] arrayForKey: __HISTORY_LIST_TEST];
}

-(BOOL)setBookmarkDB:(NSArray *)records {
  [[NSUserDefaults standardUserDefaults] setObject: records forKey: __BOOKMARKS_LIST_TEST];
  return [[NSUserDefaults standardUserDefaults] synchronize];
}

-(BOOL)setHistoryDB:(NSArray *)records {
  [[NSUserDefaults standardUserDefaults] setObject: records forKey:  __HISTORY_LIST_TEST];
  return [[NSUserDefaults standardUserDefaults] synchronize];
}

+(NSDictionary *)bookmarkShadow {
  return [[NSUserDefaults standardUserDefaults] dictionaryForKey: __BOOKMARK_SHADOW_TEST];
}

+(NSDictionary *)historyShadow {
  return [[NSUserDefaults standardUserDefaults] dictionaryForKey: __HISTORY_SHADOW_TEST];
}

+(BOOL)setBookmarkShadow:(NSDictionary *)records {
  [[NSUserDefaults standardUserDefaults] setObject: records forKey: __BOOKMARK_SHADOW_TEST];
  return [[NSUserDefaults standardUserDefaults] synchronize];
}

+(BOOL)setHistoryShadow:(NSDictionary *)records {
  [[NSUserDefaults standardUserDefaults] setObject: records forKey:  __HISTORY_SHADOW_TEST];
  return [[NSUserDefaults standardUserDefaults] synchronize];
}


@end

@interface OfflineDBTestBase ()

@property OfflineDB *offlineDB;

@end

@implementation OfflineDBTestBase

- (instancetype)init
{
  self = [super init];
  if (self) {
  
    self.offlineDB = [OfflineDB new];
    
  }
  return self;
}

+(NSDictionary *)shadowIsBookmark:(BOOL)isBookmark {
  return [OfflineDB shadowIsBookmark: isBookmark];
}

+(BOOL)setShadow:(NSDictionary *)dict isBookmark:(BOOL)isBookmark {
  return [OfflineDB setShadow: dict isBookmark: isBookmark];
}

-(void)addOffline:(NSDictionary *)r type:(RecordType)type ofIdentity:(NSString *)identity {
  [self.offlineDB addOffline: r type: type ofIdentity: identity];
}

-(NSDictionary *)deleteOffline:(NSDictionary *)r type:(RecordType)type ofIdentity:(NSString *)identity {
  return [self.offlineDB deleteOffline: r type: type ofIdentity: identity];
}

-(NSDictionary *)getOfflineRecordOfIdentity:(NSString *)identity type:(RecordType)type {
  return [self.offlineDB getOfflineRecordOfIdentity: identity type: type];
}

@end
