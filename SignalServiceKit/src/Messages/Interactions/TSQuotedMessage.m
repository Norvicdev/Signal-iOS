//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSQuotedMessage.h"
#import "TSAttachment.h"
#import "TSAttachmentStream.h"
#import <YapDatabase/YapDatabaseTransaction.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSAttachmentInfo

- (instancetype)initWithAttachment:(TSAttachment *)attachment
{
    OWSAssert(attachment.uniqueId);
    OWSAssert(attachment.contentType);

    return [self initWithAttachmentId:attachment.uniqueId
                          contentType:attachment.contentType
                       sourceFilename:attachment.sourceFilename];
}

- (instancetype)initWithAttachmentId:(nullable NSString *)attachmentId
                         contentType:(NSString *)contentType
                      sourceFilename:(NSString *)sourceFilename
{
    self = [super init];
    if (!self) {
        return self;
    }

    _attachmentId = attachmentId;
    _contentType = contentType;
    _sourceFilename = sourceFilename;

    return self;
}

@end

// View Model which has already fetched any thumbnail attachment.
@implementation OWSQuotedReplyModel

// This is a MIME type.
//
// This property should be set IFF we are quoting an attachment message.
- (nullable NSString *)contentType
{
    return self.attachmentStream.contentType;
}

- (nullable NSString *)sourceFilename
{
    return self.attachmentStream.sourceFilename;
}

