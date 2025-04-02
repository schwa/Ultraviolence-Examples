#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface UltraviolenceExamples_GaussianSplatShaders_SWIFTPM_MODULE_BUNDLER_FINDER : NSObject
@end

@implementation UltraviolenceExamples_GaussianSplatShaders_SWIFTPM_MODULE_BUNDLER_FINDER
@end

NSBundle* UltraviolenceExamples_GaussianSplatShaders_SWIFTPM_MODULE_BUNDLE() {
    NSString *bundleName = @"UltraviolenceExamples_GaussianSplatShaders";

    NSArray<NSURL*> *candidates = @[
        NSBundle.mainBundle.resourceURL,
        [NSBundle bundleForClass:[UltraviolenceExamples_GaussianSplatShaders_SWIFTPM_MODULE_BUNDLER_FINDER class]].resourceURL,
        NSBundle.mainBundle.bundleURL
    ];

    for (NSURL* candidate in candidates) {
        NSURL *bundlePath = [candidate URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.bundle", bundleName]];

        NSBundle *bundle = [NSBundle bundleWithURL:bundlePath];
        if (bundle != nil) {
            return bundle;
        }
    }

    @throw [[NSException alloc] initWithName:@"SwiftPMResourcesAccessor" reason:[NSString stringWithFormat:@"unable to find bundle named %@", bundleName] userInfo:nil];
}

NS_ASSUME_NONNULL_END