/*============================================================================*
 * (C) 2001-2026 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for macOS
 *	File		: AppControl.m
 *	Module		: アプリケーションコントローラ
 *============================================================================*/

#import "AppControl.h"
#import "Config.h"
#import "MessageCenter.h"
#import "RecvMessage.h"
#import "ReceiveControl.h"
#import "SendControl.h"
#import "NoticeControl.h"
#import "UserManager.h"
#import "UserInfo.h"
#import "DebugLog.h"

#import <SystemConfiguration/SystemConfiguration.h>
#import <unistd.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>

/*============================================================================*
 * Notification 通知キー
 *============================================================================*/

// ホスト名変更
NSString* const kIPMsgHostNameChangedNotification	= @"IPMsgHostNameChangedNotification";
// ネットワーク検出
NSString* const kIPMsgNetworkGainedNotification		= @"IPMsgNetworkGainedNotification";
// ネットワーク喪失
NSString* const kIPMsgNetworkLostNotification		= @"IPMsgNetworkLostNotification";

/*============================================================================*
 * 定数定義
 *============================================================================*/

#define ABSENCE_OFF_MENU_TAG	1000
#define ABSENCE_ITEM_MENU_TAG	2000

typedef NS_ENUM(NSInteger, _NetUpdateState)
{
	_NET_NO_CHANGE_IN_LINK,
	_NET_NO_CHANGE_IN_UNLINK,
	_NET_LINK_GAINED,
	_NET_LINK_LOST,
	_NET_PRIMARY_IF_CHANGED,
	_NET_IP_ADDRESS_CHANGED
};

typedef NS_ENUM(NSInteger, _ActivatedState)
{
	_ACTIVATED_INIT	= -1,
	_ACTIVATED_NO	= 0,
	_ACTIVATED_YES	= 1
};

/*============================================================================*
 * プライベート拡張
 *============================================================================*/

typedef NSMutableArray<ReceiveControl*>		_RecvCtrlList;

@interface AppControl()

// Sparkle 2
@property(strong)	SPUStandardUpdaterController* updaterController;	// Sparkle 2 updater

@property(assign)	_ActivatedState	activatedFlag;			// アプリケーションアクティベートフラグ
@property(strong)	NSStatusItem*	statusBarItem;			// ステータスアイテムのインスタンス
@property(strong)	_RecvCtrlList*	receiveQueue;			// 受信メッセージ（ウィンドウ）キュー
@property(strong)	NSTimer*		iconToggleTimer;		// アイコントグル用タイマー
@property(strong)	NSImage*		iconNormal;				// 通常時アプリアイコン
@property(strong)	NSImage*		iconNormalReverse;		// 通常時アプリアイコン（反転）
@property(strong)	NSImage*		iconAbsence;			// 不在時アプリアイコン
@property(strong)	NSImage*		iconAbsenceReverse;		// 不在時アプリアイコン（反転）
@property(strong)	NSImage* 		iconSmallNormal;		// 通常時アプリスモールアイコン
@property(strong)	NSImage* 		iconSmallNormalReverse;	// 通常時アプリスモールアイコン（反転）
@property(strong)	NSImage*		iconSmallAbsence;		// 不在時アプリスモールアイコン
@property(strong)	NSImage*		iconSmallAbsenceReverse;// 不在時アプリスモールアイコン（反転）
@property(strong)	NSDate*			lastDockDraggedDate;	// 前回Dockドラッグ受付時刻
@property(weak)		SendControl*	lastDockDraggedWindow;	// 前回Dockドラッグ時生成ウィンドウ

// DynamicStore関連
@property(assign)	CFRunLoopSourceRef		runLoopSource;	// Run Loop Source Obj for SC Notification
@property(assign)	SCDynamicStoreRef		scDynStore;		// DynamicStore
@property(assign)	SCDynamicStoreContext	scDSContext;	// DynamicStoreContext
@property(copy)		NSString*				scKeyHostName;	// DynamicStore Key [for LocalHostName]
@property(copy)		NSString*				scKeyNetIPv4;	// DynamicStore Key [for Global IPv4]
@property(copy)		NSString*				scKeyIFIPv4;	// DynamicStore Key [for IF IPv4 Address]

@property(copy)		NSString*				primaryNIC;		// ネットワークインタフェース

- (BOOL)updateHostName;
- (_NetUpdateState)updateIPAddress;
- (_NetUpdateState)updatePrimaryNIC;

@end

/*============================================================================*
 * ローカルグローバル変数
 *============================================================================*/

// AppControlのプロパティにするとメインスレッド規制でパフォーマンスが悪くなるため
static	UInt32		gMyIPAddress	= 0;		// ローカルホストアドレス
static	NSString*	gMyHostName		= nil;		// ホスト名

/*============================================================================*
 * ローカル関数
 *============================================================================*/

// DynamicStore Callback Func
static void _DynamicStoreCallback(SCDynamicStoreRef	store,
								  CFArrayRef		changedKeys,
								  void*				info);

/*============================================================================*
 * クラス実装
 *============================================================================*/

@implementation AppControl

