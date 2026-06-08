/*============================================================================*
 * (C) 2001-2026 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for macOS
 *	File		: NoticeControl.m
 *	Module		: 通知ダイアログコントローラ
 *============================================================================*/

#import "NoticeControl.h"

/*============================================================================*
 * 内部変数
 *============================================================================*/

// 表示中の通知ダイアログコントローラを保持するセット。
// ARC環境では生成元（MessageCenter）が本オブジェクトへの参照を保持しないため、
// ウィンドウを閉じるまでここで自己保持しておかないと、生成直後に解放されて
// 表示アニメーション中のウィンドウが破棄され、過剰解放でクラッシュする。
static NSMutableSet<NoticeControl*>*	_activeControls	= nil;

/*============================================================================*
 * クラス実装
 *============================================================================*/

@implementation NoticeControl

// 初期化
- (instancetype)initWithTitle:(NSString*)title message:(NSString*)msg date:(NSDate*)date
{
	self = [super init];
	if (self) {
		// nibファイルロード
		if (![NSBundle.mainBundle loadNibNamed:@"NoticeDialog"
										 owner:self
							   topLevelObjects:nil]) {
			return nil;
		}

		if (!date) {
			date = [NSDate date];
		}

		// 表示文字列設定
		_titleLabel.stringValue		= title;
		_messageLabel.stringValue	= msg;
		_dateLabel.objectValue		= date;

		// 画面表示位置計算
		NSSize	screenSize = NSScreen.mainScreen.visibleFrame.size;
		NSRect	windowRect = _window.frame;
		NSPoint	centerPoint;
		int		sw, sh, ww, wh;
		sw	= screenSize.width;
		sh	= screenSize.height;
		ww	= windowRect.size.width;
		wh	= windowRect.size.height;
		centerPoint.x = (sw - ww) / 2 + (arc4random_uniform(INT32_MAX) % (sw / 4)) - sw / 8;
		centerPoint.y = (sh - wh) / 2 + (arc4random_uniform(INT32_MAX) % (sh / 4)) - sh / 8;

		_window.frameOrigin	= centerPoint;

		// ウィンドウメニューから除外
		_window.excludedFromWindowsMenu	= YES;

		// ダイアログ表示
		[_window makeKeyAndOrderFront:self];

		// ウィンドウを閉じるまで自身を保持する（過剰解放によるクラッシュ防止）
		static dispatch_once_t onceToken;
		dispatch_once(&onceToken, ^{
			_activeControls = [[NSMutableSet alloc] init];
		});
		[_activeControls addObject:self];
	}

	return self;
}

// ウィンドウクローズ時
- (void)windowWillClose:(NSNotification*)notification
{
	// クローズ処理の途中で解放されないよう、次のランループで保持を解除する。
	// （ブロックが self を捕捉している間は解放されない）
	dispatch_async(dispatch_get_main_queue(), ^{
		[_activeControls removeObject:self];
	});
}

@end
