#import "AppIconHelper.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

static UIImage *iconFromData(NSData *data, CGFloat targetSize) {
    if (!data) return nil;
    UIImage *image = [UIImage imageWithData:data];
    if (!image) return nil;
    if (image.size.width <= targetSize && image.size.height <= targetSize) return image;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = image.scale;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(targetSize, targetSize) format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [image drawInRect:CGRectMake(0, 0, targetSize, targetSize)];
    }];
}

static NSData *iconDataFromProxy(id proxy) {
    SEL iconSel = NSSelectorFromString(@"iconDataForVariant:");
    if (![proxy respondsToSelector:iconSel]) return nil;

    // Variant availability differs between iOS releases and app types.
    // Stop at the first usable image instead of assuming variant zero exists.
    const int variants[] = {2, 0, 1, 3, 4, 5, 6, 7, 15};
    for (NSUInteger index = 0; index < sizeof(variants) / sizeof(variants[0]); index++) {
        id data = ((id (*)(id, SEL, int))objc_msgSend)(proxy, iconSel, variants[index]);
        if ([data isKindOfClass:[NSData class]] && [data length] > 0) return data;
    }
    return nil;
}

static BOOL proxyMatchesBundleIdentifier(id proxy, NSString *bundleID) {
    if (!proxy || bundleID.length == 0) return NO;
    NSString *teamPrefixedSuffix = [@"." stringByAppendingString:bundleID];
    for (NSString *selectorName in @[@"bundleIdentifier", @"applicationIdentifier"]) {
        SEL selector = NSSelectorFromString(selectorName);
        if (![proxy respondsToSelector:selector]) continue;
        id value = ((id (*)(id, SEL))objc_msgSend)(proxy, selector);
        if (![value isKindOfClass:[NSString class]]) continue;
        NSString *proxyBundleID = value;
        if ([proxyBundleID isEqualToString:bundleID] ||
            [proxyBundleID hasSuffix:teamPrefixedSuffix]) {
            return YES;
        }
    }
    return NO;
}

static BOOL isFreeFireBundleIdentifier(NSString *bundleID) {
    return [bundleID isEqualToString:@"com.dts.freefireth"] ||
           [bundleID isEqualToString:@"com.dts.freefiremax"];
}

static NSString *stringForFirstKey(NSDictionary *info, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        id value = info[key];
        if ([value isKindOfClass:[NSString class]] && [value length] > 0) return value;
    }
    return nil;
}

static NSString *pathForFirstKey(NSDictionary *info, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        id value = info[key];
        if ([value isKindOfClass:[NSURL class]]) {
            NSString *path = [value path];
            if (path.length > 0) return path;
        }
        if ([value isKindOfClass:[NSString class]] && [value length] > 0) return value;
    }
    return nil;
}

static void addApplicationInfo(NSMutableDictionary *result, NSString *fallbackBundleID, NSDictionary *info) {
    NSString *bundleID = stringForFirstKey(info, @[
        @"CFBundleIdentifier", @"BundleIdentifier", @"ApplicationIdentifier", @"MCMMetadataIdentifier"
    ]);
    if (bundleID.length == 0) bundleID = fallbackBundleID;
    if (bundleID.length == 0) return;

    NSString *name = stringForFirstKey(info, @[
        @"CFBundleDisplayName", @"CFBundleName", @"LocalizedName", @"Name"
    ]);
    NSString *container = pathForFirstKey(info, @[
        @"Container", @"DataContainer", @"DataContainerURL", @"ContainerPath", @"SandboxPath"
    ]);
    NSString *version = stringForFirstKey(info, @[
        @"CFBundleShortVersionString", @"BundleShortVersionString"
    ]);

    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    entry[@"name"] = name.length > 0 ? name : bundleID;
    if (container.length > 0) entry[@"container"] = container;
    if (version.length > 0) entry[@"version"] = version;
    result[bundleID] = entry;
}

static void *mobileInstallationHandle(void) {
    static void *handle;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        handle = dlopen("/System/Library/PrivateFrameworks/MobileInstallation.framework/MobileInstallation", RTLD_LAZY | RTLD_LOCAL);
    });
    return handle;
}

