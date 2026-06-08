/*============================================================================*
 * (C) 2001-2026 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for macOS
 *	File		: RefuseInfo.m
 *	Module		: 通知拒否条件情報クラス
 *============================================================================*/

#import "RefuseInfo.h"
#import "UserInfo.h"
#import "DebugLog.h"

/*============================================================================*
 * クラス実装
 *============================================================================*/

@implementation RefuseInfo

/*----------------------------------------------------------------------------*
 * ファクトリ
 *----------------------------------------------------------------------------*/
+ (instancetype)refuseInfoWithTarget:(IPRefuseTarget)aTarget
							  string:(NSString*)aString
						   condition:(IPRefuseCondition)aCondition
{
	return [[RefuseInfo alloc] initWithTarget:aTarget
									string:aString
								 condition:aCondition];
}

/*----------------------------------------------------------------------------*
 * 初期化／解放
 *----------------------------------------------------------------------------*/

// 初期化
- (instancetype)initWithTarget:(IPRefuseTarget)aTarget
						string:(NSString*)aString
					 condition:(IPRefuseCondition)aCondition
{
	self = [super init];
	if (self) {
		_target		= aTarget;
		_string		= [aString copy];
		_condition	= aCondition;
	}
	return self;
}

/*----------------------------------------------------------------------------*
 * 判定
 *----------------------------------------------------------------------------*/

- (BOOL)match:(UserInfo*)user
{
	NSString* targetStr	= nil;
	switch (self.target) {
	case IP_REFUSE_USER:	targetStr = user.userName;		break;
	case IP_REFUSE_GROUP:	targetStr = user.groupName;		break;
	case IP_REFUSE_MACHINE:	targetStr = user.hostName;		break;
	case IP_REFUSE_LOGON:	targetStr = user.logOnName;		break;
	case IP_REFUSE_ADDRESS:	targetStr = user.ipAddress;		break;
	default:
		WRN(@"invalid refuse target(%ld)", self.target);
		return NO;
	}
	switch (self.condition) {
	case IP_REFUSE_MATCH:
		return [targetStr isEqualToString:self.string];
	case IP_REFUSE_CONTAIN:
		return ([targetStr rangeOfString:self.string].location != NSNotFound);
	case IP_REFUSE_START:
		{
			NSUInteger len1 = targetStr.length;
			NSUInteger len2 = self.string.length;
			if (len1 > len2) {
				return [[targetStr substringToIndex:(len2)] isEqualToString:self.string];
			} else if (len1 == len2) {
				return [targetStr isEqualToString:self.string];
			}
		}
		break;
	case IP_REFUSE_END:
		{
			NSUInteger len1 = targetStr.length;
			NSUInteger len2 = self.string.length;
			if (len1 > len2) {
				return [[targetStr substringFromIndex:(len1 - len2)] isEqualToString:self.string];
			} else if (len1 == len2) {
				return [targetStr isEqualToString:self.string];
			}
		}
		break;
	default:
		WRN(@"invalid refuse condition(%ld)", self.condition);
		break;
	}
	return NO;
}

/*----------------------------------------------------------------------------*
 * その他
 *----------------------------------------------------------------------------*/

/* コピー処理 （NSCopyingプロトコル） */
- (instancetype)copyWithZone:(NSZone*)zone
{
	RefuseInfo* newObj = [[RefuseInfo allocWithZone:zone] init];
	if (newObj) {
		newObj->_target		= self->_target;
		newObj->_string		= [self->_string copyWithZone:zone];
		newObj->_condition	= self->_condition;
	}
	return newObj;
}

// オブジェクト文字列表現
- (NSString*)description
{
	NSString* fmt = NSLocalizedString(@"Refuse.Description.Format", nil);

	NSString* tgtKey = @"";
	switch (self.target) {
	case IP_REFUSE_USER:	tgtKey = @"Refuse.Desc.Name";		break;
	case IP_REFUSE_GROUP:	tgtKey = @"Refuse.Desc.Group";		break;
	case IP_REFUSE_MACHINE:	tgtKey = @"Refuse.Desc.Machine";	break;
	case IP_REFUSE_LOGON:	tgtKey = @"Refuse.Desc.LogOn";		break;
	case IP_REFUSE_ADDRESS:	tgtKey = @"Refuse.Desc.IPAddress";	break;
	default:
		WRN(@"invalid refuse target(%ld)", self.target);
		break;
	}
	NSString* tgt = NSLocalizedString(tgtKey, nil);

	NSString* cndKey = @"";
	switch (self.condition) {
	case IP_REFUSE_MATCH:	cndKey = @"Refuse.Desc.Match";		break;
	case IP_REFUSE_CONTAIN:	cndKey = @"Refuse.Desc.Contain";	break;
	case IP_REFUSE_START:	cndKey = @"Refuse.Desc.Start";		break;
	case IP_REFUSE_END:		cndKey = @"Refuse.Desc.End";		break;
	default:
		WRN(@"invalid refuse condition(%ld)", self.condition);
		break;
	}
	NSString* cnd = NSLocalizedString(cndKey, nil);

	return [NSString stringWithFormat:fmt, tgt, self.string, cnd];
}

@end
