
//
//  DynamoService.m
//
//  Created by Stan Liu on 16/03/2017.
//  Copyright © 2017 Stan Liu. All rights reserved.
//

#import "DynamoService.h"
#import "Bookmark.h"
#import "RecentVisit.h"
#import "DSWrapper.h"
#import "Random.h"

@interface DynamoService ()

@property (strong, nonatomic) OfflineDB *offlieDB;

@end

#pragma mark DynamoService (Bookmark&RecentlyVisit Format)

@implementation DynamoService

- (instancetype)init
{
  self = [super init];
  if (self) {
    self.offlieDB = [[OfflineDB alloc] init];
  }
  return self;
}

+(NSDictionary *)convert:(NSDictionary *)attributeDictionary {
  
  AWSDynamoDBAttributeValue *dictsValue = attributeDictionary[@"dicts"];
  AWSDynamoDBAttributeValue *remoteHash = attributeDictionary[@"remoteHash"];
  AWSDynamoDBAttributeValue *commitId = attributeDictionary[@"commitId"];
  AWSDynamoDBAttributeValue *userId = attributeDictionary[@"userId"];
  
  if (dictsValue == nil || remoteHash == nil || commitId == nil) {
    NSLog(@"Some of attribute is nil");
    return nil;
  }
  
  NSDictionary *dicts = dictsValue.M;
  NSMutableDictionary *pureDicts = [NSMutableDictionary dictionary];
  
  for (NSString *key in dicts.allKeys) {
    
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    AWSDynamoDBAttributeValue *infoValue = dicts[key];
    NSDictionary *comic = infoValue.M;
    AWSDynamoDBAttributeValue *authorValue = comic[@"author"];
    AWSDynamoDBAttributeValue *urlValue = comic[@"url"];
    
    [info setObject: authorValue.S forKey: @"author"];
    [info setObject: urlValue.S forKey: @"url"];
    [pureDicts setObject: info forKey: key];
  }
  
  NSMutableDictionary *record = [NSMutableDictionary dictionary];
  [record setObject: pureDicts forKey: @"_dicts"];
  [record setObject: remoteHash.S forKey: @"_remoteHash"];
  [record setObject: commitId.S forKey: @"_commitId"];
  [record setObject: userId.S forKey: @"_userId"];
  [record setObject: userId.S forKey: @"_id"];
  
  return record;
}

#pragma mark - Conditional Write Format

+(AWSDynamoDBAttributeValue *)AWSFormatFromDict:(NSDictionary *)dict {
	
	AWSDynamoDBAttributeValue *authorValue = [AWSDynamoDBAttributeValue new];
	authorValue.S = dict[@"author"];
	AWSDynamoDBAttributeValue *urlValue = [AWSDynamoDBAttributeValue new];
	urlValue.S = dict[@"url"];
	
	NSDictionary<NSString *, AWSDynamoDBAttributeValue *> *awsMapValue = @{@"author": authorValue, @"url": urlValue};
	
	AWSDynamoDBAttributeValue *mapValue = [AWSDynamoDBAttributeValue new];
	mapValue.M = awsMapValue;
	
	return mapValue;
}

@end


#pragma mark (AWS)

@implementation DynamoService (AWS)