//*---------------------------------------------------------------------------*
#pragma mark - 初期化/解放
//*---------------------------------------------------------------------------*

// 初期化
- (instancetype)init
{
	self = [super init];
	if (self) {
		// Sparkle 2 初期化
		_updaterController = [[SPUStandardUpdaterController alloc]
			initWithStartingUpdater:YES
			updaterDelegate:nil
			userDriverDelegate:nil];
		
		_receiveQueue				= [[_RecvCtrlList alloc] init];
		_iconNormal					= [NSImage imageNamed:@"AppIcon"];
		_iconNormalReverse			= [NSImage imageNamed:@"AppIcon_Reverse"];
		_iconAbsence				= [NSImage imageNamed:@"AppIcon_Absence"];
		_iconAbsenceReverse			= [NSImage imageNamed:@"AppIcon_AbsenceReverse"];
		_iconSmallNormal			= [NSImage imageNamed:@"MenuIcon"];
		_iconSmallNormal.template	= YES;
		NSImage* tintImg = [_iconSmallNormal copy];
		[tintImg lockFocus];
		[[NSColor selectedContentBackgroundColor] set];
		NSRectFillUsingOperation(NSMakeRect(0, 0, tintImg.size.width, tintImg.size.height), NSCompositingOperationSourceAtop);
		[tintImg unlockFocus];
		tintImg.template = NO;
		_iconSmallNormalReverse  	= tintImg;
		_iconSmallAbsence			= _iconSmallNormal;
		_iconSmallAbsenceReverse	= _iconSmallNormalReverse;

		// DynaimcStore生成
		memset(&_scDSContext, 0, sizeof(_scDSContext));
		_scDSContext.info = (__bridge void*)self;
		_scDynStore = SCDynamicStoreCreate(NULL,
										   (__bridge CFStringRef)@"net.ishwt.IPMessenger",
										   _DynamicStoreCallback,
										   &_scDSContext);
		if (_scDynStore) {
			// DynamicStore更新通知設定
			_scKeyHostName	= (__bridge_transfer NSString*)SCDynamicStoreKeyCreateHostNames(NULL);
			_scKeyNetIPv4 = (__bridge_transfer NSString*)SCDynamicStoreKeyCreateNetworkGlobalEntity(
																				  NULL, kSCDynamicStoreDomainState, kSCEntNetIPv4);
			NSArray<NSString*>* keys = @[_scKeyHostName, _scKeyNetIPv4];
			if (!SCDynamicStoreSetNotificationKeys(_scDynStore, (__bridge CFArrayRef)keys, NULL)) {
				ERR(@"dynamic store notification set error");
			}
			_runLoopSource = SCDynamicStoreCreateRunLoopSource(NULL, _scDynStore, 0);
			CFRunLoopAddSource(CFRunLoopGetCurrent(), _runLoopSource, kCFRunLoopDefaultMode);
		}
	}

	return self;
}

// 解放
- (void)dealloc
{
	if (_runLoopSource) {
		CFRunLoopRemoveSource(CFRunLoopGetCurrent(), _runLoopSource, kCFRunLoopDefaultMode);
		CFRelease(_runLoopSource);
	}
	if (_scDynStore) {
		CFRelease(_scDynStore);
	}
	// グローバル変数だがここで処理（AppControlは唯一なので）
	gMyHostName = nil;
}

//*---------------------------------------------------------------------------*
#pragma mark - メッセージ送受信
//*---------------------------------------------------------------------------*

// 新規メッセージウィンドウ表示処理
- (IBAction)newMessage:(id)sender
{
	if (!NSApp.isActive) {
		self.activatedFlag = _ACTIVATED_INIT;		// アクティベートで新規ウィンドウが開いてしまうのを抑止
		[NSApp activateIgnoringOtherApps:YES];
	}
	(void)[[SendControl alloc] initWithSendMessage:nil recvMessage:nil];
}

