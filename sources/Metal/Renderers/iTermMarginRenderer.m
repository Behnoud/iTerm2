//
//  iTermMarginRenderer.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/19/17.
//

#import "iTermMarginRenderer.h"

#import "FutureMethods.h"
#import "iTermMetalBufferPool.h"
#import "iTermShaderTypes.h"

NS_ASSUME_NONNULL_BEGIN

@implementation iTermMarginRendererTransientState
@end

@implementation iTermMarginRenderer {
    iTermMetalCellRenderer *_blendingRenderer;
#if ENABLE_TRANSPARENT_METAL_WINDOWS
    iTermMetalCellRenderer *_nonblendingRenderer NS_AVAILABLE_MAC(10_14);
    iTermMetalCellRenderer *_compositeOverRenderer NS_AVAILABLE_MAC(10_14);
#endif
    iTermMetalBufferPool *_colorPool;
    iTermMetalBufferPool *_verticesPool;
}

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
#if ENABLE_TRANSPARENT_METAL_WINDOWS
        if (iTermTextIsMonochrome()) {
            _nonblendingRenderer = [[iTermMetalCellRenderer alloc] initWithDevice:device
                                                               vertexFunctionName:@"iTermMarginVertexShader"
                                                             fragmentFunctionName:@"iTermMarginFragmentShader"
                                                                         blending:nil
                                                                   piuElementSize:0
                                                              transientStateClass:[iTermMarginRendererTransientState class]];
            _compositeOverRenderer = [[iTermMetalCellRenderer alloc] initWithDevice:device
                                                                 vertexFunctionName:@"iTermMarginVertexShader"
                                                               fragmentFunctionName:@"iTermMarginFragmentShader"
                                                                           blending:[iTermMetalBlending premultipliedCompositing]
                                                                     piuElementSize:0
                                                                transientStateClass:[iTermMarginRendererTransientState class]];
        }
#endif
        _blendingRenderer = [[iTermMetalCellRenderer alloc] initWithDevice:device
                                                        vertexFunctionName:@"iTermMarginVertexShader"
                                                      fragmentFunctionName:@"iTermMarginFragmentShader"
                                                                  blending:[[iTermMetalBlending alloc] init]
                                                            piuElementSize:0
                                                       transientStateClass:[iTermMarginRendererTransientState class]];
        _colorPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(vector_float4)];
        _verticesPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(vector_float2) * 6 * 4];
    }
    return self;
}

- (iTermMetalFrameDataStat)createTransientStateStat {
    return iTermMetalFrameDataStatPqCreateMarginTS;
}

- (iTermMetalCellRenderer *)rendererForConfiguration:(iTermCellRenderConfiguration *)configuration {
#if ENABLE_TRANSPARENT_METAL_WINDOWS
    if (iTermTextIsMonochrome()) {
        if (configuration.hasBackgroundImage) {
            return _compositeOverRenderer;
        } else {
            return _nonblendingRenderer;
        }
    }
#endif
    return _blendingRenderer;
}

- (void)drawWithFrameData:(nonnull iTermMetalFrameData *)frameData
           transientState:(__kindof iTermMetalRendererTransientState *)transientState {
    iTermMarginRendererTransientState *tState = transientState;
    [self drawWithFrameData:frameData tState:tState];
}

- (void)drawWithFrameData:(nonnull iTermMetalFrameData *)frameData
                   tState:(nonnull iTermMarginRendererTransientState *)tState {
    [self initializeRegularVertexBuffer:tState];
    vector_float4 regularColor = tState.regularColor;
    if (iTermTextIsMonochrome()) {
        regularColor.x *= regularColor.w;
        regularColor.y *= regularColor.w;
        regularColor.z *= regularColor.w;
    }
    id<MTLBuffer> colorBuffer = [_colorPool requestBufferFromContext:tState.poolContext
                                                           withBytes:&regularColor
                                                      checkIfChanged:YES];
    iTermMetalCellRenderer *cellRenderer = [self rendererForConfiguration:tState.cellConfiguration];
    [cellRenderer drawWithTransientState:tState
                           renderEncoder:frameData.renderEncoder
                        numberOfVertices:6 * 4
                            numberOfPIUs:0
                           vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.vertexBuffer }
                         fragmentBuffers:@{ @(iTermFragmentBufferIndexMarginColor): colorBuffer }
                                textures:@{}];
}

- (void)drawWithRenderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
                        color:(vector_float4)nonPremultipliedColor
                  poolContext:(iTermMetalBufferPoolContext *)poolContext
                 cellRenderer:(iTermMetalCellRenderer *)cellRenderer
                 vertexBuffer:(id<MTLBuffer>)vertexBuffer
                     numQuads:(int)numQuads
               transientState:(iTermMetalRendererTransientState *)transientState {
    if (numQuads == 0) {
        return;
    }
    vector_float4 color = nonPremultipliedColor;
    if (iTermTextIsMonochrome()) {
        color.x *= color.w;
        color.y *= color.w;
        color.z *= color.w;
    }
    id<MTLBuffer> colorBuffer = [_colorPool requestBufferFromContext:poolContext
                                                           withBytes:&color
                                                      checkIfChanged:YES];

    [cellRenderer drawWithTransientState:transientState
                           renderEncoder:renderEncoder
                        numberOfVertices:6 * numQuads
                            numberOfPIUs:0
                           vertexBuffers:@{ @(iTermVertexInputIndexVertices): vertexBuffer }
                         fragmentBuffers:@{ @(iTermFragmentBufferIndexMarginColor): colorBuffer }
                                textures:@{}];
}