-(void)pullType:(RecordType)type user:(NSString *)userId completion:(void(^)(NSDictionary *item, DSError *error))completionHandler {
  
  AWSDynamoDB *dynamoDB = [AWSDynamoDB defaultDynamoDB];
  AWSDynamoDBQueryInput *queryInput = [AWSDynamoDBQueryInput new];
  
  AWSDynamoDBAttributeValue *identityValue = [AWSDynamoDBAttributeValue new];
  identityValue.S = userId;
  
  queryInput.tableName =  type == RecordTypeBookmark ? [Bookmark dynamoDBTableName] : [RecentVisit dynamoDBTableName];
  queryInput.projectionExpression = @"userId, dicts, commitId, remoteHash";
  queryInput.keyConditionExpression = [NSString stringWithFormat: @"userId = :val"];
  queryInput.expressionAttributeValues = @{@":val": identityValue};
  
  [dynamoDB query: queryInput completionHandler:^(AWSDynamoDBQueryOutput * _Nullable response, NSError * _Nullable error) {
    
    if (error) {
      NSLog(@"AWS DynamoDB load error: %@", error);
      //completionHandler(nil, error);
      completionHandler(nil, [DSError pullFailed]);
      return;
    }
    NSLog(@"AWS DynamoDB load successfull");
    
    if (response.items != nil && response.items.count > 0) {
      
      NSDictionary *attributeDictionary = response.items.firstObject;
      NSDictionary *record = [DynamoService convert: attributeDictionary];
      completionHandler(record, nil);
      
    } else {
      completionHandler(nil, [DSError remoteDataNil]);
    }
  }];
}

-(void)pullClass:(Class)aClass withUser:(NSString *)userId  completion:(void(^)(NSArray *items, NSError *error))completionHandler {
	
	AWSDynamoDBObjectMapper *objectMapper = [AWSDynamoDBObjectMapper defaultDynamoDBObjectMapper];
	
	AWSDynamoDBQueryExpression *queryExpression = [AWSDynamoDBQueryExpression new];
	queryExpression.keyConditionExpression = @"#userId = :userId";
	queryExpression.expressionAttributeNames = @{@"#userId": @"userId"};
	queryExpression.expressionAttributeValues = @{
																								@":userId" : userId,
																								};
	[objectMapper query: aClass
					 expression: queryExpression
		completionHandler: ^(AWSDynamoDBPaginatedOutput * _Nullable response, NSError * _Nullable error) {
			
			if (error) {
				NSLog(@"AWS DynamoDB load error: %@", error);
				completionHandler(nil, error);
				return;
			}
			NSLog(@"AWS DynamoDB load successfull");
			completionHandler(response.items, nil);
		}];
}

-(void)forcePushWithObject:(id<RecordSuitable>)bkSuitable completion:(void(^)(NSError *error, NSDictionary *item))completion {
  
  AWSDynamoDBObjectMapper *objectMapper = [AWSDynamoDBObjectMapper defaultDynamoDBObjectMapper];
  
  bkSuitable._commitId = [Random string];
  [objectMapper save: (AWSDynamoDBObjectModel<AWSDynamoDBModeling> *)bkSuitable completionHandler:^(NSError * _Nullable error) {
    
    if (error) {
      NSLog(@"AWS DynamoDB save error: %@", error);
      completion(error, nil);
      return;
    }
    NSLog(@"AWS DynamoDB save successful");
    RecordType type = [bkSuitable isKindOfClass: [Bookmark class]] ? RecordTypeBookmark : RecordTypeRecentlyVisit;
    NSMutableDictionary *record = [NSMutableDictionary dictionary];
    [record setObject: bkSuitable._commitId forKey: @"_commitId"];
    [record setObject: bkSuitable._remoteHash forKey: @"_remoteHash"];
    [record setObject: bkSuitable._id forKey: @"_id"];
    [record setObject: bkSuitable._userId forKey: @"_userId"];
    [record setObject: bkSuitable._dicts forKey: @"_dicts"];
    BOOL success = [self.offlieDB pushSuccessThenSaveLocalRecord: record type: type newCommitId: bkSuitable._commitId];
    success == YES ? completion(nil, record) : completion;
  }];
}