// メッセージ受信時処理
- (void)receiveMessage:(RecvMessage*)msg
{
	// 表示中のウィンドウがある場合無視する
	for (NSWindow* window in NSApp.orderedWindows) {
		if ([window.delegate isKindOfClass:ReceiveControl.class]) {
			if ([((ReceiveControl*)window.delegate).recvMsg isEqual:msg]) {
				WRN(@"already visible message.(%@)", msg);
				return;
			}
		}
	}
	Config*	config = Config.sharedConfig;
	// 受信音再生
	[config.receiveSound play];
	// 受信ウィンドウ生成（まだ表示しない）
	ReceiveControl*	recv = [[ReceiveControl alloc] initWithRecvMessage:msg];
	if (config.nonPopup) {
		if ((config.nonPopupWhenAbsence && config.inAbsence) ||
			(!config.nonPopupWhenAbsence)) {
			// ノンポップアップの場合受信キューに追加
			@synchronized(self.receiveQueue) {
				[self.receiveQueue addObject:recv];
			}
			switch (config.iconBoundModeInNonPopup) {
			case IPMSG_BOUND_ONECE:
				[NSApp requestUserAttention:NSInformationalRequest];
				break;
			case IPMSG_BOUND_REPEAT:
				[NSApp requestUserAttention:NSCriticalRequest];
				break;
			case IPMSG_BOUND_NONE:
			default:
				break;
			}
			if (!self.iconToggleTimer) {
				// アイコントグル開始
				// AppControlはアプリ生存中ずっと存在するためselfを直接キャプチャして問題ない
				// 循環参照はshowWindow:側のinvalidate呼び出しで解消する
				__block BOOL toggleState = YES;
				self.iconToggleTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
																	   repeats:YES
																		 block:^(NSTimer* _Nonnull timer) {
					// アイコントグル処理
					toggleState = !toggleState;
					NSImage* img1 = (toggleState) ? self.iconNormal : self.iconNormalReverse;
					NSImage* img2 = (toggleState) ? self.iconSmallNormal : self.iconSmallNormalReverse;
					if (config.inAbsence) {
						img1 = (toggleState) ? self.iconAbsence : self.iconAbsenceReverse;
						img2 = (toggleState) ? self.iconSmallAbsence : self.iconSmallAbsenceReverse;
					}
					// ステータスバーアイコン
					if (config.useStatusBar) {
						if (!self.statusBarItem) {
							[self initStatusBar];
						}
						self.statusBarItem.button.image = img2;
					}
					// Dockアイコン
					[NSApp setApplicationIconImage:img1];
				}];
			}
			return;
		}
	}
	if (!NSApp.isActive) {
		[NSApp activateIgnoringOtherApps:YES];
	}
	[recv showWindow];
}

// すべてのウィンドウを閉じる
- (IBAction)closeAllWindows:(id)sender
{
	for (NSWindow* window in NSApp.orderedWindows) {
		if (window.visible) {
			[window performClose:self];
		}
	}
}

// すべての通知ダイアログを閉じる
- (IBAction)closeAllDialogs:(id)sender
{
	for (NSWindow* window in NSApp.orderedWindows) {
		if ([window.delegate isKindOfClass:NoticeControl.class]) {
			[window performClose:self];
		}
	}
}

- (IBAction)showNonPopupMessage:(id)sender {
	[self applicationShouldHandleReopen:NSApp hasVisibleWindows:NO];
}

//*---------------------------------------------------------------------------*
#pragma mark - 不在関連
//*---------------------------------------------------------------------------*

// 不在メニュー選択ハンドラ
- (IBAction)absenceMenuChanged:(id)sender
{
	Config*		config	= Config.sharedConfig;
	NSInteger	oldIdx	= config.absenceIndex;
	NSInteger	newIdx;

	if ([sender tag] == ABSENCE_OFF_MENU_TAG) {
		newIdx = -2;
	} else {
		newIdx = [sender tag] - ABSENCE_ITEM_MENU_TAG;
	}

	// 現在選択されている不在メニューのチェックを消す
	if (oldIdx == -1) {
		oldIdx = -2;
	}
    [self.absenceMenu				itemAtIndex:oldIdx + 2].state = NSControlStateValueOff;
    [self.absenceMenuForDock		itemAtIndex:oldIdx + 2].state = NSControlStateValueOff;
    [self.absenceMenuForStatusBar	itemAtIndex:oldIdx + 2].state = NSControlStateValueOff;

	// 選択された項目にチェックを入れる
    [self.absenceMenu				itemAtIndex:newIdx + 2].state = NSControlStateValueOn;
    [self.absenceMenuForDock		itemAtIndex:newIdx + 2].state = NSControlStateValueOn;
    [self.absenceMenuForStatusBar	itemAtIndex:newIdx + 2].state = NSControlStateValueOn;

	// 選択された項目によってアイコンを変更する
	if (newIdx < 0) {
		NSApp.applicationIconImage	    = self.iconNormal;
		self.statusBarItem.button.image	= self.iconSmallNormal;
	} else {
		NSApp.applicationIconImage	    = self.iconAbsence;
		self.statusBarItem.button.image	= self.iconSmallAbsence;
	}

    [sender setState:NSControlStateValueOn];

	config.absenceIndex = newIdx;
	[MessageCenter.sharedCenter broadcastAbsence];
}

// 不在メニュー作成
- (void)buildAbsenceMenu
{
	Config*		config	= Config.sharedConfig;
	NSInteger	num		= config.numberOfAbsences;
	NSInteger	index	= config.absenceIndex;

	// 不在モード解除とその下のセパレータ以外を一旦削除
	for (NSInteger i = self.absenceMenu.numberOfItems - 1; i > 1 ; i--) {
		[self.absenceMenu removeItemAtIndex:i];
	}
	for (NSInteger i = self.absenceMenuForDock.numberOfItems - 1; i > 1 ; i--) {
		[self.absenceMenuForDock removeItemAtIndex:i];
	}
	for (NSInteger i = self.absenceMenuForStatusBar.numberOfItems - 1; i > 1 ; i--) {
		[self.absenceMenuForStatusBar removeItemAtIndex:i];
	}
	if (num > 0) {
		for (NSInteger i = 0; i < num; i++) {
			[self.absenceMenu addItem:[self createAbsenceMenuItemAtIndex:i state:(i == index)]];
			[self.absenceMenuForDock addItem:[self createAbsenceMenuItemAtIndex:i state:(i == index)]];
			[self.absenceMenuForStatusBar addItem:[self createAbsenceMenuItemAtIndex:i state:(i == index)]];
		}
	}
	self.absenceOffMenuItem.state				= (index == -1);
	self.absenceOffMenuItemForDock.state		= (index == -1);
	self.absenceOffMenuItemForStatusBar.state	= (index == -1);
	[self.absenceMenu update];
	[self.absenceMenuForDock update];
	[self.absenceMenuForStatusBar update];
}

