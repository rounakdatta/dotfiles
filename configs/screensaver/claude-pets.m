// Claude Pets screen saver
//
// The lock/idle-screen counterpart to the Hammerspoon desk-pet overlay. It
// reads the very same registry the overlay does — ~/.cache/claude-sessions,
// written by the claude-session-tracker hook (see configs/claude) — and draws
// the same two squads of Claude Code bots:
//
//   * WAITING (orange, across the top) — sessions needing you (attention/asking),
//     bobbing gently.
//   * WORKING (grey, down the left edge, vertically centered) — sessions
//     currently working, vibrating gently.
//
// It runs inside the sandboxed legacyScreenSaver host, whose NSHomeDirectory()
// is redirected to a container — so we resolve the REAL home via getpwuid() and
// read the registry by absolute path (the host carries broad file entitlements,
// confirmed to allow this).
//
// Nix bundles claudecode-color.png / claudecode-gray.png (shared with the
// Hammerspoon overlay) into Contents/Resources, loaded by name below.

#import <ScreenSaver/ScreenSaver.h>
#import <Cocoa/Cocoa.h>
#import <pwd.h>
#import <unistd.h>

static const NSTimeInterval kTTL = 28800;     // ignore sessions stale > 8h
static const CGFloat kWaitSize = 88;          // orange waiting bot (pt)
static const CGFloat kWorkSize = 58;          // grey working bot (pt)
static const CGFloat kGap = 20;               // space between bots
static const CGFloat kTopMargin = 80;         // waiting row gap below the top
static const CGFloat kLeftMargin = 80;        // working column gap from the left
static const CGFloat kBobAmpl = 9;            // waiting bob height (pt)
static const CGFloat kBobPeriod = 2.6;        // waiting bob period (s)
static const CGFloat kVibAmpl = 2;            // working vibrate amplitude (pt)
static const CGFloat kVibPeriod = 0.5;        // working vibrate period (s)
static const CGFloat kLabelFont = 15;
static const NSInteger kReloadFrames = 60;    // re-read the registry every ~2s

@interface ClaudePetsView : ScreenSaverView
@property (nonatomic) double t;               // accumulated animation time (s)
@property (nonatomic) NSInteger frameCount;
@property (nonatomic, strong) NSImage *colorLogo;
@property (nonatomic, strong) NSImage *grayLogo;
@property (nonatomic, strong) NSArray<NSDictionary *> *waiting;
@property (nonatomic, strong) NSArray<NSDictionary *> *working;
@end

@implementation ClaudePetsView

- (instancetype)initWithFrame:(NSRect)frame isPreview:(BOOL)isPreview {
  self = [super initWithFrame:frame isPreview:isPreview];
  if (self) {
    [self setAnimationTimeInterval:1.0 / 30.0];
    _t = 0;
    _frameCount = 0;
    _waiting = @[];
    _working = @[];
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    _colorLogo = [[NSImage alloc] initWithContentsOfFile:
        [bundle pathForResource:@"claudecode-color" ofType:@"png"]];
    _grayLogo = [[NSImage alloc] initWithContentsOfFile:
        [bundle pathForResource:@"claudecode-gray" ofType:@"png"]];
    [self reloadSessions];
  }
  return self;
}

// ----------------------------------------------------------- registry read --

- (NSString *)registryDir {
  // NSHomeDirectory() is the sandbox container here; getpwuid gives the real
  // home, which the host is entitled to read.
  struct passwd *pw = getpwuid(getuid());
  NSString *home = (pw && pw->pw_dir) ? @(pw->pw_dir) : NSHomeDirectory();
  return [home stringByAppendingPathComponent:@".cache/claude-sessions"];
}

- (void)reloadSessions {
  NSString *dir = [self registryDir];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSArray<NSString *> *files = [fm contentsOfDirectoryAtPath:dir error:NULL];
  NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
  NSMutableArray<NSDictionary *> *wait = [NSMutableArray array];
  NSMutableArray<NSDictionary *> *work = [NSMutableArray array];

  for (NSString *f in files) {
    if (![f hasSuffix:@".json"]) {
      continue;
    }
    NSData *data = [NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:f]];
    if (!data) {
      continue;
    }
    NSDictionary *d = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![d isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSNumber *updated = d[@"updated_at"];
    if (![updated isKindOfClass:[NSNumber class]] || now - updated.doubleValue > kTTL) {
      continue;
    }
    NSString *state = d[@"state"];
    if ([state isEqualToString:@"attention"] || [state isEqualToString:@"asking"]) {
      [wait addObject:d];
    } else if ([state isEqualToString:@"working"]) {
      [work addObject:d];
    }
  }

  NSComparator byTime = ^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
    double ua = [a[@"updated_at"] doubleValue], ub = [b[@"updated_at"] doubleValue];
    return (ua < ub) ? NSOrderedAscending : (ua > ub) ? NSOrderedDescending : NSOrderedSame;
  };
  self.waiting = [wait sortedArrayUsingComparator:byTime];
  self.working = [work sortedArrayUsingComparator:byTime];
}