- (nullable UIImage *)thumbnailImage
{
    return self.attachmentStream.thumbnailImage;
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         authorId:(NSString *)authorId
                             body:(NSString *_Nullable)body
                 attachmentStream:(nullable TSAttachmentStream *)attachmentStream
{
    self = [super init];
    if (!self) {
        return self;
    }

    _timestamp = timestamp;
    _authorId = authorId;
    _body = body;
    _attachmentStream = attachmentStream;

    return self;
}

- (instancetype)initWithQuotedMessage:(TSQuotedMessage *)quotedMessage
                          transaction:(YapDatabaseReadTransaction *)transaction
{
    TSAttachment *attachment =
        [TSAttachment fetchObjectWithUniqueID:quotedMessage.quotedAttachments.firstObject.attachmentId
                                  transaction:transaction];

    TSAttachmentStream *attachmentStream;
    if ([attachment isKindOfClass:[TSAttachmentStream class]]) {
        attachmentStream = (TSAttachmentStream *)attachment;
    }

    return [self initWithTimestamp:quotedMessage.timestamp
                          authorId:quotedMessage.authorId
                              body:quotedMessage.body
                  attachmentStream:attachmentStream];
}

- (TSQuotedMessage *)buildQuotedMessage
{
    NSArray *attachments = self.attachmentStream ? @[ self.attachmentStream ] : @[];

    return [[TSQuotedMessage alloc] initWithTimestamp:self.timestamp
                                             authorId:self.authorId
                                                 body:self.body
                          quotedAttachmentsForSending:attachments];
}

@end

@interface TSQuotedMessage ()

@property (atomic) NSArray<OWSAttachmentInfo *> *quotedAttachments;
@property (atomic) NSArray<TSAttachmentStream *> *quotedAttachmentsForSending;

@end

@implementation TSQuotedMessage

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         authorId:(NSString *)authorId
                             body:(NSString *_Nullable)body
            quotedAttachmentInfos:(NSArray<OWSAttachmentInfo *> *)attachmentInfos
{
    OWSAssert(timestamp > 0);
    OWSAssert(authorId.length > 0);

    self = [super init];
    if (!self) {
        return nil;
    }

    _timestamp = timestamp;
    _authorId = authorId;
    _body = body;
    _quotedAttachments = attachmentInfos;

    return self;
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         authorId:(NSString *)authorId
                             body:(NSString *_Nullable)body
      quotedAttachmentsForSending:(NSArray<TSAttachmentStream *> *)attachments
{
    OWSAssert(timestamp > 0);
    OWSAssert(authorId.length > 0);

    self = [super init];
    if (!self) {
        return nil;
    }

    _timestamp = timestamp;
    _authorId = authorId;
    _body = body;
    
    NSMutableArray *attachmentInfos = [NSMutableArray new];
    for (TSAttachment *attachment in attachments) {
        [attachmentInfos addObject:[[OWSAttachmentInfo alloc] initWithAttachment:attachment]];
    }
    _quotedAttachments = [attachmentInfos copy];

    return self;
}

#pragma mark - Attachment (not necessarily with a thumbnail)

- (nullable OWSAttachmentInfo *)firstAttachmentInfo
{
    return self.quotedAttachments.firstObject;
}

- (nullable NSString *)contentType
{
    OWSAttachmentInfo *firstAttachment = self.firstAttachmentInfo;

    return firstAttachment.contentType;
}

- (nullable NSString *)sourceFilename
{
    OWSAttachmentInfo *firstAttachment = self.firstAttachmentInfo;

    return firstAttachment.sourceFilename;
}

//- (NSArray<TSAttachment *> *)fetchThumbnailAttachmentsWithTransaction:(YapDatabaseReadTransaction *)transaction
//{
//    NSMutableArray<TSAttachment *> *attachments = [NSMutableArray new];
//
//    for (OWSAttachmentInfo *attachmentInfo in self.quotedAttachments) {
//        TSAttachment *attachment = [TSAttachment fetchObjectWithUniqueID:attachmentInfo.attachmentId
//        transaction:transaction];
//
//    }
//}

#pragma mark - Thumbnail

//- (nullable TSAttachment *)firstAttachmentWithTransaction:(YapDatabaseReadTransaction *)transaction
//{
//    OWSAttachmentInfo *attachmentInfo = self.firstAttachmentInfo;
//    if (!attachmentInfo) {
//        return nil;
//    }
//
//    return [TSAttachment fetchObjectWithUniqueID:attachmentInfo.attachmentId];
//}
//- (nullable UIImage *)thumbnailImageWithTransaction:(YapDatabaseReadTransaction *)transaction
//{
//    TSAttachmentStream *firstAttachment = (TSAttachmentStream *)self.firstAttachmentIn;
//    if (![firstAttachment isKindOfClass:[TSAttachmentStream class]]) {
//        return nil;
//    }
//
//    return firstAttachment.thumbnailImage;
//}
//- (BOOL)hasThumbnailAttachments
//{
//    return self.thumbnailAttachments.count > 0;
//}
//
//- (void)addThumbnailAttachment:(TSAttachmentStream *)attachment
//{
//    NSMutableArray<OWSAttachmentInfo *> *existingAttachments = [self.thumbnailAttachments mutableCopy];
//
//    OWSAttachmentInfo *attachmentInfo = [[OWSAttachmentInfo alloc] initWithAttachment:attachment];
//    [existingAttachments addObject:attachmentInfo];
//
//    self.thumbnailAttachments = [existingAttachments copy];
//}
//
//- (nullable OWSAttachmentInfo *)firstThumbnailAttachment
//{
//    return self.thumbnailAttachments.firstObject;
//}
//
//- (TSAttachmentStream *)thumbnailAttachmentWithTransaction:(YapDatabaseReadTransaction *)transaction
//{
//
//}
//
- (NSArray<TSAttachmentStream *> *)createThumbnailAttachmentsIfNecessaryWithTransaction:
    (YapDatabaseReadWriteTransaction *)transaction
{
    NSMutableArray<TSAttachmentStream *> *thumbnailAttachments = [NSMutableArray new];

    for (OWSAttachmentInfo *info in self.quotedAttachments) {

        OWSAssert(info.attachmentId);
        TSAttachment *attachment = [TSAttachment fetchObjectWithUniqueID:info.attachmentId transaction:transaction];
        if (![attachment isKindOfClass:[TSAttachmentStream class]]) {
            continue;
        }

        TSAttachmentStream *attachmentStream = (TSAttachmentStream *)attachment;
        NSData *thumbnailData = attachmentStream.thumbnailData;
        //  Only some media types have thumbnails
        if (thumbnailData) {
            // Copy the thumbnail to a new attachment.
            NSString *thumbnailName =
                [NSString stringWithFormat:@"quoted-thumbnail-%@", attachmentStream.sourceFilename];
            TSAttachmentStream *thumbnailAttachment =
                [[TSAttachmentStream alloc] initWithContentType:@"image/jpeg"
                                                      byteCount:attachmentStream.byteCount
                                                 sourceFilename:thumbnailName];

            NSError *error;
            [thumbnailAttachment writeData:thumbnailData error:&error];
            if (error) {
                DDLogError(@"%@ Couldn't copy attachment data for message sent to self: %@.", self.logTag, error);
            } else {
                [thumbnailAttachment saveWithTransaction:transaction];
                info.thumbnailAttachmentId = thumbnailAttachment.uniqueId;
                [thumbnailAttachments addObject:thumbnailAttachment];
            }
        }
    }

    if (thumbnailAttachments.count > 0) {
        // Save to record any self.quotedAttachments[].thumbnailAttachmentId
        [self saveWithTransaction:transaction];
    }

    return [thumbnailAttachments copy];
}
@end

NS_ASSUME_NONNULL_END
