// ApolloGallerySlideshow.h
//
// Gallery View slideshow — the timing model behind the fullscreen viewer's
// slideshow (see ApolloGalleryImageViewer).
//
// A slideshow walks the same live feed the viewer pages through: each item
// stays up until it is "done", then the viewer crossfades to the next one.
// What "done" means depends on the media:
//   • Photo     — its FULL-SIZE picture has been on screen for the chosen
//                 duration (Settings > Media > Slideshow Photo Duration). A
//                 picture that fails, or still hasn't arrived after
//                 ApolloGallerySlideshowReadyTimeout, is timed on whatever is
//                 showing instead.
//   • Animation — an animated .gif has played one complete loop. The viewer
//                 rewinds it to the first frame when it becomes current, so
//                 that first loop is a full one.
//   • Playable  — a video / mp4 GIF / hosted clip has played to its end
//                 (looping is off while a slideshow runs). A hosted lookup
//                 that finds nothing shows its poster for the photo duration;
//                 one that never moves for ApolloGallerySlideshowStallTimeout
//                 is skipped.
//
// While the slideshow is "held" (a finger on the pager, a menu or share sheet
// open, zoomed in, scrubbing, a video the user paused, the app inactive)
// nothing advances, and on release a photo gets its full duration again and a
// GIF needs one complete loop that begins after the hold.
//
// This is a pure model: no timers, no clock, no UIKit. The viewer ticks it
// every ApolloGallerySlideshowTickInterval with the time and a snapshot of
// the current page, and acts on the answer. That keeps every rule above
// testable on the host (tests/run_gallery_slideshow_tests.sh).

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

static NSTimeInterval const ApolloGallerySlideshowTickInterval = 0.25;
static NSTimeInterval const ApolloGallerySlideshowCrossfadeDuration = 0.35;
static NSTimeInterval const ApolloGallerySlideshowReadyTimeout = 10.0;
static NSTimeInterval const ApolloGallerySlideshowStallTimeout = 10.0;
static NSInteger const ApolloGallerySlideshowDefaultPhotoSeconds = 5;

typedef NS_ENUM(NSInteger, ApolloGallerySlideKind) {
    ApolloGallerySlideKindPhoto = 0,
    ApolloGallerySlideKindAnimation,   // animated .gif through FLAnimatedImageView
    ApolloGallerySlideKindPlayable,    // AVPlayer: video, mp4 GIF, hosted video
};

typedef NS_ENUM(NSInteger, ApolloGallerySlideshowAdvance) {
    ApolloGallerySlideshowAdvanceNone = 0,
    ApolloGallerySlideshowAdvancePhotoTimer,
    ApolloGallerySlideshowAdvanceAnimationLoop,
    ApolloGallerySlideshowAdvancePlaybackEnded,
    ApolloGallerySlideshowAdvanceMediaFailed,
    ApolloGallerySlideshowAdvanceStalled,
};

// What the current page looks like right now.
typedef struct {
    BOOL held;                  // anything listed above as a hold
    BOOL fullImageShown;        // the full-size picture (not the thumbnail) is on the page
    BOOL animationShown;        // an FLAnimatedImage is on the page
    NSUInteger animationLoops;  // loops completed since that animation was last (re)set
    BOOL mediaFailed;           // photo/GIF: full image failed; playable: hosted lookup found nothing
    BOOL playbackEnded;         // playable reached its end
    double playbackPosition;    // seconds; NAN when the page has no player
} ApolloGallerySlideSample;

// The photo durations Settings offers, in seconds.
NSArray<NSNumber *> *ApolloGallerySlideshowPhotoDurationChoices(void);
// `stored` if it is one of the choices, else ApolloGallerySlideshowDefaultPhotoSeconds.
NSInteger ApolloGallerySlideshowSanitizedPhotoSeconds(NSInteger stored);
// "5 seconds".
NSString *ApolloGallerySlideshowPhotoDurationTitle(NSInteger seconds);
// "photo timer", "stalled", … for diagnostics.
NSString *ApolloGallerySlideshowAdvanceName(ApolloGallerySlideshowAdvance reason);

@interface ApolloGallerySlideshow : NSObject

// The kind the current slide is being timed as. An Animation that never
// actually animates is timed as a Photo.
@property (nonatomic, readonly) ApolloGallerySlideKind kind;

// A new item became the current page.
- (void)beginSlideOfKind:(ApolloGallerySlideKind)kind
            photoSeconds:(NSTimeInterval)photoSeconds
                  atTime:(NSTimeInterval)now;

// None to stay, otherwise why the slide is done. Idempotent: it keeps
// answering the same reason until the next -beginSlideOfKind:.
- (ApolloGallerySlideshowAdvance)tickAtTime:(NSTimeInterval)now sample:(ApolloGallerySlideSample)sample;

@end

NS_ASSUME_NONNULL_END
