#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import "RichLinkBridge.h"

@interface REMObjectID : NSObject
+ (id)objectIDWithURL:(NSURL *)url;
@end

@interface REMStore : NSObject
- (id)fetchListWithObjectID:(id)objectID error:(NSError **)error;
@end

@interface REMList : NSObject
- (NSArray *)fetchRemindersWithError:(NSError **)error;
@end

@interface REMReminder : NSObject
- (NSString *)daCalendarItemUniqueIdentifier;
@end

@interface REMSaveRequest : NSObject
- (instancetype)initWithStore:(REMStore *)store;
- (id)updateReminder:(id)reminder;
- (BOOL)saveSynchronouslyWithError:(NSError **)error;
@end

@interface REMReminderChangeItem : NSObject
- (id)attachmentContext;
@end

@interface REMReminderAttachmentContextChangeItem : NSObject
- (id)addURLAttachmentWithURL:(NSURL *)url;
@end

static void copy_error(NSString *message, char *buffer, int bufferLength) {
    if (!buffer || bufferLength <= 0) return;

    const char *utf8 = message.UTF8String ?: "Unknown error";
    snprintf(buffer, bufferLength, "%s", utf8);
}

int add_rich_link_to_existing_reminder(
    const char *listIDCString,
    const char *externalIdentifierCString,
    const char *urlCString,
    char *errorBuffer,
    int errorBufferLength
) {
    @autoreleasepool {
        NSString *listID = [NSString stringWithUTF8String:listIDCString ?: ""];
        NSString *externalIdentifier =
            [NSString stringWithUTF8String:externalIdentifierCString ?: ""];
        NSString *urlString = [NSString stringWithUTF8String:urlCString ?: ""];

        if (listID.length == 0 || externalIdentifier.length == 0 || urlString.length == 0) {
            copy_error(@"Missing list, reminder identifier, or URL.", errorBuffer, errorBufferLength);
            return 1;
        }

        void *framework = dlopen(
            "/System/Library/PrivateFrameworks/ReminderKit.framework/ReminderKit",
            RTLD_NOW
        );

        if (!framework) {
            copy_error(@"ReminderKit could not be loaded.", errorBuffer, errorBufferLength);
            return 2;
        }

        Class objectIDClass = NSClassFromString(@"REMObjectID");
        Class storeClass = NSClassFromString(@"REMStore");
        Class saveRequestClass = NSClassFromString(@"REMSaveRequest");

        if (!objectIDClass || !storeClass || !saveRequestClass) {
            copy_error(@"Required ReminderKit classes are unavailable.", errorBuffer, errorBufferLength);
            return 3;
        }

        NSString *objectURLString = [NSString stringWithFormat:
            @"x-apple-reminderkit://REMCDList/%@",
            listID
        ];
        NSURL *objectURL = [NSURL URLWithString:objectURLString];

        if (!objectURL) {
            copy_error(@"Could not create ReminderKit list identifier.", errorBuffer, errorBufferLength);
            return 4;
        }

        id objectID = [objectIDClass objectIDWithURL:objectURL];
        id store = [storeClass new];
        NSError *error = nil;
        id list = [store fetchListWithObjectID:objectID error:&error];

        if (!list) {
            copy_error(
                error.localizedDescription ?: @"Reminder list not found.",
                errorBuffer,
                errorBufferLength
            );
            return 5;
        }

        error = nil;
        NSArray *reminders = [list fetchRemindersWithError:&error];

        if (!reminders) {
            copy_error(
                error.localizedDescription ?: @"Could not fetch reminders.",
                errorBuffer,
                errorBufferLength
            );
            return 6;
        }

        id existingReminder = nil;
        for (REMReminder *candidate in reminders) {
            NSString *candidateIdentifier = [candidate daCalendarItemUniqueIdentifier];
            if (candidateIdentifier && [candidateIdentifier isEqualToString:externalIdentifier]) {
                existingReminder = candidate;
                break;
            }
        }

        if (!existingReminder) {
            copy_error(
                @"Created reminder could not be matched by calendar identifier.",
                errorBuffer,
                errorBufferLength
            );
            return 6;
        }

        id saveRequest = [[saveRequestClass alloc] initWithStore:store];
        id changeItem = [saveRequest updateReminder:existingReminder];

        if (!changeItem) {
            copy_error(
                @"Could not create ReminderKit reminder update.",
                errorBuffer,
                errorBufferLength
            );
            return 7;
        }

        id attachmentContext = [changeItem attachmentContext];

        if (!attachmentContext) {
            copy_error(
                @"Could not create URL attachment context.",
                errorBuffer,
                errorBufferLength
            );
            return 8;
        }

        NSURL *website = [NSURL URLWithString:urlString];
        if (!website) {
            copy_error(@"Invalid source URL.", errorBuffer, errorBufferLength);
            return 9;
        }

        id attachment = [attachmentContext addURLAttachmentWithURL:website];
        if (!attachment) {
            copy_error(
                @"ReminderKit did not create the URL attachment.",
                errorBuffer,
                errorBufferLength
            );
            return 10;
        }

        error = nil;
        if (![saveRequest saveSynchronouslyWithError:&error]) {
            copy_error(
                error.localizedDescription ?: @"Could not save rich URL attachment.",
                errorBuffer,
                errorBufferLength
            );
            return 11;
        }

        return 0;
    }
}
