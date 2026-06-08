/*============================================================================*
 * (C) 2001-2026 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for macOS
 *	File		: RecvMessage.h
 *	Module		: 受信メッセージクラス
 *============================================================================*/

#import <Foundation/Foundation.h>

@class UserInfo;
@class RecvFile;
@class RecvClipboard;

/*============================================================================*
 * クラス定義
 *============================================================================*/

NS_ASSUME_NONNULL_BEGIN

@interface RecvMessage : NSObject

@property(assign)	NSInteger					packetNo;		// パケット番号
@property(copy)		NSDate*						receiveDate;	// 受信日時
@property(strong)	UserInfo*					fromUser;		// 送信元ユーザ
@property(copy)		NSString*					message;		// メッセージ本文
@property(assign)	NSInteger					secureLevel;	// 暗号化レベル
@property(assign)	BOOL						doubt;			// 偽装メッセージの疑い
@property(assign)	BOOL						sealed;			// 封書付きメッセージ
@property(assign)	BOOL						locked;			// 鍵付きメッセージ
@property(assign)	BOOL						multicast;		// マルチキャスト
@property(assign)	BOOL						broadcast;		// 一斉通報
@property(assign)	BOOL						absence;		// 不在モード中
@property(strong)	NSArray<RecvFile*>*			attachments;	// 添付ファイル
@property(strong)	NSArray<RecvClipboard*>*	clipboards;		// 埋め込みクリップボード
@property(assign)	BOOL						needLog;		// ログ保存要否

// その他
- (void)removeDownloadedAttachments;

@end

NS_ASSUME_NONNULL_END
