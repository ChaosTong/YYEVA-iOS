//
//  YYEVAVideoAlphaRender.m
//  YYEVA
//
//  Created by guoyabin on 2022/4/21.
//

#import "YYEVAVideoAlphaRender.h"
#import "YYEVAAssets.h"
#include "YYEVAVideoShareTypes.h"

extern matrix_float3x3 kColorConversion601FullRangeMatrix;
extern vector_float3 kColorConversion601FullRangeOffset;

@interface YYEVAVideoAlphaRender()
{
    float _imageVertices[8];
}
@property (nonatomic, weak) MTKView *mtkView;
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLRenderPipelineState> renderPipelineState;
@property (nonatomic, strong) id<MTLBuffer> vertexBuffer;
@property (nonatomic, strong) id<MTLBuffer> convertMatrix;
@property (nonatomic, strong) id<MTLBuffer> elementVertexBuffer;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, assign) CVMetalTextureCacheRef textureCache;
@property (nonatomic, assign) vector_uint2 viewportSize;
@property (nonatomic, assign) NSInteger numVertices;
@end

@implementation YYEVAVideoAlphaRender
@synthesize completionPlayBlock;
@synthesize playAssets;
@synthesize inputSize = _inputSize;
@synthesize fillMode = _fillMode;


- (void)dealloc
{
    CFRelease(_textureCache);
}

- (instancetype)initWithMetalView:(MTKView *)mtkView
{
    if (self = [super init]) {
        [self setupRenderWithMetal:mtkView];
    }
    return self;
}

- (void)setFillMode:(YYEVAFillMode)fillMode
{
    _fillMode = fillMode;
    [self setupVertex];
}

- (void)setInputSize:(CGSize)inputSize
{
    _inputSize = inputSize;
    [self setupVertex];
}

- (void)playWithAssets:(YYEVAAssets *)assets
{
    self.playAssets = assets;
    CVMetalTextureCacheCreate(NULL, NULL, self.mtkView.device, NULL, &_textureCache);
}


- (void)setupRenderWithMetal:(MTKView *)mtkView
{
    _mtkView = mtkView;
    _device = mtkView.device;
    [self setupRenderPiplineState];
    [self setupVertex];
    [self setupFragment];
    self.viewportSize = (vector_uint2){self.mtkView.drawableSize.width, self.mtkView.drawableSize.height};
}

- (void)setupRenderPiplineState
{
    NSString *filePath = [[NSBundle bundleForClass:[self class]] pathForResource:@"YYEVABundle.bundle/default" ofType:@"metallib"];
    id<MTLLibrary> library = [_device newLibraryWithFile:filePath error:nil];
    id<MTLFunction> vertexFunction = [library newFunctionWithName:@"normalVertexShader"];
    id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"normalFragmentSharder"];
    
    MTLRenderPipelineDescriptor *renderPipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    renderPipelineDescriptor.vertexFunction = vertexFunction;
    renderPipelineDescriptor.fragmentFunction = fragmentFunction;
    renderPipelineDescriptor.colorAttachments[0].pixelFormat = _mtkView.colorPixelFormat;
    [renderPipelineDescriptor.colorAttachments[0] setBlendingEnabled:YES];
    renderPipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    renderPipelineDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    renderPipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    renderPipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor =  MTLBlendFactorSourceAlpha;
    renderPipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    renderPipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    _renderPipelineState = [_device newRenderPipelineStateWithDescriptor:renderPipelineDescriptor error:nil];
    
    
    _commandQueue = [_device newCommandQueue];
}

- (void)recalculateViewGeometry
{
    float heightScaling = 1.0;
    float widthScaling = 1.0;
    CGSize drawableSize = self.mtkView.bounds.size;
    CGRect bounds = CGRectMake(0, 0, drawableSize.width, drawableSize.height);
    CGRect insetRect = AVMakeRectWithAspectRatioInsideRect(self.inputSize, bounds);
    switch (self.fillMode) {
        case YYEVAContentMode_ScaleToFill:
            heightScaling = 1.0;
            widthScaling = 1.0;
            break;
            
        case YYEVAContentMode_ScaleAspectFit:
            widthScaling = insetRect.size.width / drawableSize.width;
            heightScaling = insetRect.size.height / drawableSize.height;
            break;
            
        case YYEVAContentMode_ScaleAspectFill:
            widthScaling = drawableSize.height / insetRect.size.height;
            heightScaling = drawableSize.width / insetRect.size.width;
            break;
    }
    self->_imageVertices[0] = -widthScaling;
    self->_imageVertices[1] = -heightScaling;
    self->_imageVertices[2] = -widthScaling;
    self->_imageVertices[3] = heightScaling;
    self->_imageVertices[4] = widthScaling;
    self->_imageVertices[5] = -heightScaling;
    self->_imageVertices[6] = widthScaling;
    self->_imageVertices[7] = heightScaling;
    
}