// 不在解除
- (void)setAbsenceOff
{
	[self absenceMenuChanged:self.absenceOffMenuItem];
}

//*---------------------------------------------------------------------------*
#pragma mark - ステータスバー関連
//*---------------------------------------------------------------------------*

- (void)clickStatusBar:(id)sender
{
	self.activatedFlag = _ACTIVATED_INIT;		// アクティベートで新規ウィンドウが開いてしまうのを抑止
	[NSApp activateIgnoringOtherApps:YES];
	[self applicationShouldHandleReopen:NSApp hasVisibleWindows:NO];
}

- (void)initStatusBar
{
	if (!self.statusBarItem) {
		// ステータスバーアイテムの初期化
		self.statusBarItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
		self.statusBarItem.button.title		= @"";
		self.statusBarItem.button.image		= self.iconSmallNormal;
		self.statusBarItem.menu				= self.statusBarMenu;
	}
}

- (void)removeStatusBar
{
	if (self.statusBarItem) {
		// ステータスバーアイテムを破棄
		[NSStatusBar.systemStatusBar removeStatusItem:self.statusBarItem];
		self.statusBarItem = nil;
	}
}

//*---------------------------------------------------------------------------*
#pragma mark - その他
//*---------------------------------------------------------------------------*

// Webサイトに飛ぶ
- (IBAction)gotoHomePage:(id)sender
{
	NSURL* url = [NSURL URLWithString:NSLocalizedString(@"IPMsg.HomePage", nil)];
	[NSWorkspace.sharedWorkspace openURL:url];
}

// 謝辞の表示
- (IBAction)showAcknowledgement:(id)sender
{
	NSString* path = [[NSBundle mainBundle] pathForResource:@"Acknowledgement" ofType:@"pdf"];
	[NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:path]];
}

// ログ参照クリック時
- (void)openLog:(id)sender
{
	// ログファイルのフルパスを取得する
	NSString *filePath = [Config.sharedConfig.standardLogFile stringByExpandingTildeInPath];
	// デフォルトのアプリでログを開く
	[NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:filePath]];
}

// Sparkle 2 - 更新チェック
- (IBAction)checkForUpdates:(id)sender
{
	[self.updaterController checkForUpdates:sender];
}

//*---------------------------------------------------------------------------*
#pragma mark - 内部利用
//*---------------------------------------------------------------------------*

- (NSMenuItem*)createAbsenceMenuItemAtIndex:(NSInteger)index state:(BOOL)state
{
	NSMenuItem* item = [[NSMenuItem alloc] init];
	item.title		= [Config.sharedConfig absenceTitleAtIndex:index];
	item.enabled	= YES;
	item.state		= state;
	item.target		= self;
	item.action		= @selector(absenceMenuChanged:);
	item.tag		= ABSENCE_ITEM_MENU_TAG + index;
	return item;
}


//*---------------------------------------------------------------------------*
#pragma mark - NSObject
//*---------------------------------------------------------------------------*

// Nibファイルロード完了時
- (void)awakeFromNib
{
	Config* config = Config.sharedConfig;
	// メニュー設定
	self.sendWindowListUserMenuItem.state		= ![config sendWindowUserListColumnHidden:kIPMsgUserInfoUserNamePropertyIdentifier];
	self.sendWindowListGroupMenuItem.state		= ![config sendWindowUserListColumnHidden:kIPMsgUserInfoGroupNamePropertyIdentifier];
	self.sendWindowListHostMenuItem.state		= ![config sendWindowUserListColumnHidden:kIPMsgUserInfoHostNamePropertyIdentifier];
	self.sendWindowListIPAddressMenuItem.state	= ![config sendWindowUserListColumnHidden:kIPMsgUserInfoIPAddressPropertyIdentifier];
	self.sendWindowListLogonMenuItem.state		= ![config sendWindowUserListColumnHidden:kIPMsgUserInfoLogOnNamePropertyIdentifier];
	self.sendWindowListVersionMenuItem.state	= ![config sendWindowUserListColumnHidden:kIPMsgUserInfoVersionPropertyIdentifer];
	[self buildAbsenceMenu];

	// ステータスバー
	if (config.useStatusBar) {
		[self initStatusBar];
	}
}

// メニュー有効判定
- (BOOL)validateMenuItem:(NSMenuItem*)item
{
	if (item == self.showNonPopupMenuItem) {
		if (Config.sharedConfig.nonPopup) {
			return (self.receiveQueue.count > 0);
		}
		return NO;
	}
	return YES;
}

