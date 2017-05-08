/* Copyright 2017 Urban Airship and Contributors */

#import "UARCTEventEmitter.h"
#import "AirshipLib.h"

@interface UARCTEventEmitter()
@property(nonatomic, strong) NSMutableArray *pendingEvents;
@property(atomic, assign) NSInteger listenerCount;
@property(readonly) BOOL isObserving;
@end

NSString *const UARCTRegistrationEvent = @"com.urbanairship.registration";
NSString *const UARCTNotificationResponseEvent = @"com.urbanairship.notification_response";
NSString *const UARCTPushReceivedEvent= @"com.urbanairship.push_received";


@implementation UARCTEventEmitter

static UARCTEventEmitter *sharedEventEmitter_;


+ (void)load {
    sharedEventEmitter_ = [[UARCTEventEmitter alloc] init];
}

+ (UARCTEventEmitter *)shared {
    return sharedEventEmitter_;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.pendingEvents = [NSMutableArray array];
    }

    return self;
}

- (BOOL)sendEventWithName:(NSString *)eventName body:(id)body {
    if (self.bridge && self.isObserving) {
        [self.bridge enqueueJSCall:@"RCTDeviceEventEmitter"
                            method:@"emit"
                              args:body ? @[eventName, body] : @[eventName]
                        completion:NULL];

        return YES;
    }

    return NO;
}

- (void)addListener:(NSString *)eventName {
    self.listenerCount++;
    if (self.listenerCount > 0) {
        for (NSDictionary *event in self.pendingEvents) {
            [self sendEventWithName:event[@"name"] body:event[@"body"]];
        }

        [self.pendingEvents removeAllObjects];
    }
}

- (void)removeListeners:(NSInteger)count {
    self.listenerCount = MAX(self.listenerCount - count, 0);
}

- (BOOL)isObserving {
    return self.listenerCount > 0;
}

#pragma mark -
#pragma mark UAPushDelegate

-(void)receivedForegroundNotification:(UANotificationContent *)notificationContent completionHandler:(void (^)())completionHandler {
    [self sendEventWithName:UARCTPushReceivedEvent body:[self eventBodyForNotificationContent:notificationContent]];
    completionHandler();
}


-(void)receivedBackgroundNotification:(UANotificationContent *)notificationContent completionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
    [self sendEventWithName:UARCTPushReceivedEvent body:[self eventBodyForNotificationContent:notificationContent]];
    completionHandler(UIBackgroundFetchResultNoData);
}

-(void)receivedNotificationResponse:(UANotificationResponse *)notificationResponse completionHandler:(void (^)())completionHandler {
    // Ignore dismisses for now
    if ([notificationResponse.actionIdentifier isEqualToString:UANotificationDismissActionIdentifier]) {
        completionHandler();
        return;
    }

    NSDictionary *body = [self eventBodyForNotificationResponse:notificationResponse];

    if (![self sendEventWithName:UARCTNotificationResponseEvent body:body]) {
        [self.pendingEvents addObject:@{ @"name": UARCTNotificationResponseEvent, @"body": body }];
    }

    completionHandler();
}


#pragma mark -
#pragma mark UARegistrationDelegate

- (void)registrationSucceededForChannelID:(NSString *)channelID deviceToken:(NSString *)deviceToken {
    NSMutableDictionary *registrationBody = [NSMutableDictionary dictionary];
    [registrationBody setValue:channelID forKey:@"channel"];
    [registrationBody setValue:deviceToken forKey:@"registrationToken"];
    [self sendEventWithName:UARCTRegistrationEvent body:registrationBody];
}

#pragma mark -
#pragma mark Helper methods


- (NSMutableDictionary *)eventBodyForNotificationResponse:(UANotificationResponse *)notificationResponse {
    NSMutableDictionary *body = [self eventBodyForNotificationContent:notificationResponse.notificationContent];


    if ([notificationResponse.actionIdentifier isEqualToString:UANotificationDefaultActionIdentifier]) {
        [body setValue:@(YES) forKey:@"isForeground"];
    } else {
        [body setValue:notificationResponse.actionIdentifier forKey:@"actionId"];


        UANotificationAction *notificationAction = [self notificationActionForCategory:notificationResponse.notificationContent.categoryIdentifier
                                                                      actionIdentifier:notificationResponse.actionIdentifier];

        BOOL isForeground = notificationAction.options & UNNotificationActionOptionForeground;
        [body setValue:@(isForeground) forKey:@"isForeground"];
    }

    return body;
}

- (NSMutableDictionary *)eventBodyForNotificationContent:(UANotificationContent *)content {
    NSMutableDictionary *pushBody = [NSMutableDictionary dictionary];
    [pushBody setValue:content.alertBody forKey:@"alert"];
    [pushBody setValue:content.alertTitle forKey:@"title"];


    // remove extraneous key/value pairs
    NSMutableDictionary *extras = [NSMutableDictionary dictionaryWithDictionary:content.notificationInfo];

    if([[extras allKeys] containsObject:@"aps"]) {
        [extras removeObjectForKey:@"aps"];
    }

    if([[extras allKeys] containsObject:@"_"]) {
        [extras removeObjectForKey:@"_"];
    }

    if (extras.count) {
        [pushBody setValue:extras forKey:@"extras"];
    }

    return pushBody;
}

- (UANotificationAction *)notificationActionForCategory:(NSString *)category actionIdentifier:(NSString *)identifier {
    NSSet *categories = [UAirship push].combinedCategories;

    UANotificationCategory *notificationCategory;
    UANotificationAction *notificationAction;

    for (UANotificationCategory *possibleCategory in categories) {
        if ([possibleCategory.identifier isEqualToString:category]) {
            notificationCategory = possibleCategory;
            break;
        }
    }

    if (!notificationCategory) {
        UA_LERR(@"Unknown notification category identifier %@", category);
        return nil;
    }

    NSMutableArray *possibleActions = [NSMutableArray arrayWithArray:notificationCategory.actions];

    for (UANotificationAction *possibleAction in possibleActions) {
        if ([possibleAction.identifier isEqualToString:identifier]) {
            notificationAction = possibleAction;
            break;
        }
    }

    if (!notificationAction) {
        UA_LERR(@"Unknown notification action identifier %@", identifier);
        return nil;
    }
    
    return notificationAction;
}

@end