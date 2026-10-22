#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Returns a dictionary mapping bundleID -> @{ @"name": NSString, @"icon": UIImage }.
/// Uses the private LSApplicationWorkspace API (stable across iOS 14+).
NSDictionary<NSString *, NSDictionary *> *installedAppInfo(void);

/// Fetches an icon for a single bundle ID via LSApplicationProxy.
UIImage * _Nullable iconForBundleID(NSString *bundleID);

/// Returns @{ @"name": NSString, @"icon": UIImage } for a single bundle ID.
NSDictionary *appInfoForBundleID(NSString *bundleID);

/// Opens an installed app using LaunchServices. Returns NO when the private
/// selector is unavailable or the requested bundle cannot be opened.
BOOL openApplicationForBundleID(NSString *bundleID);

/// Checks whether an application is installed by bundle ID.
BOOL isApplicationInstalled(NSString *bundleID);

/// Opens a sensitive system settings URL (e.g. prefs:root=General&path=ManagedConfigurationList/DNS)
/// via LaunchServices workspace. Returns YES if successfully opened.
BOOL openSensitiveSettingsURL(NSString *urlString);

NS_ASSUME_NONNULL_END