- (BOOL)rendererDisabled {
    return NO;
}

- (nullable __kindof iTermMetalRendererTransientState *)createTransientStateForCellConfiguration:(nonnull iTermCellRenderConfiguration *)configuration
                                                                          commandBuffer:(nonnull id<MTLCommandBuffer>)commandBuffer {
    iTermMetalCellRenderer *renderer = [self rendererForConfiguration:configuration];
    __kindof iTermMetalRendererTransientState * _Nonnull transientState =
        [renderer createTransientStateForCellConfiguration:configuration
                                             commandBuffer:commandBuffer];
    return transientState;
}

- (vector_float2 *)appendVerticesForQuad:(CGRect)quad vertices:(vector_float2 *)v {
    *(v++) = simd_make_float2(CGRectGetMaxX(quad), CGRectGetMinY(quad));
    *(v++) = simd_make_float2(CGRectGetMinX(quad), CGRectGetMinY(quad));
    *(v++) = simd_make_float2(CGRectGetMinX(quad), CGRectGetMaxY(quad));

    *(v++) = simd_make_float2(CGRectGetMaxX(quad), CGRectGetMinY(quad));
    *(v++) = simd_make_float2(CGRectGetMinX(quad), CGRectGetMaxY(quad));
    *(v++) = simd_make_float2(CGRectGetMaxX(quad), CGRectGetMaxY(quad));

    return v;
}

- (void)initializeRegularVertexBuffer:(iTermMarginRendererTransientState *)tState {
    CGSize size = CGSizeMake(tState.configuration.viewportSize.x,
                             tState.configuration.viewportSize.y);
    const NSEdgeInsets margins = tState.margins;
    vector_float2 vertices[6 * 4];
    vector_float2 *v = &vertices[0];
    // Top
    v = [self appendVerticesForQuad:CGRectMake(0,
                                               0,
                                               size.width,
                                               margins.top)
                           vertices:v];

    // Bottom
    v = [self appendVerticesForQuad:CGRectMake(0,
                                               size.height - margins.bottom,
                                               size.width,
                                               margins.bottom)
                           vertices:v];

    const CGFloat innerHeight = size.height - margins.bottom - margins.top;

    // Left
    v = [self appendVerticesForQuad:CGRectMake(0,
                                               margins.top,
                                               margins.left,
                                               innerHeight)
                           vertices:v];

    // Right
    const CGFloat gridWidth = tState.cellConfiguration.gridSize.width * tState.cellConfiguration.cellSize.width;
    const CGFloat rightGutterWidth = tState.configuration.viewportSize.x - margins.left - margins.right - gridWidth;
    [self appendVerticesForQuad:CGRectMake(size.width - margins.right - rightGutterWidth,
                                           margins.top,
                                           margins.right + rightGutterWidth,
                                           innerHeight)
                       vertices:v];

    tState.vertexBuffer = [_verticesPool requestBufferFromContext:tState.poolContext
                                                        withBytes:vertices
                                                   checkIfChanged:YES];
}

- (int)initializeVertexBuffer:(iTermMarginRendererTransientState *)tState {
    CGSize size = CGSizeMake(tState.configuration.viewportSize.x,
                             tState.configuration.viewportSize.y);
    const NSEdgeInsets margins = tState.margins;
    vector_float2 vertices[6 * 8];
    vector_float2 *v = &vertices[0];
    const VT100GridRange visibleRange = VT100GridRangeMake(0, MAX(0, tState.cellConfiguration.gridSize.height));

    int count = 0;

    // Top
    v = [self appendVerticesForQuad:CGRectMake(0,
                                               size.height - margins.bottom,
                                               size.width,
                                               margins.bottom)
                           vertices:v];
    count += 1;

    // Bottom
    v = [self appendVerticesForQuad:CGRectMake(0,
                                               0,
                                               size.width,
                                               margins.top)
                           vertices:v];
    count += 1;

    const CGFloat gridWidth = tState.cellConfiguration.gridSize.width * tState.cellConfiguration.cellSize.width;
    const CGFloat rightGutterWidth = tState.configuration.viewportSize.x - margins.left - margins.right - gridWidth;

    // Left/Right
    CGFloat y = margins.top;

    CGFloat h = visibleRange.length * tState.cellConfiguration.cellSize.height;
    v = [self appendVerticesForQuad:CGRectMake(0,
                                               y,
                                               margins.left,
                                               h)
                           vertices:v];
    v = [self appendVerticesForQuad:CGRectMake(size.width - margins.right - rightGutterWidth,
                                               y,
                                               margins.right + rightGutterWidth,
                                               h)
                           vertices:v];
    count += 2;
    y += h;

    tState.vertexBuffer = [_verticesPool requestBufferFromContext:tState.poolContext
                                                        withBytes:vertices
                                                   checkIfChanged:YES];
    return count;
}

@end

NS_ASSUME_NONNULL_END
