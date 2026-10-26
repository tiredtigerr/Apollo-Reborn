// ApolloGallerySlideshow.m — see ApolloGallerySlideshow.h.

#import "ApolloGallerySlideshow.h"

#import <math.h>

NSArray<NSNumber *> *ApolloGallerySlideshowPhotoDurationChoices(void) {
    return @[@2, @3, @5, @8, @10, @15, @20, @30];
}

NSInteger ApolloGallerySlideshowSanitizedPhotoSeconds(NSInteger stored) {
    return [ApolloGallerySlideshowPhotoDurationChoices() containsObject:@(stored)]
        ? stored : ApolloGallerySlideshowDefaultPhotoSeconds;
}

NSString *ApolloGallerySlideshowPhotoDurationTitle(NSInteger seconds) {
    return [NSString stringWithFormat:@"%ld seconds", (long)seconds];
}

NSString *ApolloGallerySlideshowAdvanceName(ApolloGallerySlideshowAdvance reason) {
    switch (reason) {
        case ApolloGallerySlideshowAdvancePhotoTimer: return @"photo timer";
        case ApolloGallerySlideshowAdvanceAnimationLoop: return @"animation loop";
        case ApolloGallerySlideshowAdvancePlaybackEnded: return @"playback ended";
        case ApolloGallerySlideshowAdvanceMediaFailed: return @"media failed";
        case ApolloGallerySlideshowAdvanceStalled: return @"stalled";
        case ApolloGallerySlideshowAdvanceNone: break;
    }
    return @"none";
}

@interface ApolloGallerySlideshow ()
@property (nonatomic, readwrite) ApolloGallerySlideKind kind;
@property (nonatomic) NSTimeInterval photoSeconds;
@property (nonatomic) NSTimeInterval slideStart;
// The previous tick was held; the next unheld one restarts the clocks.
@property (nonatomic) BOOL heldOnLastTick;

// Photo: when the full image (or a failure, or the readiness timeout) put
// something on screen to time. NAN until then.
@property (nonatomic) NSTimeInterval showingSince;
@property (nonatomic) BOOL showingBecauseFailed;

// Animation: loop completions already accounted for, and whether the loop
// now playing began while nothing was held — only such a loop can finish
// the slide.
@property (nonatomic) NSUInteger loopsSeen;
@property (nonatomic) BOOL loopClean;

// Playable.
@property (nonatomic) NSTimeInterval failedSince;
@property (nonatomic) double lastPosition;
@property (nonatomic) NSTimeInterval lastProgressAt;
@end

@implementation ApolloGallerySlideshow

- (void)beginSlideOfKind:(ApolloGallerySlideKind)kind
            photoSeconds:(NSTimeInterval)photoSeconds
                  atTime:(NSTimeInterval)now {
    self.kind = kind;
    self.photoSeconds = photoSeconds;
    self.slideStart = now;
    self.heldOnLastTick = NO;
    self.showingSince = NAN;
    self.showingBecauseFailed = NO;
    // The viewer rewinds the animation as the slide begins, so the loop
    // that is about to play is a complete one.
    self.loopsSeen = 0;
    self.loopClean = YES;
    self.failedSince = NAN;
    self.lastPosition = NAN;
    self.lastProgressAt = now;
}