static NSDictionary *appsFromMobileInstallation(void) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    void *frameworkHandle = mobileInstallationHandle();

    // Legacy path for older releases where the original symbol is still exported.
    void *lookupFn = dlsym(RTLD_DEFAULT, "MobileInstallationLookup");
    if (!lookupFn && frameworkHandle) {
        lookupFn = dlsym(frameworkHandle, "MobileInstallationLookup");
    }
    if (!lookupFn) return result;

    NSDictionary *apps = nil;
    NSArray *optionSets = @[
        @{@"ApplicationType": @"Any"},
        @{@"ApplicationType": @"User"},
        @{@"ApplicationType": @"System"},
        @{},
    ];
    for (NSDictionary *options in optionSets) {
        apps = ((NSDictionary *(*)(NSDictionary *, void *))lookupFn)(options, NULL);
        if (apps && [apps isKindOfClass:[NSDictionary class]] && apps.count > 0) break;
    }
    if (!apps || apps.count == 0) return result;

    for (NSString *bundleID in apps) {
        @autoreleasepool {
            id rawInfo = apps[bundleID];
            if (![rawInfo isKindOfClass:[NSDictionary class]]) continue;
            addApplicationInfo(result, bundleID, rawInfo);
        }
    }
    return result;
}

static void ensureLaunchServicesLoaded(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        const char *candidates[] = {
            "/System/Library/Frameworks/CoreServices.framework/CoreServices",
            "/System/Library/PrivateFrameworks/MobileCoreServices.framework/MobileCoreServices",
            "/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices",
        };
        for (size_t i = 0; i < sizeof(candidates) / sizeof(candidates[0]); i++) {
            if (dlopen(candidates[i], RTLD_LAZY | RTLD_GLOBAL)) {
                NSLog(@"[3105] ls: loaded %s", candidates[i]);
                return;
            }
        }
        NSLog(@"[3105] ls: CoreServices/MobileCoreServices dlopen failed");
    });
}

static NSDictionary *appsFromWorkspace(void) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    ensureLaunchServicesLoaded();

    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!workspaceClass) {
        NSLog(@"[3105] ls: LSApplicationWorkspace class unavailable");
        return result;
    }
    SEL defaultWorkspaceSel = NSSelectorFromString(@"defaultWorkspace");
    if (![workspaceClass respondsToSelector:defaultWorkspaceSel]) {
        NSLog(@"[3105] ls: defaultWorkspace selector unavailable");
        return result;
    }
    id workspace = ((id (*)(id, SEL))objc_msgSend)(workspaceClass, defaultWorkspaceSel);
    if (!workspace) {
        NSLog(@"[3105] ls: defaultWorkspace returned nil");
        return result;
    }

    NSArray *apps = nil;
    NSString *usedSelector = nil;
    for (NSString *selectorName in @[@"allApplications", @"allInstalledApplications"]) {
        SEL allAppsSel = NSSelectorFromString(selectorName);
        if (![workspace respondsToSelector:allAppsSel]) continue;
        id candidate = ((id (*)(id, SEL))objc_msgSend)(workspace, allAppsSel);
        if ([candidate isKindOfClass:[NSArray class]] && [candidate count] > 0) {
            apps = candidate;
            usedSelector = selectorName;
            break;
        }
        NSLog(@"[3105] ls: %@ returned %lu", selectorName,
              (unsigned long)([candidate isKindOfClass:[NSArray class]] ? [candidate count] : 0));
    }
    if (!apps || apps.count == 0) {
        NSLog(@"[3105] ls: workspace enumeration empty");
        return result;
    }
    NSLog(@"[3105] ls: %@ returned %lu proxies", usedSelector, (unsigned long)apps.count);

    NSUInteger withContainer = 0;
    for (id app in apps) {
        @autoreleasepool {
            NSString *bundleID = nil;
            for (NSString *selectorName in @[@"bundleIdentifier", @"applicationIdentifier"]) {
                SEL bundleSel = NSSelectorFromString(selectorName);
                if (![app respondsToSelector:bundleSel]) continue;
                id value = ((id (*)(id, SEL))objc_msgSend)(app, bundleSel);
                if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
                    bundleID = value;
                    break;
                }
            }
            if (bundleID.length == 0) continue;

            NSString *name = nil;
            for (NSString *selectorName in @[@"localizedName", @"localizedShortName"]) {
                SEL nameSel = NSSelectorFromString(selectorName);
                if (![app respondsToSelector:nameSel]) continue;
                id value = ((id (*)(id, SEL))objc_msgSend)(app, nameSel);
                if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
                    name = value;
                    break;
                }
            }
            if (name.length == 0) name = bundleID;

            NSMutableDictionary *entry = [NSMutableDictionary dictionary];
            entry[@"name"] = name;
            for (NSString *selectorName in @[@"dataContainerURL", @"containerURL"]) {
                SEL containerSel = NSSelectorFromString(selectorName);
                if (![app respondsToSelector:containerSel]) continue;
                id containerValue = ((id (*)(id, SEL))objc_msgSend)(app, containerSel);
                NSString *containerPath = [containerValue isKindOfClass:[NSURL class]] ? [containerValue path] : containerValue;
                if ([containerPath isKindOfClass:[NSString class]] && containerPath.length > 0) {
                    entry[@"container"] = containerPath;
                    withContainer++;
                    break;
                }
            }
            result[bundleID] = entry;
        }
    }
    NSLog(@"[3105] ls: extracted %lu apps (%lu with container)",
          (unsigned long)result.count, (unsigned long)withContainer);
    return result;
}

