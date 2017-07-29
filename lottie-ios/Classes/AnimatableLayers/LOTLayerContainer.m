//
//  LOTLayerContainer.m
//  Lottie
//
//  Created by brandon_withrow on 7/18/17.
//  Copyright © 2017 Airbnb. All rights reserved.
//

#import "LOTLayerContainer.h"
#import "LOTTransformInterpolator.h"
#import "LOTNumberInterpolator.h"
#import "CGGeometry+LOTAdditions.h"
#import "LOTRenderGroup.h"
#import "LOTHelpers.h"
#import "LOTMaskContainer.h"
#import "LOTAsset.h"

@implementation LOTLayerContainer {
  LOTTransformInterpolator *_transformInterpolator;
  LOTNumberInterpolator *_opacityInterpolator;
  NSNumber *_inFrame;
  NSNumber *_outFrame;
  CALayer *DEBUG_Center;
  LOTRenderGroup *_contentsGroup;
  LOTMaskContainer *_maskLayer;
}

@dynamic currentFrame;

- (instancetype)initWithModel:(LOTLayer *)layer
                 inLayerGroup:(LOTLayerGroup *)layerGroup {
  self = [super init];
  if (self) {
    _wrapperLayer = [CALayer new];
    [self addSublayer:_wrapperLayer];
    DEBUG_Center = [CALayer layer];
    
    DEBUG_Center.bounds = CGRectMake(0, 0, 20, 20);
    DEBUG_Center.borderColor = [UIColor blueColor].CGColor;
    DEBUG_Center.borderWidth = 2;
    DEBUG_Center.masksToBounds = YES;
    
    if (ENABLE_DEBUG_SHAPES) {
      [_wrapperLayer addSublayer:DEBUG_Center];
    } 
    self.actions = @{@"hidden" : [NSNull null], @"opacity" : [NSNull null], @"transform" : [NSNull null]};
    _wrapperLayer.actions = [self.actions copy];
    [self commonInitializeWith:layer inLayerGroup:layerGroup];
  }
  return self;
}

- (void)commonInitializeWith:(LOTLayer *)layer
                inLayerGroup:(LOTLayerGroup *)layerGroup {
  if (layer == nil) {
    return;
  }
  
  if (layer.layerType == LOTLayerTypeImage ||
      layer.layerType == LOTLayerTypeSolid ||
      layer.layerType == LOTLayerTypePrecomp) {
    _wrapperLayer.bounds = CGRectMake(0, 0, layer.layerWidth.floatValue, layer.layerHeight.floatValue);
    _wrapperLayer.anchorPoint = CGPointMake(0, 0);
    _wrapperLayer.masksToBounds = YES;
    DEBUG_Center.position = LOT_RectGetCenterPoint(self.bounds);
  }
  
  if (layer.layerType == LOTLayerTypeImage) {
    [self _setImageForAsset:layer.imageAsset];
  }
  
  _inFrame = [layer.inFrame copy];
  _outFrame = [layer.outFrame copy];
  _transformInterpolator = [LOTTransformInterpolator transformForLayer:layer];
  if (layer.parentID) {
    NSNumber *parentID = layer.parentID;
    LOTTransformInterpolator *childInterpolator = _transformInterpolator;
    while (parentID != nil) {
      LOTLayer *parentModel = [layerGroup layerModelForID:parentID];
      LOTTransformInterpolator *interpolator = [LOTTransformInterpolator transformForLayer:parentModel];
      childInterpolator.inputNode = interpolator;
      childInterpolator = interpolator;
      parentID = parentModel.parentID;
    }
  }
  _opacityInterpolator = [[LOTNumberInterpolator alloc] initWithKeyframes:layer.opacity.keyframes];
  if (layer.layerType == LOTLayerTypeShape &&
      layer.shapes.count) {
    [self buildContents:layer.shapes];
  }
  if (layer.layerType == LOTLayerTypeSolid) {
    _wrapperLayer.backgroundColor = layer.solidColor.CGColor;
  }
  if (layer.masks.count) {
    _maskLayer = [[LOTMaskContainer alloc] initWithMasks:layer.masks];
    _wrapperLayer.mask = _maskLayer;
  }
}

