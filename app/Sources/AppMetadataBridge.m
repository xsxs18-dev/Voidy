#import "AppMetadataBridge.h"

static BOOL ObjectArgument(NSMethodSignature *signature, NSUInteger index) {
    return index < signature.numberOfArguments && [signature getArgumentTypeAtIndex:index][0] == '@';
}

static id ObjectResult(NSInvocation *invocation) {
    // NSInvocation does not retain object return values. Promote immediately
    // to an ARC-managed reference while the callee's autorelease pool is alive.
    __unsafe_unretained id value = nil;
    [invocation getReturnValue:&value];
    return value;
}

static NSString *ReadDisplayName(Class proxyClass, NSString *bundleID) {
    @try {
        SEL selector = NSSelectorFromString(@"applicationProxyForIdentifier:");
        if (!bundleID.length || ![proxyClass respondsToSelector:selector]) return nil;
        NSMethodSignature *signature = [proxyClass methodSignatureForSelector:selector];
        if (signature.numberOfArguments != 3 || signature.methodReturnType[0] != '@' || !ObjectArgument(signature, 2)) return nil;
        NSInvocation *call = [NSInvocation invocationWithMethodSignature:signature];
        call.target = proxyClass;
        call.selector = selector;
        [call setArgument:&bundleID atIndex:2];
        [call invoke];
        id proxy = ObjectResult(call);
        SEL nameSelector = NSSelectorFromString(@"localizedName");
        if (![proxy respondsToSelector:nameSelector]) return nil;
        NSMethodSignature *nameSignature = [proxy methodSignatureForSelector:nameSelector];
        if (nameSignature.numberOfArguments != 2 || nameSignature.methodReturnType[0] != '@') return nil;
        NSInvocation *nameCall = [NSInvocation invocationWithMethodSignature:nameSignature];
        nameCall.target = proxy;
        nameCall.selector = nameSelector;
        [nameCall invoke];
        id name = ObjectResult(nameCall);
        return [name isKindOfClass:NSString.class] && [name length] ? name : nil;
    } @catch (NSException *exception) {
        return nil;
    }
}

static NSObject *ReadIcon(Class imageClass, NSString *bundleID, double scale) {
    @try {
        SEL selector = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
        if (!bundleID.length || ![imageClass respondsToSelector:selector]) return nil;
        NSMethodSignature *signature = [imageClass methodSignatureForSelector:selector];
        if (signature.numberOfArguments != 5 || signature.methodReturnType[0] != '@' || !ObjectArgument(signature, 2)) return nil;
        NSInvocation *call = [NSInvocation invocationWithMethodSignature:signature];
        call.target = imageClass;
        call.selector = selector;
        [call setArgument:&bundleID atIndex:2];
        // Private signatures vary across iOS versions. Match the runtime ABI
        // instead of assuming the format is a Swift Int32 or the scale a float.
        const char *formatType = [signature getArgumentTypeAtIndex:3];
        if (strcmp(formatType, @encode(int)) == 0) {
            int format = 2;
            [call setArgument:&format atIndex:3];
        } else if (strcmp(formatType, @encode(NSInteger)) == 0) {
            NSInteger format = 2;
            [call setArgument:&format atIndex:3];
        } else { return nil; }
        const char *scaleType = [signature getArgumentTypeAtIndex:4];
        if (strcmp(scaleType, @encode(double)) == 0) {
            [call setArgument:&scale atIndex:4];
        } else if (strcmp(scaleType, @encode(float)) == 0) {
            float smallScale = (float)scale;
            [call setArgument:&smallScale atIndex:4];
        } else { return nil; }
        [call invoke];
        id image = ObjectResult(call);
        return [image isKindOfClass:imageClass] ? image : nil;
    } @catch (NSException *exception) {
        return nil;
    }
}

NSString *VDAppDisplayName(NSString *bundleID) {
    return ReadDisplayName(NSClassFromString(@"LSApplicationProxy"), bundleID);
}

NSObject *VDAppIcon(NSString *bundleID, double scale) {
    return ReadIcon(NSClassFromString(@"UIImage"), bundleID, scale);
}
