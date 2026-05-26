#import <Foundation/Foundation.h>
#import <React/RCTBridgeModule.h>
#import <React/RCTUtils.h>
#import <UIKit/UIKit.h>

#if __has_include(<UniformTypeIdentifiers/UniformTypeIdentifiers.h>)
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#endif

@interface MusicFolderModule : NSObject <RCTBridgeModule, UIDocumentPickerDelegate>

@property (nonatomic, copy) RCTPromiseResolveBlock pendingResolve;
@property (nonatomic, copy) RCTPromiseRejectBlock pendingReject;

@end

@implementation MusicFolderModule

RCT_EXPORT_MODULE();

+ (BOOL)requiresMainQueueSetup
{
  return YES;
}

RCT_EXPORT_METHOD(pickFolder:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self.pendingResolve != nil) {
      reject(@"E_PICK_IN_PROGRESS", @"A folder selection is already in progress.", nil);
      return;
    }

    UIViewController *presenter = RCTPresentedViewController();
    if (presenter == nil) {
      reject(@"E_NO_VIEW_CONTROLLER", @"No view controller is available for folder selection.", nil);
      return;
    }

    UIDocumentPickerViewController *picker = nil;
#if __has_include(<UniformTypeIdentifiers/UniformTypeIdentifiers.h>)
    if (@available(iOS 14.0, *)) {
      picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeFolder]
                                                                            asCopy:NO];
    }
#endif

    if (picker == nil) {
      picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.folder"]
                                                                        inMode:UIDocumentPickerModeOpen];
    }

    picker.allowsMultipleSelection = NO;
    picker.delegate = self;

    self.pendingResolve = resolve;
    self.pendingReject = reject;

    [presenter presentViewController:picker animated:YES completion:nil];
  });
}

RCT_EXPORT_METHOD(listPlayableFiles:(NSString *)folderId
                  allowedExtensions:(NSArray<NSString *> *)allowedExtensions
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSError *resolveError = nil;
    NSURL *folderURL = [self folderURLForIdentifier:folderId error:&resolveError];
    if (folderURL == nil) {
      reject(@"E_RESOLVE_FOLDER", @"Failed to resolve the stored folder reference.", resolveError);
      return;
    }

    BOOL grantedAccess = [folderURL startAccessingSecurityScopedResource];
    if (!grantedAccess) {
      reject(@"E_ACCESS_DENIED", @"The app could not access the selected folder anymore.", nil);
      return;
    }

    @try {
      NSSet<NSString *> *normalizedExtensions = [self normalizedExtensions:allowedExtensions];
      NSArray<NSDictionary<NSString *, id> *> *files = [self playableFilesAtURL:folderURL
                                                                allowedExtensions:normalizedExtensions];
      resolve(files);
    } @catch (NSException *exception) {
      NSError *scanError =
          [NSError errorWithDomain:@"MusicFolderModule"
                              code:500
                          userInfo:@{NSLocalizedDescriptionKey : exception.reason ?: @"Folder scan failed."}];
      reject(@"E_SCAN_FOLDER", @"Failed to scan the selected folder.", scanError);
    } @finally {
      [folderURL stopAccessingSecurityScopedResource];
    }
  });
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller
{
  if (self.pendingReject == nil) {
    return;
  }

  self.pendingReject(@"E_PICK_CANCELLED", @"Folder selection was cancelled.", nil);
  self.pendingResolve = nil;
  self.pendingReject = nil;
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
  if (self.pendingResolve == nil || self.pendingReject == nil) {
    return;
  }

  NSURL *folderURL = urls.firstObject;
  if (folderURL == nil) {
    self.pendingReject(@"E_INVALID_RESULT", @"No folder was returned from the picker.", nil);
    self.pendingResolve = nil;
    self.pendingReject = nil;
    return;
  }

  if (![folderURL startAccessingSecurityScopedResource]) {
    self.pendingReject(@"E_ACCESS_DENIED", @"The selected folder could not be accessed.", nil);
    self.pendingResolve = nil;
    self.pendingReject = nil;
    return;
  }

  NSError *bookmarkError = nil;
  NSData *bookmarkData = [folderURL bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope
                             includingResourceValuesForKeys:nil
                                              relativeToURL:nil
                                                      error:&bookmarkError];

  [folderURL stopAccessingSecurityScopedResource];

  if (bookmarkData == nil) {
    self.pendingReject(@"E_CREATE_BOOKMARK", @"Failed to save the selected folder.", bookmarkError);
    self.pendingResolve = nil;
    self.pendingReject = nil;
    return;
  }

  self.pendingResolve(@{
    @"id" : [bookmarkData base64EncodedStringWithOptions:0],
    @"name" : folderURL.lastPathComponent ?: @"Selected folder",
    @"pathLabel" : folderURL.path ?: folderURL.lastPathComponent ?: @"Selected folder",
    @"platform" : @"ios",
  });

  self.pendingResolve = nil;
  self.pendingReject = nil;
}