//*---------------------------------------------------------------------------*
#pragma mark - NSApplicationDelegate
//*---------------------------------------------------------------------------*

// アプリ起動完了時処理
- (void)applicationDidFinishLaunching:(NSNotification*)aNotification
{
	TRC(@"Enter");

	// DynamicStoreチェック
	if (!self.scDynStore) {
		// Dockアイコンバウンド
		[NSApp requestUserAttention:NSCriticalRequest];
		// エラーダイアログ表示
		NSAlert* alert = [[NSAlert alloc] init];
		alert.alertStyle		= NSAlertStyleCritical;
		alert.messageText		= NSLocalizedString(@"Err.DynStoreCreate.title", nil);
		alert.informativeText	= NSLocalizedString(@"Err.DynStoreCreate.title", nil);
		[alert runModal];
		// プログラム終了
		[NSApp terminate:self];
		return;
	}

	// DynamicStoreからの情報取得
	[self updateHostName];
	[self updateIPAddress];
	if (gMyIPAddress == 0) {
		// Dockアイコンバウンド
		[NSApp requestUserAttention:NSCriticalRequest];
		// エラーダイアログ表示
		NSAlert* alert = [[NSAlert alloc] init];
		alert.alertStyle		= NSAlertStyleCritical;
		alert.messageText		= NSLocalizedString(@"Err.NetCheck.title", nil);
		alert.informativeText	= NSLocalizedString(@"Err.NetCheck.msg", nil);
		[alert runModal];
	}

	// フラグ初期化
	self.activatedFlag = _ACTIVATED_INIT;

	// 送受信サーバの起動
	TRC(@"Start Messaging server");
	if (![MessageCenter.sharedCenter startupServer]) {
		ERR(@"Messageing server failed to startup.");
	}

	// ENTRYパケットのブロードキャスト
	TRC(@"Broadcast entry");
	[MessageCenter.sharedCenter broadcastEntry];

	TRC(@"Complete");
}

// アプリ終了前確認
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication*)sender
{
	// 表示されている受信ウィンドウがあれば終了確認
	for (NSWindow* window in NSApp.orderedWindows) {
		if (window.visible && [window.delegate isKindOfClass:ReceiveControl.class]) {
			NSAlert* alert = [[NSAlert alloc] init];
			alert.alertStyle		= NSAlertStyleCritical;
			alert.messageText		= NSLocalizedString(@"ShutDown.Confirm1.Title", nil);
			alert.informativeText	= NSLocalizedString(@"ShutDown.Confirm1.Msg", nil);
			[alert addButtonWithTitle:NSLocalizedString(@"ShutDown.Confirm1.OK", nil)];
			[alert addButtonWithTitle:NSLocalizedString(@"ShutDown.Confirm1.Cancel", nil)];
			NSModalResponse ret = [alert runModal];
			if (ret == NSAlertSecondButtonReturn) {
				[window makeKeyAndOrderFront:self];
				// 終了キャンセル
				return NSTerminateCancel;
			}
			break;
		}
	}
	// ノンポップアップの未読メッセージがあれば終了確認
	@synchronized (self.receiveQueue) {
		if (self.receiveQueue.count > 0) {
			NSAlert* alert = [[NSAlert alloc] init];
			alert.alertStyle		= NSAlertStyleCritical;
			alert.messageText		= NSLocalizedString(@"ShutDown.Confirm2.Title", nil);
			alert.informativeText	= NSLocalizedString(@"ShutDown.Confirm2.Msg", nil);
			[alert addButtonWithTitle:NSLocalizedString(@"ShutDown.Confirm2.OK", nil)];
			[alert addButtonWithTitle:NSLocalizedString(@"ShutDown.Confirm2.Other", nil)];
			[alert addButtonWithTitle:NSLocalizedString(@"ShutDown.Confirm2.Cancel", nil)];
			NSModalResponse ret = [alert runModal];
			if (ret == NSAlertThirdButtonReturn) {
				// 終了キャンセル
				return NSTerminateCancel;
			} else if (ret == NSAlertSecondButtonReturn) {
				[self applicationShouldHandleReopen:NSApp hasVisibleWindows:NO];
				// 終了キャンセル
				return NSTerminateCancel;
			}
		}
	}
	// 終了
	return NSTerminateNow;
}

// アプリ終了時処理
- (void)applicationWillTerminate:(NSNotification*)aNotification
{
	Config*			cfg	= Config.sharedConfig;
	MessageCenter*	mc	= MessageCenter.sharedCenter;

	// EXITパケットのブロードキャスト
	[mc broadcastExit];

	// ステータスバー消去
	if (cfg.useStatusBar && (self.statusBarItem != nil)) {
		// [self removeStatusBar]を呼ぶと落ちる（なぜ？）
		[NSStatusBar.systemStatusBar removeStatusItem:self.statusBarItem];
	}

	// 初期設定の保存
	[cfg save];

	// 送受信サーバの終了
	[mc shutdownServer];
}