- (void)buildContents:(NSArray *)contents {
  _contentsGroup = [[LOTRenderGroup alloc] initWithInputNode:nil contents:contents];
  [_wrapperLayer addSublayer:_contentsGroup.containerLayer];
}

#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR

- (void)_setImageForAsset:(LOTAsset *)asset {
  if (asset.imageName) {
    UIImage *image;
    if (asset.rootDirectory.length > 0) {
      NSString *rootDirectory  = asset.rootDirectory;
      if (asset.imageDirectory.length > 0) {
        rootDirectory = [rootDirectory stringByAppendingPathComponent:asset.imageDirectory];
      }
      NSString *imagePath = [rootDirectory stringByAppendingPathComponent:asset.imageName];
      image = [UIImage imageWithContentsOfFile:imagePath];
    }else{
      NSArray *components = [asset.imageName componentsSeparatedByString:@"."];
      image = [UIImage imageNamed:components.firstObject inBundle:asset.assetBundle compatibleWithTraitCollection:nil];
    }
    
    if (image) {
      _wrapperLayer.contents = (__bridge id _Nullable)(image.CGImage);
    } else {
      NSLog(@"%s: Warn: image not found: %@", __PRETTY_FUNCTION__, asset.imageName);
    }
  }
}

#else

- (void)_setImageForAsset:(LOTAsset *)asset {
  if (asset.imageName) {
    NSArray *components = [asset.imageName componentsSeparatedByString:@"."];
    NSImage *image = [NSImage imageNamed:components.firstObject];
    if (image) {
      NSWindow *window = [NSApp mainWindow];
      CGFloat desiredScaleFactor = [window backingScaleFactor];
      CGFloat actualScaleFactor = [image recommendedLayerContentsScale:desiredScaleFactor];
      id layerContents = [image layerContentsForContentsScale:actualScaleFactor];
      _wrapperLayer = layerContents;
      
    }
  }
  
}

#endif

// MARK - Animation

+ (BOOL)needsDisplayForKey:(NSString *)key {
  BOOL needsDisplay = [super needsDisplayForKey:key];
  
  if ([key isEqualToString:@"currentFrame"]) {
    needsDisplay = YES;
  }
  
  return needsDisplay;
}

-(id<CAAction>)actionForKey:(NSString *)event {
  if([event isEqualToString:@"currentFrame"]) {
    CABasicAnimation *theAnimation = [CABasicAnimation
                                      animationWithKeyPath:event];
    theAnimation.fromValue = [[self presentationLayer] valueForKey:event];
    return theAnimation;
  }
  return [super actionForKey:event];
}

- (void)display {
  LOTLayerContainer *presentation = (LOTLayerContainer *)self.presentationLayer;
  if (presentation == nil) {
    presentation = self;
  }
  [self displayWithFrame:presentation.currentFrame];
}

- (void)displayWithFrame:(NSNumber *)frame {
  if (ENABLE_DEBUG_LOGGING) NSLog(@"View %@ Displaying Frame %@", self, frame);
  BOOL hidden = NO;
  if (_inFrame && _outFrame) {
    hidden = (frame.floatValue < _inFrame.floatValue ||
              frame.floatValue > _outFrame.floatValue);
  }
  self.hidden = hidden;
  if (hidden) {
    return;
  }
  if (_opacityInterpolator && [_opacityInterpolator hasUpdateForFrame:frame]) {
    self.opacity = [_opacityInterpolator floatValueForFrame:frame];
  }
  if (_transformInterpolator && [_transformInterpolator hasUpdateForFrame:frame]) {
    _wrapperLayer.transform = [_transformInterpolator transformForFrame:frame];
  }
  [_contentsGroup updateWithFrame:frame];
  _maskLayer.currentFrame = frame;
}

- (void)setViewportBounds:(CGRect)viewportBounds {
  _viewportBounds = viewportBounds;
  if (_maskLayer) {
    CGPoint center = LOT_RectGetCenterPoint(viewportBounds);
    viewportBounds.origin = CGPointMake(-center.x, -center.y);
    _maskLayer.bounds = viewportBounds;
  }
}

@end