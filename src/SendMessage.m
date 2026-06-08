/*============================================================================*
 * (C) 2001-2019 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for macOS
 *	File		: SendMessage.m
 *	Module		: 送信メッセージ情報クラス
 *============================================================================*/

#import "SendMessage.h"
#import "MessageCenter.h"
#import "DebugLog.h"

// クラス実装
@implementation SendMessage

/*============================================================================*
 * その他
 *============================================================================*/

// オブジェクト文字列表現
- (NSString*)description
{
	return [NSString stringWithFormat:@"SendMessage:PacketNo=%ld", self.packetNo];
}

@end
