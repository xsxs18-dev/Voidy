#import "../app/Sources/AppMetadataBridge.m"
#include <assert.h>

@interface FakeProxy : NSObject
@property(nonatomic, copy) NSString *identifier;
@end
@implementation FakeProxy
+ (id)applicationProxyForIdentifier:(NSString *)identifier {
    if ([identifier isEqualToString:@"missing"]) return nil;
    if ([identifier isEqualToString:@"throw-proxy"])
        [NSException raise:NSInvalidArgumentException format:@"unavailable app"];
    FakeProxy *proxy = [self new];
    proxy.identifier = identifier;
    return proxy;
}
- (id)localizedName {
    if ([self.identifier isEqualToString:@"throw-name"])
        [NSException raise:NSUndefinedKeyException format:@"unavailable name"];
    if ([self.identifier isEqualToString:@"wrong-type"]) return @123;
    if ([self.identifier isEqualToString:@"empty"]) return @"";
    return [NSString stringWithFormat:@"Name: %@", self.identifier];
}
@end

@interface FakeIcon32 : NSObject @end
@implementation FakeIcon32
+ (id)_applicationIconImageForBundleIdentifier:(NSString *)identifier format:(int)format scale:(float)scale {
    assert(format == 2 && scale == 2.0f);
    if ([identifier isEqualToString:@"throw"])
        [NSException raise:NSInternalInconsistencyException format:@"icon services unavailable"];
    if ([identifier isEqualToString:@"missing"]) return nil;
    if ([identifier isEqualToString:@"wrong-type"]) return @"not an image";
    return [self new];
}
@end

@interface FakeIcon64 : NSObject @end
@implementation FakeIcon64
+ (id)_applicationIconImageForBundleIdentifier:(NSString *)identifier format:(NSInteger)format scale:(double)scale {
    assert(format == 2 && scale == 3.0);
    return [self new];
}
@end

@interface IncompatibleIcon : NSObject @end
@implementation IncompatibleIcon
+ (id)_applicationIconImageForBundleIdentifier:(NSString *)identifier format:(id)format scale:(double)scale {
    assert(false); // unsupported ABI must not be invoked
    return nil;
}
@end

@interface IncompatibleProxy : NSObject @end
@implementation IncompatibleProxy
+ (NSInteger)applicationProxyForIdentifier:(NSString *)identifier {
    assert(false);
    return 0;
}
@end

int main(void) {
    @autoreleasepool {
        assert(ReadDisplayName(Nil, @"app") == nil);
        assert(ReadDisplayName(NSObject.class, @"app") == nil);
        assert(ReadDisplayName(FakeProxy.class, @"") == nil);
        for (NSString *identifier in @[@"missing", @"throw-proxy", @"throw-name", @"wrong-type", @"empty"])
            assert(ReadDisplayName(FakeProxy.class, identifier) == nil);
        assert(ReadDisplayName(IncompatibleProxy.class, @"app") == nil);
        assert(ReadIcon(Nil, @"app", 2) == nil);
        assert(ReadIcon(NSObject.class, @"app", 2) == nil);
        assert(ReadIcon(FakeIcon32.class, @"", 2) == nil);
        for (NSString *identifier in @[@"missing", @"throw", @"wrong-type"])
            assert(ReadIcon(FakeIcon32.class, identifier, 2) == nil);
        assert(ReadIcon(IncompatibleIcon.class, @"app", 2) == nil);
        for (int i = 0; i < 1000; i++) {
            NSString *name;
            NSObject *icon32, *icon64;
            @autoreleasepool {
                name = ReadDisplayName(FakeProxy.class, @"Example");
                icon32 = ReadIcon(FakeIcon32.class, @"app", 2);
                icon64 = ReadIcon(FakeIcon64.class, @"app", 3);
            }
            assert([name isEqualToString:@"Name: Example"]);
            assert([icon32 isKindOfClass:FakeIcon32.class]);
            assert([icon64 isKindOfClass:FakeIcon64.class]);
        }
        puts("App metadata: exceptions, missing apps, runtime signatures and object lifetimes passed.");
    }
    return 0;
}