- (ApolloGallerySlideshowAdvance)tickAtTime:(NSTimeInterval)now sample:(ApolloGallerySlideSample)sample {
    if (sample.held) {
        self.heldOnLastTick = YES;
        return ApolloGallerySlideshowAdvanceNone;
    }
    if (self.heldOnLastTick) {
        // Released: whatever was being timed starts over, so a photo gets its
        // full duration again and a paused video gets a fresh stall window.
        self.heldOnLastTick = NO;
        if (!isnan(self.showingSince)) self.showingSince = now;
        if (!isnan(self.failedSince)) self.failedSince = now;
        self.lastProgressAt = now;
        // The loop in progress started before the release, so it can't count —
        // unless nothing is animating yet, in which case the next animation
        // starts fresh from its first frame.
        self.loopsSeen = sample.animationLoops;
        self.loopClean = !sample.animationShown;
    }

    switch (self.kind) {
        case ApolloGallerySlideKindPhoto:
            return [self apollo_photoTickAtTime:now sample:sample];
        case ApolloGallerySlideKindAnimation:
            return [self apollo_animationTickAtTime:now sample:sample];
        case ApolloGallerySlideKindPlayable:
            return [self apollo_playableTickAtTime:now sample:sample];
    }
    return ApolloGallerySlideshowAdvanceNone;
}

- (ApolloGallerySlideshowAdvance)apollo_photoTickAtTime:(NSTimeInterval)now sample:(ApolloGallerySlideSample)sample {
    if (isnan(self.showingSince)) {
        if (sample.fullImageShown || sample.mediaFailed ||
            now - self.slideStart >= ApolloGallerySlideshowReadyTimeout) {
            self.showingSince = now;
            self.showingBecauseFailed = sample.mediaFailed && !sample.fullImageShown;
        } else {
            return ApolloGallerySlideshowAdvanceNone;
        }
    }
    if (now - self.showingSince < self.photoSeconds) return ApolloGallerySlideshowAdvanceNone;
    return self.showingBecauseFailed ? ApolloGallerySlideshowAdvanceMediaFailed
                                     : ApolloGallerySlideshowAdvancePhotoTimer;
}

- (ApolloGallerySlideshowAdvance)apollo_animationTickAtTime:(NSTimeInterval)now sample:(ApolloGallerySlideSample)sample {
    if (!sample.animationShown) {
        // A still where the animation should be (no FLAnimatedImageView, or
        // it decoded as a single frame), a failure, or nothing after the
        // readiness timeout: time it like a photo from here on.
        if (sample.fullImageShown || sample.mediaFailed ||
            now - self.slideStart >= ApolloGallerySlideshowReadyTimeout) {
            self.kind = ApolloGallerySlideKindPhoto;
            return [self apollo_photoTickAtTime:now sample:sample];
        }
        return ApolloGallerySlideshowAdvanceNone;
    }

    NSUInteger loops = sample.animationLoops;
    if (loops < self.loopsSeen) {
        // The animation was set again, which restarts it at its first frame.
        self.loopsSeen = loops;
        self.loopClean = YES;
    }
    if (loops > self.loopsSeen) {
        // Two or more completions in one tick means a whole loop fitted
        // between this tick and the last — which was itself unheld.
        if (self.loopClean || loops - self.loopsSeen >= 2) return ApolloGallerySlideshowAdvanceAnimationLoop;
        self.loopsSeen = loops;
        self.loopClean = YES;
    }
    return ApolloGallerySlideshowAdvanceNone;
}

- (ApolloGallerySlideshowAdvance)apollo_playableTickAtTime:(NSTimeInterval)now sample:(ApolloGallerySlideSample)sample {
    if (sample.playbackEnded) return ApolloGallerySlideshowAdvancePlaybackEnded;

    if (sample.mediaFailed) {
        if (isnan(self.failedSince)) self.failedSince = now;
        return now - self.failedSince >= self.photoSeconds ? ApolloGallerySlideshowAdvanceMediaFailed
                                                           : ApolloGallerySlideshowAdvanceNone;
    }

    double position = sample.playbackPosition;
    if (isfinite(position) && (isnan(self.lastPosition) || fabs(position - self.lastPosition) > 0.01)) {
        self.lastPosition = position;
        self.lastProgressAt = now;
    }
    return now - self.lastProgressAt >= ApolloGallerySlideshowStallTimeout ? ApolloGallerySlideshowAdvanceStalled
                                                                         : ApolloGallerySlideshowAdvanceNone;
}

@end
