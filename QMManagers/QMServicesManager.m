//
//  QBServiceManager.m
//  sample-chat
//
//  Created by Andrey Moskvin on 5/19/15.
//  Copyright (c) 2015 Igor Khomenko. All rights reserved.
//

#import "QMServicesManager.h"
#import "_CDMessage.h"

@interface QMServicesManager ()

@property (nonatomic, strong) QMAuthService* authService;
@property (nonatomic, strong) QMChatService* chatService;

@property (nonatomic, strong) dispatch_group_t logoutGroup;

@end

@implementation QMServicesManager

- (instancetype)init {
	self = [super init];
	if (self) {
		[QMChatCache setupDBWithStoreNamed:@"sample-cache"];
        [QMChatCache instance].messagesLimitPerDialog = 10;
		[QMContactListCache setupDBWithStoreNamed:@"sample-cache-contacts"];
		_authService = [[QMAuthService alloc] initWithServiceManager:self];
		_chatService = [[QMChatService alloc] initWithServiceManager:self cacheDataSource:self];
        [_chatService addDelegate:self];
        _logoutGroup = dispatch_group_create();
	}
	return self;
}

+ (instancetype)instance {
	static QMServicesManager* manager = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		manager = [[QMServicesManager alloc] init];
	});
	return manager;
}

- (void)logoutWithCompletion:(void(^)())completion
{
    if ([QBSession currentSession].currentUser != nil) {
        __weak typeof(self)weakSelf = self;    
        
        dispatch_group_enter(self.logoutGroup);
        [self.authService logOut:^(QBResponse *response) {
            __typeof(self) strongSelf = weakSelf;
            [strongSelf.chatService logoutChat];
            [strongSelf.chatService free];
            dispatch_group_leave(strongSelf.logoutGroup);
        }];
        
        dispatch_group_enter(self.logoutGroup);
        [[QMChatCache instance] deleteAllDialogs:^{
            __typeof(self) strongSelf = weakSelf;
            dispatch_group_leave(strongSelf.logoutGroup);
        }];
        
        dispatch_group_enter(self.logoutGroup);
        [[QMChatCache instance] deleteAllMessages:^{
            __typeof(self) strongSelf = weakSelf;
            dispatch_group_leave(strongSelf.logoutGroup);
        }];
        
        dispatch_group_notify(self.logoutGroup, dispatch_get_main_queue(), ^{
            if (completion) {
                completion();
            }
        });
    } else {
        if (completion) {
            completion();
        }
    }
}

- (void)logInWithUser:(QBUUser *)user
		   completion:(void (^)(BOOL success, NSString *errorMessage))completion
{
	[self.authService logInWithUser:user completion:^(QBResponse *response, QBUUser *userProfile) {
		if (response.error != nil) {
			if (completion != nil) {
				completion(NO, response.error.error.localizedDescription);
			}
			return;
		}
		
        __weak typeof(self) weakSelf = self;
		[self.chatService logIn:^(NSError *error) {
            __typeof(self) strongSelf = weakSelf;
			if (completion != nil) {
				completion(error == nil, error.localizedDescription);
			}
            NSArray* dialogs = [strongSelf.chatService.dialogsMemoryStorage unsortedDialogs];
            for (QBChatDialog* dialog in dialogs) {
                if (dialog.type != QBChatDialogTypePrivate) {
                    [strongSelf.chatService joinToGroupDialog:dialog failed:^(NSError *error) {
						if (error != nil) {
							NSLog(@"Join error: %@", error.localizedDescription);
						}
                    }];
                }
            }
		}];
	}];
}

- (void)handleErrorResponse:(QBResponse *)response {

}

- (BOOL)isAutorized {
	return self.authService.isAuthorized;
}

- (QBUUser *)currentUser {
	return [QBSession currentSession].currentUser;
}

#pragma mark QMChatServiceCache delegate

- (void)chatService:(QMChatService *)chatService didAddChatDialogToMemoryStorage:(QBChatDialog *)chatDialog {
	[QMChatCache.instance insertOrUpdateDialog:chatDialog completion:nil];
}

- (void)chatService:(QMChatService *)chatService didAddChatDialogsToMemoryStorage:(NSArray *)chatDialogs {
	[QMChatCache.instance insertOrUpdateDialogs:chatDialogs completion:nil];
}

- (void)chatService:(QMChatService *)chatService didUpdateChatDialogInMemoryStorage:(QBChatDialog *)chatDialog {
	[QMChatCache.instance insertOrUpdateDialog:chatDialog completion:nil];
}

- (void)chatService:(QMChatService *)chatService didAddMessageToMemoryStorage:(QBChatMessage *)message forDialogID:(NSString *)dialogID {
	[QMChatCache.instance insertOrUpdateMessage:message withDialogId:dialogID completion:nil];
}

- (void)chatService:(QMChatService *)chatService didAddMessagesToMemoryStorage:(NSArray *)messages forDialogID:(NSString *)dialogID {
	[QMChatCache.instance insertOrUpdateMessages:messages withDialogId:dialogID completion:nil];
}

- (void)chatService:(QMChatService *)chatService didUpdateMessage:(QBChatMessage *)message forDialogID:(NSString *)dialogID {
    [QMChatCache.instance insertOrUpdateMessage:message withDialogId:dialogID completion:nil];
}

- (void)chatService:(QMChatService *)chatService didDeleteChatDialogWithIDFromMemoryStorage:(NSString *)chatDialogID {
    [QMChatCache.instance deleteDialogWithID:chatDialogID completion:nil];
}

- (void)chatService:(QMChatService *)chatService  didReceiveNotificationMessage:(QBChatMessage *)message createDialog:(QBChatDialog *)dialog {
	NSAssert(message.dialogID == dialog.ID, @"must be equal");
	
	[QMChatCache.instance insertOrUpdateMessage:message withDialogId:dialog.ID completion:nil];
	[QMChatCache.instance insertOrUpdateDialog:dialog completion:nil];
}

#pragma mark QMChatServiceCacheDataSource

- (void)cachedDialogs:(QMCacheCollection)block {
	[QMChatCache.instance dialogsSortedBy:@"lastMessageDate" ascending:YES completion:^(NSArray *dialogs) {
		block(dialogs);
	}];
}

- (void)cachedMessagesWithDialogID:(NSString *)dialogID block:(QMCacheCollection)block {
	[QMChatCache.instance messagesWithDialogId:dialogID sortedBy:CDMessageAttributes.messageID ascending:YES completion:^(NSArray *array) {
		block(array);
	}];
}

#pragma mark QMContactListServiceCacheDelegate delegate

- (void)cachedUsers:(QMCacheCollection)block {
	[QMContactListCache.instance usersSortedBy:@"id" ascending:YES completion:^(NSArray *users) {
		block(users);
	}];
}

- (void)cachedContactListItems:(QMCacheCollection)block {
	[QMContactListCache.instance contactListItems:block];
}

@end
