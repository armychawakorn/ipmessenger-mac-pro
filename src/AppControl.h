/*============================================================================*
 * (C) 2001-2026 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for macOS
 *	File		: AppControl.h
 *	Module		: アプリケーションコントローラ
 *============================================================================*/

#import <Cocoa/Cocoa.h>
#import <Sparkle/SPUStandardUpdaterController.h>

@class RecvMessage;
@class SendControl;

/*============================================================================*
 * Notification 通知キー
 *============================================================================*/

/// ホスト名変更
extern NSString * _Nonnull const kIPMsgHostNameChangedNotification;
/// ネットワーク検出
extern NSString * _Nonnull const kIPMsgNetworkGainedNotification;
/// ネットワーク喪失通知
extern NSString * _Nonnull const kIPMsgNetworkLostNotification;

/*============================================================================*
 * 関数定義
 *============================================================================*/

// ホスト名取得
extern NSString* _Nullable AppControlGetHostName(void);

// IPアドレス取得
extern UInt32 AppControlGetIPAddress(void);

NS_ASSUME_NONNULL_BEGIN

/*============================================================================*
 * クラス定義
 *============================================================================*/

@interface AppControl : NSObject <NSApplicationDelegate, NSMenuItemValidation>

// IBOutletプロパティ（ARCではstrongが推奨）
@property (strong, nonatomic) IBOutlet NSMenu*		absenceMenu;					// 不在メニュー
@property (strong, nonatomic) IBOutlet NSMenuItem*	absenceOffMenuItem;				// 不在解除メニュー項目
@property (strong, nonatomic) IBOutlet NSMenu*		absenceMenuForDock;				// Dock用不在メニュー
@property (strong, nonatomic) IBOutlet NSMenuItem*	absenceOffMenuItemForDock;		// Dock用不在解除メニュー項目
@property (strong, nonatomic) IBOutlet NSMenu*		absenceMenuForStatusBar;		// ステータスバー用不在メニュー
@property (strong, nonatomic) IBOutlet NSMenuItem*	absenceOffMenuItemForStatusBar;	// ステータスバー用不在解除メニュー項目

@property (strong, nonatomic) IBOutlet NSMenuItem*	showNonPopupMenuItem;			// ノンポップアップ表示メニュー項目

@property (strong, nonatomic) IBOutlet NSMenuItem*	sendWindowListUserMenuItem;		// 送信ウィンドウユーザ一覧ユーザメニュー項目
@property (strong, nonatomic) IBOutlet NSMenuItem*	sendWindowListGroupMenuItem;	// 送信ウィンドウユーザ一覧グループメニュー項目
@property (strong, nonatomic) IBOutlet NSMenuItem*	sendWindowListHostMenuItem;		// 送信ウィンドウユーザ一覧ホストメニュー項目
@property (strong, nonatomic) IBOutlet NSMenuItem*	sendWindowListIPAddressMenuItem;// 送信ウィンドウユーザ一覧IPアドレスメニュー項目
@property (strong, nonatomic) IBOutlet NSMenuItem*	sendWindowListLogonMenuItem;	// 送信ウィンドウユーザ一覧ログオンメニュー項目
@property (strong, nonatomic) IBOutlet NSMenuItem*	sendWindowListVersionMenuItem;	// 送信ウィンドウユーザ一覧バージョンメニュー項目

@property (strong, nonatomic) IBOutlet NSMenu*		statusBarMenu;					// ステータスバー用のメニュー

// Sparkle 2 updater controller
@property (strong, readonly) SPUStandardUpdaterController *updaterController;

// メッセージ送受信／ウィンドウ関連処理
- (IBAction)newMessage:(id)sender;
- (void)receiveMessage:(RecvMessage*)msg;
- (IBAction)closeAllWindows:(id)sender;
- (IBAction)closeAllDialogs:(id)sender;
- (IBAction)showNonPopupMessage:(id)sender;

// 不在関連処理
- (IBAction)absenceMenuChanged:(id)sender;
- (void)buildAbsenceMenu;
- (void)setAbsenceOff;

// ステータスバー関連
- (IBAction)clickStatusBar:(id)sender;
- (void)initStatusBar;
- (void)removeStatusBar;

// その他
- (IBAction)gotoHomePage:(id)sender;
- (IBAction)showAcknowledgement:(id)sender;
- (IBAction)openLog:(id)sender;

// Sparkle 2 - 更新チェック
- (IBAction)checkForUpdates:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
