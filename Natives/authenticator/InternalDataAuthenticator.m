#import "BaseAuthenticator.h"
#import "MinecraftResourceUtils.h"
#import "ios_uikit_bridge.h"

@interface InternalDataAuthenticator : BaseAuthenticator
@end

@implementation InternalDataAuthenticator

- (void)loginWithCallback:(void (^)(BOOL success))callback {
    self.authData = [NSMutableDictionary new];
    self.authData[@"username"] = @"InternalData";
    self.authData[@"profileId"] = @"00000000-0000-0000-0000-000000000000";
    self.authData[@"accessToken"] = @"internal_data_token";
    self.authData[@"accountType"] = @"InternalData";
    callback(YES);
}

- (void)refreshTokenWithCallback:(void (^)(BOOL success))callback {
    callback(YES);
}

+ (NSString *)localizedTitle {
    return @"Internal Data Download";
}

@end
