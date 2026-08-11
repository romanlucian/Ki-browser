#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Swift-facing contract for the future Objective-C++ CEF host.
///
/// This header intentionally contains no CEF or C++ types. It is a compile-time
/// architecture boundary, not a runtime implementation.
@protocol ClearframeChromiumBridgeDelegate <NSObject>
- (void)chromiumBridgeDidChangeURL:(NSURL *)URL;
- (void)chromiumBridgeDidChangeTitle:(NSString *)title;
- (void)chromiumBridgeDidChangeLoading:(BOOL)isLoading progress:(double)progress;
- (void)chromiumBridgeDidChangeCanGoBack:(BOOL)canGoBack
                            canGoForward:(BOOL)canGoForward;
- (void)chromiumBridgeDidFailWithCode:(NSInteger)code
                          description:(NSString *)description
                                  URL:(nullable NSURL *)URL;
- (void)chromiumBridgeRequestedPopupURL:(NSURL *)URL;
@end

/// A future NSView-backed owner for exactly one CEF browser/tab lifecycle.
@interface ClearframeChromiumHostView : NSView

@property(nonatomic, weak, nullable) id<ClearframeChromiumBridgeDelegate> delegate;

- (instancetype)initWithProfileIdentifier:(NSString *)profileIdentifier
    NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(NSRect)frameRect NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

- (void)loadURL:(NSURL *)URL;
- (void)goBack;
- (void)goForward;
- (void)reload;
- (void)stopLoading;

/// Extract visible page content only in response to an explicit user action.
- (void)requestVisiblePageTextWithCompletion:
    (void (^)(NSString *_Nullable text, NSError *_Nullable error))completion;

/// Asynchronously detach callbacks and close the CEF browser for this tab.
- (void)closeBrowserWithCompletion:(void (^)(void))completion;

@end

NS_ASSUME_NONNULL_END