- (NSURL *)folderURLForIdentifier:(NSString *)folderId error:(NSError **)error
{
  NSData *bookmarkData = [[NSData alloc] initWithBase64EncodedString:folderId options:0];
  if (bookmarkData == nil) {
    if (error != nil) {
      *error = [NSError errorWithDomain:@"MusicFolderModule"
                                   code:400
                               userInfo:@{NSLocalizedDescriptionKey : @"The stored folder reference is invalid."}];
    }
    return nil;
  }

  BOOL isStale = NO;
  return [NSURL URLByResolvingBookmarkData:bookmarkData
                                   options:NSURLBookmarkResolutionWithSecurityScope
                             relativeToURL:nil
                       bookmarkDataIsStale:&isStale
                                     error:error];
}

- (NSArray<NSDictionary<NSString *, id> *> *)playableFilesAtURL:(NSURL *)folderURL
                                               allowedExtensions:(NSSet<NSString *> *)allowedExtensions
{
  NSMutableArray<NSDictionary<NSString *, id> *> *playableFiles = [NSMutableArray new];
  NSArray<NSURLResourceKey> *resourceKeys = @[
    NSURLIsRegularFileKey,
    NSURLIsDirectoryKey,
    NSURLFileSizeKey,
    NSURLContentModificationDateKey,
  ];

  NSDirectoryEnumerator<NSURL *> *enumerator =
      [[NSFileManager defaultManager] enumeratorAtURL:folderURL
                           includingPropertiesForKeys:resourceKeys
                                              options:NSDirectoryEnumerationSkipsHiddenFiles
                                         errorHandler:^BOOL(__unused NSURL *url, __unused NSError *error) {
                                           return YES;
                                         }];

  NSString *rootPath = folderURL.path ?: @"";
  NSString *rootPrefix = [rootPath stringByAppendingString:@"/"];

  for (NSURL *fileURL in enumerator) {
    NSNumber *isDirectory = nil;
    [fileURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
    if (isDirectory.boolValue) {
      continue;
    }

    NSNumber *isRegularFile = nil;
    [fileURL getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:nil];
    if (!isRegularFile.boolValue) {
      continue;
    }

    NSString *extension = fileURL.pathExtension.lowercaseString;
    if (extension.length == 0 || ![allowedExtensions containsObject:extension]) {
      continue;
    }

    NSNumber *fileSize = nil;
    NSDate *modifiedAt = nil;
    [fileURL getResourceValue:&fileSize forKey:NSURLFileSizeKey error:nil];
    [fileURL getResourceValue:&modifiedAt forKey:NSURLContentModificationDateKey error:nil];

    NSString *pathLabel = fileURL.lastPathComponent ?: @"";
    if ([fileURL.path hasPrefix:rootPrefix]) {
      pathLabel = [fileURL.path substringFromIndex:rootPrefix.length];
    }

    [playableFiles addObject:@{
      @"id" : [NSString stringWithFormat:@"%@#%@", fileURL.absoluteString ?: @"", pathLabel],
      @"name" : fileURL.lastPathComponent ?: @"Unknown file",
      @"pathLabel" : pathLabel,
      @"extension" : extension,
      @"size" : fileSize ?: @0,
      @"modifiedAt" : @((modifiedAt ?: [NSDate dateWithTimeIntervalSince1970:0]).timeIntervalSince1970 * 1000.0),
      @"uri" : fileURL.absoluteString ?: @"",
    }];
  }

  return [playableFiles sortedArrayUsingComparator:^NSComparisonResult(NSDictionary<NSString *, id> *lhs,
                                                                       NSDictionary<NSString *, id> *rhs) {
    return [lhs[@"pathLabel"] compare:rhs[@"pathLabel"] options:NSCaseInsensitiveSearch];
  }];
}

- (NSSet<NSString *> *)normalizedExtensions:(NSArray<NSString *> *)allowedExtensions
{
  NSMutableSet<NSString *> *normalized = [NSMutableSet new];

  for (NSString *extension in allowedExtensions) {
    NSString *cleaned = [[[extension stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
        lowercaseString] stringByReplacingOccurrencesOfString:@"." withString:@""];

    if (cleaned.length > 0) {
      [normalized addObject:cleaned];
    }
  }

  return normalized;
}

@end