NSDictionary<NSString *, NSDictionary *> *installedAppInfo(void) {
    NSDictionary *workspace = appsFromWorkspace();
    if (workspace.count > 0) return workspace;
    NSDictionary *mobileInstallation = appsFromMobileInstallation();
    NSLog(@"[3105] ls: workspace empty; MobileInstallation=%lu",
          (unsigned long)mobileInstallation.count);
    return mobileInstallation;
}

static UIImage *iconFromBundleURL(NSURL *bundleURL) {
    if (!bundleURL) return nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *bundlePath = [bundleURL path];
    if (!bundlePath || ![fm fileExistsAtPath:bundlePath]) return nil;

    NSString *infoPlistPath = [bundlePath stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *infoDict = [NSDictionary dictionaryWithContentsOfFile:infoPlistPath];
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    if (infoDict) {
        id cfIcons = infoDict[@"CFBundleIcons"];
        if ([cfIcons isKindOfClass:[NSDictionary class]]) {
            id primary = cfIcons[@"CFBundlePrimaryIcon"];
            if ([primary isKindOfClass:[NSDictionary class]]) {
                id files = primary[@"CFBundleIconFiles"];
                if ([files isKindOfClass:[NSArray class]]) [candidates addObjectsFromArray:files];
            }
        }
        id cfIconsIpad = infoDict[@"CFBundleIcons~ipad"];
        if ([cfIconsIpad isKindOfClass:[NSDictionary class]]) {
            id primary = cfIconsIpad[@"CFBundlePrimaryIcon"];
            if ([primary isKindOfClass:[NSDictionary class]]) {
                id files = primary[@"CFBundleIconFiles"];
                if ([files isKindOfClass:[NSArray class]]) [candidates addObjectsFromArray:files];
            }
        }
        id iconFiles = infoDict[@"CFBundleIconFiles"];
        if ([iconFiles isKindOfClass:[NSArray class]]) [candidates addObjectsFromArray:iconFiles];
        id iconFile = infoDict[@"CFBundleIconFile"];
        if ([iconFile isKindOfClass:[NSString class]]) [candidates addObject:iconFile];
    }

    NSArray<NSString *> *suffixes = @[@"@3x.png", @"@2x.png", @".png", @"~ipad.png", @"@2x~ipad.png"];
    for (NSString *baseName in [candidates reverseObjectEnumerator]) {
        for (NSString *sfx in suffixes) {
            NSString *fullName = [baseName stringByAppendingString:sfx];
            NSString *p = [bundlePath stringByAppendingPathComponent:fullName];
            if ([fm fileExistsAtPath:p]) {
                UIImage *img = [UIImage imageWithContentsOfFile:p];
                if (img) return img;
            }
        }
        NSString *p = [bundlePath stringByAppendingPathComponent:baseName];
        if ([fm fileExistsAtPath:p]) {
            UIImage *img = [UIImage imageWithContentsOfFile:p];
            if (img) return img;
        }
    }

    NSArray *contents = [fm contentsOfDirectoryAtPath:bundlePath error:nil];
    for (NSString *file in contents) {
        if ([file hasPrefix:@"AppIcon"] && [file hasSuffix:@".png"]) {
            NSString *p = [bundlePath stringByAppendingPathComponent:file];
            UIImage *img = [UIImage imageWithContentsOfFile:p];
            if (img && img.size.width >= 40) return img;
        }
    }
    return nil;
}

static UIImage *iconFromUIKitPrivate(NSString *bundleID) {
    if (bundleID.length == 0) return nil;
    SEL sel = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
    if ([UIImage respondsToSelector:sel]) {
        CGFloat scale = [UIScreen mainScreen].scale;
        if (scale < 1.0) scale = 2.0;
        UIImage *img = ((UIImage *(*)(id, SEL, id, int, CGFloat))objc_msgSend)([UIImage class], sel, bundleID, 2, scale);
        if (img) return img;
        img = ((UIImage *(*)(id, SEL, id, int, CGFloat))objc_msgSend)([UIImage class], sel, bundleID, 0, scale);
        if (img) return img;
    }
    return nil;
}

BOOL isApplicationInstalled(NSString *bundleID) {
    if (bundleID.length == 0) return NO;
    ensureLaunchServicesLoaded();

    Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
    SEL defSel = NSSelectorFromString(@"defaultWorkspace");
    if (wsClass && [wsClass respondsToSelector:defSel]) {
        id ws = ((id (*)(id, SEL))objc_msgSend)(wsClass, defSel);
        SEL instSel = NSSelectorFromString(@"applicationIsInstalled:");
        if (ws && [ws respondsToSelector:instSel]) {
            BOOL isInst = ((BOOL (*)(id, SEL, id))objc_msgSend)(ws, instSel, bundleID);
            if (isInst) return YES;
        }
    }

    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    SEL appProxySel = NSSelectorFromString(@"applicationProxyForIdentifier:");
    if (proxyClass && [proxyClass respondsToSelector:appProxySel]) {
        id proxy = ((id (*)(id, SEL, id))objc_msgSend)(proxyClass, appProxySel, bundleID);
        if (proxy) {
            SEL isInstSel = NSSelectorFromString(@"isInstalled");
            if ([proxy respondsToSelector:isInstSel]) {
                BOOL isInst = ((BOOL (*)(id, SEL))objc_msgSend)(proxy, isInstSel);
                if (isInst) return YES;
            }
            SEL bURLSel = NSSelectorFromString(@"bundleURL");
            if ([proxy respondsToSelector:bURLSel]) {
                id bURL = ((id (*)(id, SEL))objc_msgSend)(proxy, bURLSel);
                if (bURL != nil) return YES;
            }
            SEL cURLSel = NSSelectorFromString(@"dataContainerURL");
            if (![proxy respondsToSelector:cURLSel]) cURLSel = NSSelectorFromString(@"containerURL");
            if ([proxy respondsToSelector:cURLSel]) {
                id cURL = ((id (*)(id, SEL))objc_msgSend)(proxy, cURLSel);
                if (cURL != nil) return YES;
            }
        }
    }

    return NO;
}

// Icon via LSApplicationProxy / bundle URL / UIKit private / assets fallback.
//
// LSApplicationProxy is authoritative because the returned icon data belongs to
// the exact installed application proxy. The UIKit private helper is deliberately
// not used for Free Fire: on some sideloaded iOS builds it ignores the requested
// identifier and returns another application's icon, which previously caused TH
// and MAX to display the same image.
UIImage *iconForBundleID(NSString *bundleID) {
    if (bundleID.length == 0) return nil;
    BOOL isFreeFire = isFreeFireBundleIdentifier(bundleID);
    static NSCache<NSString *, UIImage *> *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 256;
    });
    // Always re-query the two games so a rescan can observe an updated or
    // alternate installed icon instead of retaining an earlier result.
    if (!isFreeFire) {
        UIImage *cached = [cache objectForKey:bundleID];
        if (cached) return cached;
    }

    // 1. Resolve and verify the exact LaunchServices proxy.
    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    id proxy = nil;
    if (proxyClass) {
        SEL appProxySel = NSSelectorFromString(@"applicationProxyForIdentifier:");
        if ([proxyClass respondsToSelector:appProxySel]) {
            proxy = ((id (*)(id, SEL, id))objc_msgSend)(proxyClass, appProxySel, bundleID);
        }
    }
    if (!proxyMatchesBundleIdentifier(proxy, bundleID)) {
        proxy = nil;
    }

    // 2. Ask that verified proxy for its current installed icon.
    UIImage *icon = nil;
    BOOL shouldCacheIcon = NO;
    if (proxy) {
        icon = iconFromData(iconDataFromProxy(proxy), 60.0);
        if (icon) {
            shouldCacheIcon = YES;
            NSLog(@"[3105] icon: proxy data %@", bundleID);
        }
    }

    // 3. Try loose icon files in the exact installed app bundle. This is mainly
    // useful for older apps; modern apps commonly keep their icons in Assets.car.
    if (!icon && proxy) {
        SEL bundleURLSel = NSSelectorFromString(@"bundleURL");
        if ([proxy respondsToSelector:bundleURLSel]) {
            id bURL = ((id (*)(id, SEL))objc_msgSend)(proxy, bundleURLSel);
            if ([bURL isKindOfClass:[NSURL class]]) {
                icon = iconFromBundleURL(bURL);
                if (icon) {
                    shouldCacheIcon = YES;
                    NSLog(@"[3105] icon: bundle files %@", bundleID);
                }
            }
        }
    }

    // 4. Keep the legacy UIKit lookup for the generic app browser only. Its
    // result cannot be trusted for the two game choices in the patch dialog.
    if (!icon && !isFreeFire) {
        icon = iconFromUIKitPrivate(bundleID);
        if (icon) {
            shouldCacheIcon = YES;
            NSLog(@"[3105] icon: UIKit fallback %@", bundleID);
        }
    }

    // 5. If iOS blocks icon extraction, use the correct per-game bundled image.
    if (!icon) {
        if ([bundleID isEqualToString:@"com.dts.freefireth"]) {
            icon = [UIImage imageNamed:@"FreeFireTHIcon"];
        } else if ([bundleID isEqualToString:@"com.dts.freefiremax"]) {
            icon = [UIImage imageNamed:@"FreeFireMAXIcon"];
        }
        if (icon) NSLog(@"[3105] icon: bundled fallback %@", bundleID);
    }

    if (icon && shouldCacheIcon && !isFreeFire) {
        [cache setObject:icon forKey:bundleID];
    }
    return icon;
}