-(void)forcePushWithType:(RecordType)type
                  record:(NSDictionary *)record
                  userId:(NSString *)userId
              completion:(void(^)(NSError *error, NSString *commitId, NSString *remoteHash))completion {
	
  NSString *commitId = [Random string];
  NSString *remoteHash = [Random string];
  
  AWSDynamoDB *dynamoDB = [AWSDynamoDB defaultDynamoDB];
  AWSDynamoDBPutItemInput *putItemInput = [AWSDynamoDBPutItemInput new];
  
  AWSDynamoDBAttributeValue *identityValue = [AWSDynamoDBAttributeValue new];
  // Identity is the key for offline record
  identityValue.S = userId;
  
  if (type == RecordTypeBookmark) {
    
    putItemInput.tableName = [Bookmark dynamoDBTableName];
  } else {
    putItemInput.tableName = [RecentVisit dynamoDBTableName];
  }
  
  // commit id
  AWSDynamoDBAttributeValue *newCommitIdValue = [AWSDynamoDBAttributeValue new];
  newCommitIdValue.S = commitId;
  
  AWSDynamoDBAttributeValue *remoteHashValue = [AWSDynamoDBAttributeValue new];
  remoteHashValue.S = remoteHash;
  
  NSArray *addList = [DSWrapper arrayFromDict: record[@"_dicts"]];
  
  // attributeValues
  NSMutableDictionary *attributeValues = [NSMutableDictionary dictionary];
  [addList enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
    
    NSString *additionAttributeValueKey = [NSString stringWithFormat: @"%@", obj[@"comicName"]];
    
    [attributeValues setObject: [DynamoService AWSFormatFromDict: obj] forKey: additionAttributeValueKey];
  }];
  
  AWSDynamoDBAttributeValue *dictsValue = [AWSDynamoDBAttributeValue new];
  dictsValue.M = attributeValues;
  
  putItemInput.item = @{@"userId": identityValue,
                        @"id": identityValue,
                        @"commitId": newCommitIdValue,
                        @"remoteHash": remoteHashValue,
                        @"dicts": dictsValue
                        };
  
  putItemInput.returnValues = AWSDynamoDBReturnValueAllOld;
  
  [[dynamoDB putItem: putItemInput] continueWithBlock:^id(AWSTask *task) {
    
    if (task.error) {
      NSLog(@"force push error: %@", task.error);
      completion(task.error, nil, nil);
      return nil;
    } else {
      AWSDynamoDBUpdateItemOutput *result = task.result;
      NSDictionary *resultValue = result.dictionaryValue;
      NSDictionary *pureResult = [DynamoService convert: resultValue[@"attributes"]];
      completion(task.error, commitId, remoteHash);
    }
    return nil;
  }];
}