// ------------------------------------------------------------------- draw --

- (void)drawImage:(NSImage *)img inRect:(NSRect)r alpha:(CGFloat)a {
  if (img) {
    [img drawInRect:r
           fromRect:NSZeroRect
          operation:NSCompositingOperationSourceOver
           fraction:a
     respectFlipped:YES
              hints:nil];
  } else { // asset missing: fall back to a visible block so it's never silent
    [[NSColor systemOrangeColor] set];
    NSRectFill(NSInsetRect(r, r.size.width * 0.2, r.size.height * 0.2));
  }
}

- (NSString *)labelFor:(NSDictionary *)session {
  NSString *cwd = session[@"cwd"];
  if ([cwd isKindOfClass:[NSString class]] && cwd.length > 0) {
    return cwd.lastPathComponent;
  }
  return @"claude";
}

- (void)drawLabel:(NSString *)text centeredAt:(CGFloat)cx top:(CGFloat)top width:(CGFloat)w {
  static NSDictionary *attrs = nil;
  if (!attrs) {
    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
    ps.alignment = NSTextAlignmentCenter;
    ps.lineBreakMode = NSLineBreakByTruncatingTail;
    attrs = @{
      NSFontAttributeName : [NSFont systemFontOfSize:kLabelFont weight:NSFontWeightMedium],
      NSForegroundColorAttributeName : [NSColor colorWithWhite:0.9 alpha:0.92],
      NSParagraphStyleAttributeName : ps,
    };
  }
  NSRect r = NSMakeRect(cx - w, top - kLabelFont - 4, w * 2, kLabelFont + 2);
  [text drawInRect:r withAttributes:attrs];
}

- (void)drawRect:(NSRect)rect {
  [[NSColor blackColor] set];
  NSRectFill(rect);

  NSRect b = self.bounds;
  CGFloat W = b.size.width, H = b.size.height;
  double t = self.t;

  // Empty: a single dim logo so an idle screen still reads as "Claude Pets".
  if (self.waiting.count == 0 && self.working.count == 0) {
    CGFloat s = 140;
    [self drawImage:self.grayLogo
             inRect:NSMakeRect((W - s) / 2, (H - s) / 2, s, s)
              alpha:0.22];
    return;
  }

  // Working bots: grey, vertical column centered on the left edge, vibrating.
  NSUInteger m = self.working.count;
  if (m > 0) {
    CGFloat total = m * kWorkSize + (m - 1) * kGap;
    CGFloat topY = (H + total) / 2 - kWorkSize; // top slot's origin-y
    for (NSUInteger i = 0; i < m; i++) {
      double phase = i * 0.9;
      CGFloat vx = kVibAmpl * sin(t * (2 * M_PI / kVibPeriod) + phase);
      CGFloat vy = kVibAmpl * sin(t * (2 * M_PI / kVibPeriod) * 1.7 + phase);
      CGFloat x = kLeftMargin + vx;
      CGFloat y = topY - i * (kWorkSize + kGap) + vy;
      [self drawImage:self.grayLogo
               inRect:NSMakeRect(x, y, kWorkSize, kWorkSize)
                alpha:1.0];
    }
  }

  // Waiting bots: orange, horizontal row centered near the top, bobbing.
  NSUInteger n = self.waiting.count;
  if (n > 0) {
    CGFloat total = n * kWaitSize + (n - 1) * kGap;
    CGFloat startX = (W - total) / 2;
    CGFloat baseY = H - kTopMargin - kWaitSize;
    for (NSUInteger i = 0; i < n; i++) {
      double phase = i * 0.7;
      CGFloat bob = kBobAmpl * sin(t * (2 * M_PI / kBobPeriod) + phase);
      CGFloat x = startX + i * (kWaitSize + kGap);
      CGFloat y = baseY - bob;
      [self drawImage:self.colorLogo
               inRect:NSMakeRect(x, y, kWaitSize, kWaitSize)
                alpha:1.0];
      [self drawLabel:[self labelFor:self.waiting[i]]
           centeredAt:x + kWaitSize / 2
                  top:y
                width:kWaitSize];
    }
  }
}

- (void)animateOneFrame {
  self.t += [self animationTimeInterval];
  self.frameCount += 1;
  if (self.frameCount % kReloadFrames == 0) {
    [self reloadSessions];
  }
  [self setNeedsDisplay:YES];
}

@end