// アプリアクティベート
- (void)applicationDidBecomeActive:(NSNotification*)aNotification
{
	// 初回だけは無視（起動時のアクティベートがあるので）
	self.activatedFlag = (self.activatedFlag == _ACTIVATED_INIT) ? _ACTIVATED_NO : _ACTIVATED_YES;
}

// Dockファイルドロップ時
- (BOOL)application:(NSApplication*)theApplication openFile:(NSString*)fileName
{
	DBG(@"drop file=%@", fileName);
	if (self.lastDockDraggedDate) {
		if (self.lastDockDraggedDate.timeIntervalSinceNow > -0.5) {
			if (self.lastDockDraggedWindow) {
				[self.lastDockDraggedWindow appendAttachmentByPath:fileName];
			} else {
				self.lastDockDraggedDate = nil;
			}
		} else {
			self.lastDockDraggedDate	= nil;
			self.lastDockDraggedWindow	= nil;
		}
	}
	if (!self.lastDockDraggedDate) {
		// strongな一時変数で保持してからweakプロパティに代入（ARC警告回避）
		SendControl* sendCtrl = [[SendControl alloc] initWithSendMessage:nil recvMessage:nil];
		self.lastDockDraggedWindow = sendCtrl;
		[sendCtrl appendAttachmentByPath:fileName];
		self.lastDockDraggedDate = [NSDate date];
	}
	return YES;
}

// Dockクリック時
- (BOOL)applicationShouldHandleReopen:(NSApplication*)theApplication hasVisibleWindows:(BOOL)flag
{
	BOOL	showPopup	= NO;
	Config*	config		= Config.sharedConfig;
	// ノンポップアップのキューにメッセージがあれば表示
	@synchronized (self.receiveQueue) {
		showPopup = (self.receiveQueue.count > 0);
		for (ReceiveControl* recvCtrl in self.receiveQueue) {
			[recvCtrl showWindow];
		}
		[self.receiveQueue removeAllObjects];
	}
	// アイコントグルアニメーションストップ
	if (showPopup && self.iconToggleTimer) {
		[self.iconToggleTimer invalidate];
		self.iconToggleTimer = nil;
		[NSApp setApplicationIconImage:((config.inAbsence) ? self.iconAbsence : self.iconNormal)];
		self.statusBarItem.button.image = (config.inAbsence) ? self.iconSmallAbsence : self.iconSmallNormal;
	}
	// 新規送信ウィンドウのオープン
	BOOL noWin = YES;
	for (NSWindow* window in NSApp.windows) {
		if (window.visible) {
			noWin = NO;
			break;
		}
	}
	if (self.activatedFlag != _ACTIVATED_INIT) {
		if ((noWin || (self.activatedFlag == _ACTIVATED_NO)) && !showPopup && config.openNewOnDockClick) {
			// ・クリック前からアクティブアプリだったか、または表示中のウィンドウが一個もない
			// ・環境設定で指定されている
			// ・ノンポップアップ受信でキューイングされた受信ウィンドウがない
			// のすべてを満たす場合、新規送信ウィンドウを開く
			[self newMessage:self];
		}
	}
	self.activatedFlag = _ACTIVATED_NO;
	return YES;
}

//*---------------------------------------------------------------------------*
#pragma mark - DynamicStore関連
//*---------------------------------------------------------------------------*

- (BOOL)updateHostName
{
	NSDictionary* newVal = (__bridge_transfer NSDictionary*)SCDynamicStoreCopyValue(self.scDynStore, (__bridge CFStringRef)self.scKeyHostName);
	if (newVal) {
		NSString* newName = newVal[(NSString*)kSCPropNetLocalHostName];
		if (newName) {
			if (![newName isEqualToString:gMyHostName]) {
				gMyHostName = [newName copy];
				return YES;
			}
		}
	}
	return NO;
}

