/*============================================================================*
 * (C) 2001-2026 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for macOS
 *	File		: UserInfo.h
 *	Module		: ユーザ情報クラス
 *============================================================================*/

#import <Foundation/Foundation.h>
#import <netinet/in.h>

@class CryptoCapability;
@class RSAPublicKey;

/*============================================================================*
 * プロパティ識別定義
 *============================================================================*/

extern NSString * _Nonnull const kIPMsgUserInfoUserNamePropertyIdentifier;
extern NSString * _Nonnull const kIPMsgUserInfoGroupNamePropertyIdentifier;
extern NSString * _Nonnull const kIPMsgUserInfoHostNamePropertyIdentifier;
extern NSString * _Nonnull const kIPMsgUserInfoLogOnNamePropertyIdentifier;
extern NSString * _Nonnull const kIPMsgUserInfoIPAddressPropertyIdentifier;
extern NSString * _Nonnull const kIPMsgUserInfoVersionPropertyIdentifer;

/*============================================================================*
 * クラス定義
 *============================================================================*/

NS_ASSUME_NONNULL_BEGIN

@interface UserInfo : NSObject

@property(readonly)	NSString*				    hostName;			// マシン名
@property(readonly)	NSString*				    logOnName;			// ログインユーザ名
@property(readonly)	NSData*					    fingerPrint;		// 公開鍵指紋
@property(readonly)	struct sockaddr_in		    address;			// 接続アドレス
@property(readonly)	NSString*				    ipAddress;			// IPアドレス（文字列）

@property(copy)		NSString*					userName;			// IPMsgユーザ名（ニックネーム）
@property(copy)		NSString*					groupName;			// IPMsgグループ名
@property(copy)		NSString*					version;			// バージョン情報
@property(assign)	BOOL						inAbsence;			// 不在
@property(assign)	BOOL						dialupConnect;		// ダイアルアップ接続
@property(assign)	BOOL						supportsAttachment;	// ファイル添付サポート
@property(assign)	BOOL						supportsEncrypt;	// 暗号化サポート
@property(assign)	BOOL						supportsEncExtMsg;	// メッセージ拡張部暗号化サポート
@property(strong, nullable)	CryptoCapability*	cryptoCapability;	// 暗号化能力
@property(strong, nullable)	RSAPublicKey*		publicKey;			// 公開鍵
@property(assign)	BOOL						supportsUTF8;		// UTF-8サポート

@property(readonly)	NSString*					summaryString;		// 表示用文字列

// ファクトリ
+ (instancetype)userWithHostName:(NSString*)host
					   logOnName:(NSString*)logOn
						 address:(struct sockaddr_in*)addr;

// 初期化
- (instancetype)initWithHostName:(NSString*)host
					   logOnName:(NSString*)logOn
						 address:(struct sockaddr_in*)addr;

@end

NS_ASSUME_NONNULL_END
