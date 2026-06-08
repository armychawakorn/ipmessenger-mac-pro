/*============================================================================*
 * (C) 2001-2026 G.Ishiwata, All Rights Reserved.
 *
 *	Project		: IP Messenger for macOS
 *	File		: SendMessageView.m
 *	Module		: 送信メッセージ表示View
 *============================================================================*/

#import "SendMessageView.h"
#import "MessageCenter.h"
#import "SendControl.h"
#import "DebugLog.h"

@interface IPMsgTextAttachment : NSTextAttachment
@property (nonatomic, copy) NSString *filePath;
@end

@implementation IPMsgTextAttachment
@end

@interface SendMessageView()

@property(assign)	BOOL	duringDragging;

@end

@implementation SendMessageView

- (instancetype)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self) {
		[self setRichText:YES];
		[self setImportsGraphics:YES];
		// ファイルのドラッグを受け付ける
		if (MessageCenter.isAttachmentAvailable) {
			[self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
		}
	}
	return self;
}

/*----------------------------------------------------------------------------*
 * ファイルドロップ処理（添付ファイル）
 *----------------------------------------------------------------------------*/

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender
{
	if (!MessageCenter.isAttachmentAvailable) {
		return NSDragOperationNone;
	}
	self.duringDragging = YES;
	self.needsDisplay	= YES;

	return NSDragOperationGeneric;
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender
{
	if (!MessageCenter.isAttachmentAvailable) {
		return NSDragOperationNone;
	}
	return NSDragOperationGeneric;
}

- (void)draggingExited:(id<NSDraggingInfo>)sender
{
	if (!MessageCenter.isAttachmentAvailable) {
		return;
	}
	self.duringDragging = NO;
	self.needsDisplay	= YES;
}

- (void)drawRect:(NSRect)aRect
{
	[super drawRect:aRect];
	if (self.duringDragging) {
		[NSColor.selectedControlColor set];
		NSFrameRectWithWidth(self.visibleRect, 4.0);
	}
}

- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender
{
	return MessageCenter.isAttachmentAvailable;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender
{
	return MessageCenter.isAttachmentAvailable;
}

- (void)concludeDragOperation:(id<NSDraggingInfo>)sender
{
	NSPasteboard* 		pBoard	= [sender draggingPasteboard];
	NSArray<NSURL*>*	urls	= [pBoard readObjectsForClasses:@[NSURL.class]
								options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
	SendControl*		control	= (SendControl*)self.window.delegate;
	for (NSURL* url in urls) {
		[control appendAttachmentByPath:url.path];
	}
	self.duringDragging = NO;
	self.needsDisplay	= YES;
}

- (void)paste:(id)sender
{
	NSPasteboard *pboard = [NSPasteboard generalPasteboard];
	DBG(@"[IPMsgDebug] paste: method called. Types: %@", pboard.types);
	
	// 1. Handle image files copied from Finder (File URLs)
	NSArray<NSURL*>* urls = [pboard readObjectsForClasses:@[NSURL.class]
								options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
	if (urls.count > 0) {
		BOOL hasAttachedImage = NO;
		SendControl *control = (SendControl*)self.window.delegate;
		for (NSURL *url in urls) {
			NSString *ext = [url.pathExtension lowercaseString];
			if ([@[@"png", @"jpg", @"jpeg", @"gif", @"tiff", @"bmp", @"heic"] containsObject:ext]) {
				DBG(@"[IPMsgDebug] Pasting image file from Finder: %@", url.path);
				if ([control respondsToSelector:@selector(appendAttachmentByPath:)]) {
					[control appendAttachmentByPath:url.path];
					
					// Insert image inline into text area
					NSImage *image = [[NSImage alloc] initWithContentsOfFile:url.path];
					if (image) {
						IPMsgTextAttachment *attachment = [[IPMsgTextAttachment alloc] init];
						attachment.image = image;
						attachment.filePath = url.path;
						CGFloat maxWidth = 120.0;
						CGFloat ratio = image.size.height / image.size.width;
						attachment.bounds = CGRectMake(0, 0, maxWidth, maxWidth * ratio);
						
						NSAttributedString *attrString = [NSAttributedString attributedStringWithAttachment:attachment];
						[self.textStorage insertAttributedString:attrString atIndex:self.selectedRange.location];
						self.selectedRange = NSMakeRange(self.selectedRange.location + 1, 0);
					}
					hasAttachedImage = YES;
				}
			}
		}
		if (hasAttachedImage) {
			return; // Stop processing further paste operations
		}
	}
	
	// 2. Handle raw clipboard images (e.g. screenshots, copied web images)
	if ([pboard canReadObjectForClasses:@[[NSImage class]] options:nil]) {
		NSArray *objects = [pboard readObjectsForClasses:@[[NSImage class]] options:nil];
		if (objects.count > 0) {
			NSImage *image = objects[0];
			DBG(@"[IPMsgDebug] Pasting raw image from clipboard: %@", image);
			
			// Convert NSImage to PNG data
			NSData *imageData = [image TIFFRepresentation];
			NSBitmapImageRep *imageRep = [NSBitmapImageRep imageRepWithData:imageData];
			NSData *pngData = [imageRep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
			
			if (pngData) {
				// Create a temporary file path
				NSString *tempDir = NSTemporaryDirectory();
				NSString *fileName = [NSString stringWithFormat:@"pasted_image_%ld.png", (long)[[NSDate date] timeIntervalSince1970]];
				NSString *tempPath = [tempDir stringByAppendingPathComponent:fileName];
				
				// Save file to disk and attach to message
				if ([pngData writeToFile:tempPath atomically:YES]) {
					SendControl *control = (SendControl*)self.window.delegate;
					if ([control respondsToSelector:@selector(appendAttachmentByPath:)]) {
						[control appendAttachmentByPath:tempPath];
						
						// Insert image inline into text area
						IPMsgTextAttachment *attachment = [[IPMsgTextAttachment alloc] init];
						attachment.image = image;
						attachment.filePath = tempPath;
						CGFloat maxWidth = 120.0;
						CGFloat ratio = image.size.height / image.size.width;
						attachment.bounds = CGRectMake(0, 0, maxWidth, maxWidth * ratio);
						
						NSAttributedString *attrString = [NSAttributedString attributedStringWithAttachment:attachment];
						[self.textStorage insertAttributedString:attrString atIndex:self.selectedRange.location];
						self.selectedRange = NSMakeRange(self.selectedRange.location + 1, 0);
						
						return; // Stop default paste operation
					}
				}
			}
		}
	}
	
	// 3. Fallback to default NSTextView paste
	DBG(@"[IPMsgDebug] Falling back to default text paste");
	[super paste:sender];
}

- (void)didChangeText
{
	[super didChangeText];
	
	NSMutableSet<NSString*> *currentPaths = [NSMutableSet set];
	[self.textStorage enumerateAttribute:NSAttachmentAttributeName
								 inRange:NSMakeRange(0, self.textStorage.length)
								 options:0
							  usingBlock:^(id value, NSRange range, BOOL *stop) {
		if ([value isKindOfClass:[IPMsgTextAttachment class]]) {
			IPMsgTextAttachment *attach = (IPMsgTextAttachment *)value;
			if (attach.filePath) {
				[currentPaths addObject:attach.filePath];
			}
		}
	}];
	
	SendControl *control = (SendControl*)self.window.delegate;
	if ([control respondsToSelector:@selector(syncAttachmentsWithPaths:)]) {
		[control syncAttachmentsWithPaths:currentPaths];
	}
}

@end
