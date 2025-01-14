//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SDSAnyReadTransaction;
@class SDSAnyWriteTransaction;
@class SignedPreKeyRecord;

typedef NS_ENUM(uint8_t, OWSIdentity);

@interface SSKSignedPreKeyStore : NSObject

- (instancetype)initForIdentity:(OWSIdentity)identity;

#pragma mark - SignedPreKeyStore transactions

- (nullable SignedPreKeyRecord *)loadSignedPreKey:(int)signedPreKeyId transaction:(SDSAnyReadTransaction *)transaction;

- (NSArray<SignedPreKeyRecord *> *)loadSignedPreKeysWithTransaction:(SDSAnyReadTransaction *)transaction;

- (void)storeSignedPreKey:(int)signedPreKeyId
       signedPreKeyRecord:(SignedPreKeyRecord *)signedPreKeyRecord
              transaction:(SDSAnyWriteTransaction *)transaction;

- (BOOL)containsSignedPreKey:(int)signedPreKeyId transaction:(SDSAnyReadTransaction *)transaction;

- (void)removeSignedPreKey:(int)signedPreKeyId transaction:(SDSAnyWriteTransaction *)transaction;

#pragma mark -

- (SignedPreKeyRecord *)generateRandomSignedRecord;

// Returns nil if no current signed prekey id is found.
- (nullable NSNumber *)currentSignedPrekeyId;
- (void)setCurrentSignedPrekeyId:(int)value;
- (nullable SignedPreKeyRecord *)currentSignedPreKey;

#pragma mark - Prekey update failures

- (int)prekeyUpdateFailureCount;
- (void)clearPrekeyUpdateFailureCount;
- (NSInteger)incrementPrekeyUpdateFailureCount;

- (nullable NSDate *)firstPrekeyUpdateFailureDate;
- (void)setFirstPrekeyUpdateFailureDate:(nonnull NSDate *)value;
- (void)clearFirstPrekeyUpdateFailureDate;

#pragma mark - Debugging

- (void)logSignedPreKeyReport;

#if TESTABLE_BUILD
- (void)removeAll:(SDSAnyWriteTransaction *)transaction;
#endif

@end

NS_ASSUME_NONNULL_END