// Name + icon for a single bundle ID via LSApplicationProxy
NSDictionary *appInfoForBundleID(NSString *bundleID) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"name"] = bundleID;

    ensureLaunchServicesLoaded();

    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    id proxy = nil;
    if (proxyClass) {
        SEL appProxySel = NSSelectorFromString(@"applicationProxyForIdentifier:");
        if ([proxyClass respondsToSelector:appProxySel]) {
            proxy = ((id (*)(id, SEL, id))objc_msgSend)(proxyClass, appProxySel, bundleID);
        }
    }

    BOOL found = NO;
    if (proxy) {
        for (NSString *selectorName in @[@"applicationIdentifier", @"bundleIdentifier"]) {
            SEL identifierSel = NSSelectorFromString(selectorName);
            if (![proxy respondsToSelector:identifierSel]) continue;
            id value = ((id (*)(id, SEL))objc_msgSend)(proxy, identifierSel);
            if ([value isKindOfClass:[NSString class]]) {
                if ([value isEqualToString:bundleID] || [value hasSuffix:[@"." stringByAppendingString:bundleID]]) {
                    found = YES;
                    break;
                }
            }
        }
        if (!found) {
            SEL isInstSel = NSSelectorFromString(@"isInstalled");
            if ([proxy respondsToSelector:isInstSel] && ((BOOL (*)(id, SEL))objc_msgSend)(proxy, isInstSel)) {
                found = YES;
            }
        }
        if (!found) {
            SEL bURLSel = NSSelectorFromString(@"bundleURL");
            if ([proxy respondsToSelector:bURLSel] && ((id (*)(id, SEL))objc_msgSend)(proxy, bURLSel) != nil) {
                found = YES;
            }
        }
    }

    if (!found) {
        found = isApplicationInstalled(bundleID);
    }

    if (!found) return result;
    result[@"found"] = @YES;

    NSURL *bundleURL = nil;
    if (proxy) {
        SEL bundleURLSel = NSSelectorFromString(@"bundleURL");
        if ([proxy respondsToSelector:bundleURLSel]) {
            id value = ((id (*)(id, SEL))objc_msgSend)(proxy, bundleURLSel);
            if ([value isKindOfClass:[NSURL class]]) bundleURL = value;
        }
    }

    NSBundle *applicationBundle = bundleURL ? [NSBundle bundleWithURL:bundleURL] : nil;
    NSDictionary *localizedInfo = applicationBundle.localizedInfoDictionary;
    NSDictionary *bundleInfo = applicationBundle.infoDictionary;
    NSString *bundleName = stringForFirstKey(localizedInfo, @[
        @"CFBundleDisplayName", @"CFBundleName"
    ]);
    if (bundleName.length == 0) {
        bundleName = stringForFirstKey(bundleInfo, @[
            @"CFBundleDisplayName", @"CFBundleName"
        ]);
    }
    if (bundleName.length > 0) result[@"name"] = bundleName;

    if ([result[@"name"] isEqualToString:bundleID] && proxy) {
        for (NSString *selectorName in @[@"localizedName", @"localizedShortName"]) {
            SEL nameSel = NSSelectorFromString(selectorName);
            if (![proxy respondsToSelector:nameSel]) continue;
            NSString *name = ((id (*)(id, SEL))objc_msgSend)(proxy, nameSel);
            if ([name isKindOfClass:[NSString class]] && name.length > 0) {
                result[@"name"] = name;
                break;
            }
        }
    }

    NSString *bundleVersion = stringForFirstKey(bundleInfo, @[
        @"CFBundleShortVersionString"
    ]);
    if (bundleVersion.length > 0) result[@"version"] = bundleVersion;
    if (!result[@"version"] && proxy) {
        SEL versionSel = NSSelectorFromString(@"shortVersionString");
        if ([proxy respondsToSelector:versionSel]) {
            NSString *version = ((id (*)(id, SEL))objc_msgSend)(proxy, versionSel);
            if ([version isKindOfClass:[NSString class]] && version.length > 0) {
                result[@"version"] = version;
            }
        }
    }

    if (proxy) {
        for (NSString *selectorName in @[@"dataContainerURL", @"containerURL"]) {
            SEL containerSel = NSSelectorFromString(selectorName);
            if (![proxy respondsToSelector:containerSel]) continue;
            id value = ((id (*)(id, SEL))objc_msgSend)(proxy, containerSel);
            NSString *path = [value isKindOfClass:[NSURL class]] ? [value path] : value;
            if ([path isKindOfClass:[NSString class]] && path.length > 0) {
                result[@"container"] = path;
                break;
            }
        }
    }

    UIImage *icon = iconForBundleID(bundleID);
    if (icon) result[@"icon"] = icon;

    return result;
}