- (_NetUpdateState)updateIPAddress
{
	// PrimaryNetworkInterface更新
	_NetUpdateState	state = [self updatePrimaryNIC];
	switch (state) {
	case _NET_LINK_LOST:
		// クリアして復帰
		self.scKeyIFIPv4 = nil;
		gMyIPAddress = 0;
		return _NET_LINK_LOST;
	case _NET_NO_CHANGE_IN_UNLINK:
		// 変更はないがリンクしていないので復帰
		return _NET_NO_CHANGE_IN_UNLINK;
	case _NET_NO_CHANGE_IN_LINK:
		// 変更はないのでクリアせずに進む
		// (先での変更の可能性があるため）
		break;
	case _NET_LINK_GAINED:
	case _NET_PRIMARY_IF_CHANGED:
		// リンクの検出またはNICの切り替えが発生したので一度クリアする
		self.scKeyIFIPv4 = nil;
		gMyIPAddress = 0;
		break;
	default:
		ERR(@"Invalid change status(%ld)", state);
		self.scKeyIFIPv4 = nil;
		gMyIPAddress = 0;
		if (!self.primaryNIC) {
			// リンク消失扱いにして復帰
			return _NET_LINK_LOST;
		} else {
			// 一応NICが変わったものとして扱う
			state = _NET_PRIMARY_IF_CHANGED;
		}
		break;
	}

	// State:/Network/Interface/<PrimaryNetworkInterface>/IPv4 キー編集
	if (!self.scKeyIFIPv4) {
		CFStringRef key = SCDynamicStoreKeyCreateNetworkInterfaceEntity(NULL,
																		kSCDynamicStoreDomainState,
																		(__bridge CFStringRef)self.primaryNIC,
																		kSCEntNetIPv4);
		if (!key) {
			// 内部エラー
			ERR(@"Edit Key error (if=%@)", self.primaryNIC);
			self.primaryNIC	= nil;
			gMyIPAddress = 0;
			return _NET_LINK_LOST;
		}
		self.scKeyIFIPv4 = (__bridge_transfer NSString*)key;
	}

	// State:/Network/Interface/<PrimaryNetworkInterface>/IPv4 取得
	CFDictionaryRef	value = (CFDictionaryRef)SCDynamicStoreCopyValue(self.scDynStore, (__bridge CFStringRef)self.scKeyIFIPv4);
	if (!value) {
		// 値なし（ありえないはず）
		ERR(@"value get error (%@)", self.scKeyIFIPv4);
		self.primaryNIC	= nil;
		self.scKeyIFIPv4 = nil;
		gMyIPAddress = 0;
		return _NET_LINK_LOST;
	}

	// Addressesプロパティ取得
	CFArrayRef addrs = (CFArrayRef)CFDictionaryGetValue(value, kSCPropNetIPv4Addresses);
	if (!addrs) {
		// プロパティなし
		ERR(@"prop get error (%@ in %@)", (NSString*)kSCPropNetIPv4Addresses, self.scKeyIFIPv4);
		CFRelease(value);
		self.primaryNIC	= nil;
		self.scKeyIFIPv4 = nil;
		gMyIPAddress = 0;
		return _NET_LINK_LOST;
	}

	// IPアドレス([0])取得
	NSString* addr = (__bridge NSString*)CFArrayGetValueAtIndex(addrs, 0);
	if (!addr) {
		ERR(@"[0] not exist (in %@)", (NSString*)kSCPropNetIPv4Addresses);
		CFRelease(value);
		self.primaryNIC	= nil;
		self.scKeyIFIPv4 = nil;
		gMyIPAddress = 0;
		return _NET_LINK_LOST;
	}

	struct in_addr inAddr;
	if (inet_aton(addr.UTF8String, &inAddr) == 0) {
		ERR(@"IP Address format error(%@)", addr);
		CFRelease(value);
		self.primaryNIC	= nil;
		self.scKeyIFIPv4 = nil;
		gMyIPAddress = 0;
		return _NET_LINK_LOST;
	}

#ifdef IPMSG_DEBUG
	unsigned long oldAddr = gMyIPAddress;
#endif
	unsigned long newAddr = ntohl(inAddr.s_addr);

	CFRelease(value);

	if (gMyIPAddress != newAddr) {
		DBG(@"IPAddress changed (%lu.%lu.%lu.%lu -> %lu.%lu.%lu.%lu)",
			((oldAddr >> 24) & 0x00FF), ((oldAddr >> 16) & 0x00FF),
			((oldAddr >> 8) & 0x00FF), (oldAddr & 0x00FF),
			((newAddr >> 24) & 0x00FF), ((newAddr >> 16) & 0x00FF),
			((newAddr >> 8) & 0x00FF), (newAddr & 0x00FF));
		gMyIPAddress = (UInt32)newAddr;
		// ステータスチェック（必要に応じて変更）
		switch (state) {
		case _NET_LINK_GAINED:
		case _NET_PRIMARY_IF_CHANGED:
			// そのまま（より大きな変更なので）
			break;
		case _NET_NO_CHANGE_IN_LINK:
		default:
			// IPアドレスは変更になったのでステータス変更
			state = _NET_IP_ADDRESS_CHANGED;
			break;
		}
	}

	return state;
}