-(void)mergePushType:(RecordType)type userId:(NSString *)userId completion:(void(^)(NSDictionary *responseItem, DSError *error))mergeCompletion {
	
  // Diff local and shadow first, should know the modifies.
  NSDictionary *local = [[OfflineDB new] getOfflineRecordOfIdentity: userId type: type];
	__block NSDictionary *diff_client_shadow = [DSWrapper diffShadowAndClient: local[@"_dicts"] isBookmark: type == RecordTypeBookmark];
  
  NSLog(@"start: 1");
  // push local AWS model and the diff we get before.
  [self pushWithObject: local type: type diff: diff_client_shadow userId: userId completion:^(NSDictionary *responseItem, NSError *error, NSString *commitId) {
    
    NSLog(@"done 1");
		if (!error) {
			// expected commit id meet localBookmarkRecord commit id
			// successed!
			NSLog(@"push success by merge push at the first place");
			//NSLog(@"first push success with object: %@", response);
			[self.offlieDB pushSuccessThenSaveLocalRecord: local type: type newCommitId: commitId];
			
			mergeCompletion(responseItem, nil);
			return;
			
		} else {
			NSLog(@"first conditional write error: %@", error);
			
			NSLog(@"starting pull...");
			NSLog(@"start 2");
      [self pullType: type user: userId completion:^(NSDictionary *item, DSError *error) {

				NSLog(@"done 2");
				if (error && (error && error.code != 4)) {
          
          NSLog(@"DynamoService pulling error: %@", error);
            // com.DynamoService.pullError
            mergeCompletion(nil, error);
					return;
					
				} else {
          
          NSLog(@"pulling Success");
          NSMutableDictionary *cloud = [item mutableCopy];
					
					NSLog(@"start 3");
					if (!cloud) {
						NSLog(@"remote is empty, push...");
            [self forcePushWithType: type record: local userId: userId completion:^(NSError *error, NSString *commitId, NSString *remoteHash) {
              
              NSLog(@"done 3");
							if (!error) {
                NSLog(@"FORCE push success with reocrd: %@", local);
                [self.offlieDB pushSuccessThenSaveLocalRecord: local type: type newCommitId: commitId];
                mergeCompletion(item, nil);
                return;
              }
							mergeCompletion(item, [DSError forcePushFailed]);
						}];
					} else {
						
						NSLog(@"done 3");
						NSLog(@"remote version: %@, local version: %@", cloud[@"_remoteHash"], local[@"_remoteHash"]);
						NSLog(@"remote timestamp: %@, local timestamp: %@", cloud[@"_commitId"], local[@"_commitId"]);
            
            NSMutableDictionary *new = [NSMutableDictionary dictionary];
            
            [new setObject: cloud[@"_id"] forKey: @"_id"];
            [new setObject: cloud[@"_userId"] forKey: @"_userId"];
            [new setObject: cloud[@"_commitId"] forKey: @"_commitId"];
            [new setObject: cloud[@"_remoteHash"] forKey: @"_remoteHash"];
            [new setObject: cloud[@"_dicts"] forKey: @"_dicts"];
            
            NSLog(@"start 4: check remote Hash");
            // remote Hash is nil
            if (!cloud[@"_remoteHash"]) {
              
              [new setObject: [Random string] forKey: @"_commidId"];
              [new setObject: [Random string] forKey: @"_remoteHash"];
              
              NSLog(@"RemoteHash is nil, force push whole local record");
              [self forcePushWithType: type record: cloud userId: userId completion:^(NSError *error, NSString *commitId, NSString *remoteHash) {
                
                if (!error) {
                  NSLog(@"5: Done by force push");
                  
                  [self.offlieDB pushSuccessThenSaveLocalRecord: [new copy] type: type newCommitId: commitId];
                  mergeCompletion(item, nil);
                } else {
                  mergeCompletion(nil, [DSError forcePushFailed]);
                }
              }];
              return;
            } else if (![cloud[@"_remoteHash"] isEqualToString: local[@"_remoteHash"]]) {
              
              NSLog(@"RemoteHash is changed, Now empty shadow...");
              [OfflineDB setShadow: @{} isBookmark: type == RecordTypeBookmark];
              // diff client shadow again. becasue shadow is empty.
              diff_client_shadow = [DSWrapper diffShadowAndClient: local[@"_dicts"] isBookmark: type == RecordTypeBookmark];
              NSLog(@"Get a new diff from client and empty shadow");
            }
            NSLog(@"done 4");
            
						NSLog(@"starting diffmerge...");
						NSLog(@"start 4-1: diffmerge");
            // MARK: conflict use remote directly.
            NSDictionary *newClientDicts = cloud[@"_dicts"];
            NSLog(@"done 4-1");
            NSLog(@"start 5");
            
            NSLog(@"conditional push whole local record");
            newClientDicts = [DSWrapper mergeInto: newClientDicts applyDiff: diff_client_shadow];
            NSDictionary *need_to_apply_to_remote = [DSWrapper diffWins: newClientDicts loses: cloud[@"_dicts"]];
            
            [self pushWithObject: new type: type diff: need_to_apply_to_remote userId: userId completion:^(NSDictionary *responseItem, NSError *error, NSString *commitId) {
              
              if (error) {
                NSLog(@"conditional push error: %@", error);
                NSLog(@"fuckkkkkkkkkkkkkkkk erorrrrrrrrr");
                mergeCompletion(nil, [DSError mergePushFailed]);
                return;
              }
              NSLog(@"push success after diffmerge");
              NSLog(@"5: Done by conditonal update");
              
              [new setObject: newClientDicts forKey: @"_dicts"];
              
              [self.offlieDB pushSuccessThenSaveLocalRecord: new type: type newCommitId: commitId];
              mergeCompletion(responseItem, nil);
            }];
          }
				}
			}];
		}
	}];
}