BOOL openApplicationForBundleID(NSString *bundleID) {
    if (bundleID.length == 0) return NO;
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    SEL defaultWorkspaceSelector = NSSelectorFromString(@"defaultWorkspace");
    if (!workspaceClass || ![workspaceClass respondsToSelector:defaultWorkspaceSelector]) {
        return NO;
    }
    id workspace = ((id (*)(id, SEL))objc_msgSend)(
        workspaceClass,
        defaultWorkspaceSelector
    );
    if (!workspace) return NO;
    SEL openSelector = NSSelectorFromString(@"openApplicationWithBundleID:");
    if (![workspace respondsToSelector:openSelector]) return NO;
    return ((BOOL (*)(id, SEL, id))objc_msgSend)(workspace, openSelector, bundleID);
}

BOOL openSensitiveSettingsURL(NSString *urlString) {
    if (urlString.length == 0) return NO;
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return NO;

    ensureLaunchServicesLoaded();

    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    SEL defaultWorkspaceSelector = NSSelectorFromString(@"defaultWorkspace");
    if (!workspaceClass || ![workspaceClass respondsToSelector:defaultWorkspaceSelector]) {
        return NO;
    }

    id workspace = ((id (*)(id, SEL))objc_msgSend)(
        workspaceClass,
        defaultWorkspaceSelector
    );
    if (!workspace) return NO;

    // 1. Thử openSensitiveURL:withOptions: (được Apple cấp quyền mở các scheme nội bộ prefs: trong Settings)
    SEL openSensitiveSel = NSSelectorFromString(@"openSensitiveURL:withOptions:");
    if ([workspace respondsToSelector:openSensitiveSel]) {
        BOOL ok = ((BOOL (*)(id, SEL, id, id))objc_msgSend)(workspace, openSensitiveSel, url, nil);
        if (ok) return YES;
    }

    // 2. Thử openURL: thông qua LaunchServices
    SEL openURLSel = NSSelectorFromString(@"openURL:");
    if ([workspace respondsToSelector:openURLSel]) {
        BOOL ok = ((BOOL (*)(id, SEL, id))objc_msgSend)(workspace, openURLSel, url);
        if (ok) return YES;
    }

    return NO;
}