- (_NetUpdateState)updatePrimaryNIC
{
	// State:/Network/Global/IPv4 を取得
	CFDictionaryRef	value = (CFDictionaryRef)SCDynamicStoreCopyValue(self.scDynStore, (__bridge CFStringRef)self.scKeyNetIPv4);
	if (!value) {
		// キー自体がないのは、すべてのネットワークI/FがUnlink状態
		if (self.primaryNIC) {
			// いままではあったのに無くなった
			DBG(@"All Network I/F becomes unlinked(%@)", self.primaryNIC);
			self.primaryNIC = nil;
			return _NET_LINK_LOST;
		}
		// もともと無いので変化なし
		return _NET_NO_CHANGE_IN_UNLINK;
	}

	// PrimaryNetwork プロパティを取得
	CFStringRef primaryIF = (CFStringRef)CFDictionaryGetValue(value, kSCDynamicStorePropNetPrimaryInterface);
	if (!primaryIF) {
		// この状況が発生するのか不明（ありえないと思われる）
		ERR(@"Not exist prop %@", kSCDynamicStorePropNetPrimaryInterface);
		CFRelease(value);
		if (self.primaryNIC) {
			// いままではあったのに無くなった
			DBG(@"All Network I/F becomes unlinked(%@)", self.primaryNIC);
			self.primaryNIC = nil;
			return _NET_LINK_LOST;
		}
		// もともと無いので変化なし
		return _NET_NO_CHANGE_IN_UNLINK;
	}

	NSString* newNIC = (__bridge NSString*)primaryIF;	// ARCがretainする前にCFReleaseしないよう先に代入

	CFRelease(value);

	if (!self.primaryNIC) {
		// ネットワークが無い状態からある状態になった
		self.primaryNIC = newNIC;
		DBG(@"A Network I/F becomes linked(%@)", newNIC);
		return _NET_LINK_GAINED;
	}

	if (![self.primaryNIC isEqualToString:newNIC]) {
		// 既にあるが変わった
		DBG(@"Primary Network I/F changed(%@ -> %@)", self.primaryNIC, newNIC);
		self.primaryNIC = newNIC;
		return _NET_PRIMARY_IF_CHANGED;
	}

	return _NET_NO_CHANGE_IN_LINK;
}

@end

//*---------------------------------------------------------------------------*
#pragma mark - グローバル関数
//*---------------------------------------------------------------------------*

// ホスト名を返す
NSString* AppControlGetHostName(void)
{
	// 書き込みはメインスレッドのみなので、バックグラウンドスレッドからの
	// 読み取りはメインスレッドに委譲してスレッドセーフにする
	if ([NSThread isMainThread]) {
		return gMyHostName;
	}
	__block NSString* result;
	dispatch_sync(dispatch_get_main_queue(), ^{
		result = gMyHostName;
	});
	return result;
}

// IPアドレスを返す
UInt32 AppControlGetIPAddress(void)
{
	// 書き込みはメインスレッドのみなので、バックグラウンドスレッドからの
	// 読み取りはメインスレッドに委譲してスレッドセーフにする
	if ([NSThread isMainThread]) {
		return gMyIPAddress;
	}
	__block UInt32 result;
	dispatch_sync(dispatch_get_main_queue(), ^{
		result = gMyIPAddress;
	});
	return result;
}

//*---------------------------------------------------------------------------*
#pragma mark - ローカル関数
//*---------------------------------------------------------------------------*

// DynamicStoreコールバック
void _DynamicStoreCallback(SCDynamicStoreRef	store,
						   CFArrayRef			changedKeys,
						   void*				info)
{
	AppControl*				appControl	= (__bridge AppControl*)info;
	MessageCenter*			msgCenter	= MessageCenter.sharedCenter;
	NSNotificationCenter*	ntcCenter	= NSNotificationCenter.defaultCenter;
	UserManager*			userMng		= UserManager.sharedManager;
	NSArray<NSString*>*		keys		= (__bridge NSArray<NSString*>*)changedKeys;
	for (NSString* key in keys) {
		if ([key isEqualToString:appControl.scKeyNetIPv4]) {
			DBG(@"<SC>NetIFStatus changed (key:%@)", key);
			_NetUpdateState	ret	= [appControl updateIPAddress];
			switch (ret) {
			case _NET_NO_CHANGE_IN_LINK:
				// なにもしない
				DBG(@" no effects (in link status)");
				break;
			case _NET_NO_CHANGE_IN_UNLINK:
				// なにもしない
				DBG(@" no effects (in unlink status)");
				break;
			case _NET_PRIMARY_IF_CHANGED:
				// NICが切り替わったたのでユーザリストを更新する
				DBG(@" NIC Changed -> Referesh UserList");
				[userMng removeAllUsers];
				[msgCenter broadcastEntry];
				break;
			case _NET_IP_ADDRESS_CHANGED:
				// IPに変更があったのでユーザリストを更新する
				DBG(@" IPAddress Changed -> Referesh UserList");
				[userMng removeAllUsers];
				[msgCenter broadcastEntry];
				break;
			case _NET_LINK_GAINED:
				// ネットワーク環境に繋がったので通知してユーザリストを更新する
				DBG(@" Network Gained -> Referesh UserList");
				[ntcCenter postNotificationName:kIPMsgNetworkGainedNotification object:nil];
				[msgCenter broadcastEntry];
				break;
			case _NET_LINK_LOST:
				// つながっていたが接続がなくなったので通知
				DBG(@" Network Lost -> Remove Users");
				[ntcCenter postNotificationName:kIPMsgNetworkLostNotification object:nil];
				[userMng removeAllUsers];
				break;
			default:
				ERR(@" Unknown Status(%ld)", ret);
				break;
			}
		} else if ([key isEqualToString:appControl.scKeyHostName]) {
			if ([appControl updateHostName]) {
				DBG(@"<SC>HostName changed (key:%@)", key);
				[ntcCenter postNotificationName:kIPMsgHostNameChangedNotification object:nil];
				[msgCenter broadcastAbsence];
			}
		} else {
			DBG(@"<SC>No action defined for key:%@", key);
		}
	}
}