-(void)pushWithObject:(NSDictionary *)record type:(RecordType)type diff:(NSDictionary *)diff userId:(NSString *)userId completion:(void(^)(NSDictionary *responseItem, NSError *error, NSString *commitId))completion {
  
  if (!diff) {
    completion(nil, nil, nil);
    return;
  }
	
	NSString *commitId = [Random string];
	NSString *remoteHash = record[@"_remoteHash"] != nil ? record[@"_remoteHash"] : [Random string];
	
	AWSDynamoDB *dynamoDB = [AWSDynamoDB defaultDynamoDB];
	AWSDynamoDBUpdateItemInput *updateInput = [AWSDynamoDBUpdateItemInput new];
	
	AWSDynamoDBAttributeValue *identityValue = [AWSDynamoDBAttributeValue new];
  // Identity is the key for offline record
  identityValue.S = userId;
	
	if (type == RecordTypeBookmark) {
		
		updateInput.tableName = [Bookmark dynamoDBTableName];
	} else {
		updateInput.tableName = [RecentVisit dynamoDBTableName];
	}
	
	updateInput.key = @{ @"userId": identityValue, @"id": identityValue };
	
	// commit id
	AWSDynamoDBAttributeValue *oldCommitIdValue = [AWSDynamoDBAttributeValue new];
	oldCommitIdValue.S = record[@"_commitId"];
	
	AWSDynamoDBAttributeValue *newCommitIdValue = [AWSDynamoDBAttributeValue new];
	newCommitIdValue.S = commitId;
	
	AWSDynamoDBAttributeValue *remoteHashValue = [AWSDynamoDBAttributeValue new];
	remoteHashValue.S = remoteHash;
	
	NSArray *addList = diff[@"_add"];
	NSArray *delList = diff[@"_delete"];
  NSArray *replaceList = diff[@"_replace"];
	
	// attributeValues
	NSMutableDictionary *attributeValues = [NSMutableDictionary dictionary];
	// attributeNames
	NSMutableDictionary *attributeNames = [NSMutableDictionary dictionary];
	
	NSMutableString *addString = [NSMutableString string];
  
  // Copy a delMutableList from delList
  __block NSMutableArray *waitTobeDelList = [NSMutableArray array];
  if (replaceList && replaceList.count > 0) {
    
    [replaceList enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
      
      if([obj[@"comicName"] isEqualToString: @""]) {
        return;
      }
      
      NSString *additionAttributeValueKey = [NSString stringWithFormat: @":%@", obj[@"comicName"]];
      NSString *additionAttributeNameKey = [NSString stringWithFormat: @"#%@", obj[@"comicName"]];
      
      [attributeValues setObject: [DynamoService AWSFormatFromDict: obj] forKey: additionAttributeValueKey];
      [attributeNames setObject: obj[@"comicName"] forKey: additionAttributeNameKey];
      
      NSString *key = [NSString stringWithFormat: @", #dicts.%@ = %@", additionAttributeNameKey, additionAttributeValueKey];
      [addString appendString: key];
      
      [delList enumerateObjectsUsingBlock:^(id  _Nonnull delObj, NSUInteger delIdx, BOOL * _Nonnull stop) {
        
        *stop = NO;
        if ([delObj[@"comicName"] isEqualToString: obj[@"comicName"]]) {
          *stop = YES;
        }
        if (stop) {
          [waitTobeDelList addObject: delObj];
        }
      }];
    }];
  } else {
    
    [addList enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
      
      if([obj[@"comicName"] isEqualToString: @""]) {
        return;
      }
      
      NSString *additionAttributeValueKey = [NSString stringWithFormat: @":%@", obj[@"comicName"]];
      NSString *additionAttributeNameKey = [NSString stringWithFormat: @"#%@", obj[@"comicName"]];
      
      [attributeValues setObject: [DynamoService AWSFormatFromDict: obj] forKey: additionAttributeValueKey];
      [attributeNames setObject: obj[@"comicName"] forKey: additionAttributeNameKey];
      
      NSString *key = [NSString stringWithFormat: @", #dicts.%@ = %@", additionAttributeNameKey, additionAttributeValueKey];
      [addString appendString: key];
      
      [delList enumerateObjectsUsingBlock:^(id  _Nonnull delObj, NSUInteger delIdx, BOOL * _Nonnull stop) {
        
        if ([delObj[@"comicName"] isEqualToString: obj[@"comicName"]]) {
          [waitTobeDelList addObject: delObj];
        }
      }];
    }];
  }
  NSMutableArray *delMutableList;
  if (delList && delList.count > 0) {
    delMutableList = [delList mutableCopy];
    [delMutableList removeObjectsInArray: waitTobeDelList];
    delList = [delMutableList copy];
  }
	NSMutableString *delString = [NSMutableString string];
	[delList enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
		
		NSString *key;
		if (delList.count - 1 == idx) {
			key = [NSString stringWithFormat: @"dicts.%@", obj[@"comicName"]];
		} else {
			key = [NSString stringWithFormat: @"dicts.%@, ", obj[@"comicName"]];
		}
		[delString appendString: key];
	}];
	
	[attributeValues setObject: newCommitIdValue forKey: @":nci"];
	if (oldCommitIdValue.S) {
		[attributeValues setObject: oldCommitIdValue forKey: @":oci"];
	}
	[attributeValues setObject: remoteHashValue forKey: @":exprh"];
	updateInput.expressionAttributeValues = attributeValues;
	
	NSMutableString *updateExpressionString = [NSMutableString string];
	// first append commit id everytime.
	[updateExpressionString appendString: @"SET #commitId = :nci"];
	[attributeNames setObject: @"commitId" forKey: @"#commitId"];
	
	// second append the expression if needed
	if (!addString || ![addString isEqualToString: @""]) {
		
		[attributeNames setObject: @"dicts" forKey: @"#dicts"];
		[updateExpressionString appendString: addString];
		
	}
  if (!delString || ![delString isEqualToString: @""]) {

		[updateExpressionString appendString: [NSString stringWithFormat: @" REMOVE %@", delString]];
	}
	
	updateInput.expressionAttributeNames = attributeNames;
	updateInput.updateExpression		= updateExpressionString;
	
	NSMutableString *conditionString = [NSMutableString string];
	// condition append commit id for define which device commit
	if (oldCommitIdValue.S) {
		[conditionString appendString: @"commitId = :oci and "];
	}
	// condition append commit id for define server is reset or not
	[conditionString appendString: @"remoteHash = :exprh "];
	
	[addList enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
		
    if([obj[@"comicName"] isEqualToString: @""]) {
      return;
    }
		[conditionString appendString: [NSString stringWithFormat: @"and attribute_not_exists(dict.#%@) ", obj[@"comicName"]]];
	}];
	
	updateInput.conditionExpression = conditionString;
	
	updateInput.returnValues = AWSDynamoDBReturnValueAllNew;
	
	[[dynamoDB updateItem: updateInput] continueWithBlock:^id(AWSTask *task) {
    
    if (task.error) {
      completion(nil, task.error, commitId);
      return nil;
    } else {
      AWSDynamoDBUpdateItemOutput *result = task.result;
      NSDictionary *resultValue = result.dictionaryValue;
      NSDictionary *pureResult = [DynamoService convert: resultValue[@"attributes"]];
      completion(pureResult, task.error, commitId);
    }
    return nil;
	}];
}

@end