// 设置顶点
- (void)setupVertex {
     
    
    [self recalculateViewGeometry];
    
    YSVideoMetalVertex quadVertices[] =
    {   // 顶点坐标，分别是x、y、z；    纹理坐标，x、y；
        { { self->_imageVertices[0], self->_imageVertices[1], 0.0 ,1.0},  { 0.f, 1.f} },
        { { self->_imageVertices[2],  self->_imageVertices[3], 0.0 ,1.0},  { 0.f, 0.0f } },
        { { self->_imageVertices[4], self->_imageVertices[5], 0.0,1.0 },  { 1.f, 1.f } },
        { { self->_imageVertices[6], self->_imageVertices[7], 0.0,1.0 },  { 1.f, 0.f } }
    };
    
    //2.创建顶点缓存区
    self.vertexBuffer = [self.mtkView.device newBufferWithBytes:quadVertices
                                                     length:sizeof(quadVertices)
                                                    options:MTLResourceStorageModeShared];
    //3.计算顶点个数
    self.numVertices = sizeof(quadVertices) / sizeof(YSVideoMetalVertex);
}
- (void)setupFragment
{
    //创建转化矩阵结构体.
    YSVideoMetalConvertMatrix matrix;
    matrix.matrix = kColorConversion601FullRangeMatrix;
    matrix.offset = kColorConversion601FullRangeOffset;
    //4.创建转换矩阵缓存区.
    self.convertMatrix = [self.mtkView.device newBufferWithBytes:&matrix
                                                        length:sizeof(YSVideoMetalConvertMatrix)
                                                options:MTLResourceStorageModeShared];
     
}


#pragma mark -- MTKView Delegate
//当MTKView size 改变则修改self.viewportSize
- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size
{
    self.viewportSize = (vector_uint2){size.width, size.height};
    
    [self setupVertex];
}

//视图绘制
- (void)drawInMTKView:(MTKView *)view
{
    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
    CMSampleBufferRef sampleBuffer = [self.playAssets nextSampleBuffer];
     
    if(renderPassDescriptor && sampleBuffer)
    {
        NSLog(@"-----%zd----",self.playAssets.frameIndex);
        
        //设置renderPassDescriptor中颜色附着(默认背景色)
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0f);
        //根据渲染描述信息创建渲染命令编码器
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        //设置视口大小(显示区域)
        [renderEncoder setViewport:(MTLViewport){0.0, 0.0, self.viewportSize.x, self.viewportSize.y, -1.0, 1.0 }];
        [renderEncoder setRenderPipelineState:self.renderPipelineState];
        [self setupVertexFunctionData:renderEncoder];
        [self setupFragmentFunctionData:renderEncoder sampleBuffer:sampleBuffer];
        //绘制
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip
                          vertexStart:0
                          vertexCount:self.numVertices];
        [renderEncoder endEncoding];
        [commandBuffer presentDrawable:view.currentDrawable];
        [commandBuffer commit];
    } else {
        if (![self.playAssets hasNextSampleBuffer]) {
//            self.mtkView.paused = YES;
            if (self.completionPlayBlock) {
                self.completionPlayBlock();
            }
        }
    }
    
    if (sampleBuffer) {
        CMSampleBufferInvalidate(sampleBuffer);
        CFRelease(sampleBuffer);
        sampleBuffer = NULL;
    }
}

- (void)setupVertexFunctionData:(id<MTLRenderCommandEncoder>)renderCommandEncoder
{
    //设置顶点数据和纹理坐标
    [renderCommandEncoder setVertexBuffer:self.vertexBuffer offset:0 atIndex:YSVideoMetalVertexInputIndexVertices];
}

- (void)setupFragmentFunctionData:(id<MTLRenderCommandEncoder>)renderCommandEncoder
                     sampleBuffer:(CMSampleBufferRef)sampleBuffer
{
    //设置转换矩阵
    [renderCommandEncoder setFragmentBuffer:self.convertMatrix offset:0 atIndex:YSVideoMetalFragmentBufferIndexMatrix];
     
    //Y纹理
    id<MTLTexture> textureY = [self getTextureFromSampleBuffer:sampleBuffer planeIndex:0 pixelFormat:MTLPixelFormatR8Unorm];
    id<MTLTexture> textureUV = [self getTextureFromSampleBuffer:sampleBuffer planeIndex:1 pixelFormat:MTLPixelFormatRG8Unorm];
    if (textureY && textureUV) {
        [renderCommandEncoder setFragmentTexture:textureY atIndex:YSVideoMetalFragmentTextureIndexTextureY];
        [renderCommandEncoder setFragmentTexture:textureUV atIndex:YSVideoMetalFragmentTextureIndexTextureUV];
    } else {
        NSLog(@"---YUV获取异常---");
    }
    
}


//如果图像缓冲区是平面的，则为映射纹理数据的平面索引。对于非平面图像缓冲区忽
- (id<MTLTexture>)getTextureFromSampleBuffer:(CMSampleBufferRef)sampleBuffer
                                  planeIndex:(size_t)planeIndex
                                 pixelFormat:(MTLPixelFormat)pixelFormat
{
    //设置yuv纹理数据
    CVPixelBufferRef pixelBufferRef = CMSampleBufferGetImageBuffer(sampleBuffer);
//    //y纹理
    id<MTLTexture> texture = nil;
    size_t width = CVPixelBufferGetWidthOfPlane(pixelBufferRef, planeIndex);
    size_t height = CVPixelBufferGetHeightOfPlane(pixelBufferRef, planeIndex);
    CVMetalTextureRef textureRef = NULL;
    CVReturn status =  CVMetalTextureCacheCreateTextureFromImage(NULL, _textureCache, pixelBufferRef, NULL, pixelFormat, width, height, planeIndex, &textureRef);
    if (status == kCVReturnSuccess) {
        texture = CVMetalTextureGetTexture(textureRef);
        CVBufferRelease(textureRef);
        textureRef = NULL;
    }
    CVMetalTextureCacheFlush(_textureCache, 0);
    pixelBufferRef = NULL;
    return texture;
}

@end
