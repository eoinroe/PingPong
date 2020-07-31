import MetalKit

/**
 - Important: You must be explicit about types here and not rely on Swift's
   type inference when passing values into the shader functions.
*/
struct Uniforms {
    /// Scales the texture coordinates that feed the curl noise function.
    var noiseScale: Float = 2.5
    /// Scales the offset generated with the curl noise function.
    var noiseOffset: Float = 0
    /// Width and height of the textures used for Ping-pong buffer technique.
    var resolution: SIMD2<Float> = SIMD2<Float>(1024, 1024)
}

// Any attempt to subclass a final class is reported as a compile-time error.
final class Renderer: NSObject {
    /*
     Metal has a major advantage over OpenGL in that
     you're able to instantiate some objects up front.
     */
 
    /// Basic Metal entities to interface with the designated GPU.
    var metal: (device: MTLDevice, queue: MTLCommandQueue, library: MTLLibrary)
    /// Three compute pipelines - one for computation, one for rendering and a third that clears the textures.
    var states: (compute: MTLComputePipelineState, render: MTLComputePipelineState, reset: MTLComputePipelineState)
    /// Metal textures for Ping-pong buffer technique.
    var textures: (read: MTLTexture, write: MTLTexture)
    /// This array makes it easy to swap the textures after each compute pass.
    var textureBufferIndex: [Int] = [0, 1]
    /// Parameters that are passed into the shader, some of which can be adjusted with the user interface.
    public var uniforms = Uniforms()
    /// To visualize the curl noise this image will be sampled with an offset added to each uv coordinate.
    var image: MTLTexture!
    /// When true the components of the textures are set to 0.
    var reset: Bool = false
    
    enum Samplers {
        case _repeat, mirrored_repeat, clamp_to_edge, clamp_to_zero, clamp_to_border
    }
    
    var textureSampler: MTLSamplerState
    
    init(view: MTKView) {
        self.metal = Renderer.setupMetal()
        self.states = Renderer.setupComputePipelines(device: metal.device, library: metal.library)
        self.textures = Renderer.setupTextures(device: metal.device)
        self.image = Renderer.loadTexture(device: metal.device, name: "bikers")
        
        let descriptor = MTLSamplerDescriptor()
        descriptor.normalizedCoordinates = true
        descriptor.borderColor = .opaqueBlack
        descriptor.sAddressMode = .clampToBorderColor
        descriptor.tAddressMode = .clampToBorderColor
        descriptor.magFilter = .linear
        descriptor.minFilter = .linear
        
        textureSampler = metal.device.makeSamplerState(descriptor: descriptor)!

        super.init()
        
        // Final steps to set up the view
        view.device = metal.device
        view.delegate = self
        
        // This allows you to write directly to the current drawable with a compute shader
        view.framebufferOnly = false
    }
}

private extension Renderer {
    /// Creates the basic *non-trasient* Metal objects needed for this project.
    /// - returns: A metal device, a metal command queue, and the default library.
    static func setupMetal() -> (device: MTLDevice, queue: MTLCommandQueue, library: MTLLibrary) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device.")
        }
        
        guard let queue = device.makeCommandQueue() else {
            fatalError("A Metal command queue could not be created.")
        }
        
        guard let library = device.makeDefaultLibrary() else {
            fatalError("The default Metal library could not be created.")
        }
        
        return (device, queue, library)
    }
    
    /// - parameter device: Metal device needed to create pipeline state object.
    /// - parameter library: Compile Metal code hosting the kernel function driving the compute pipeline.
    static func setupComputePipelines(device: MTLDevice, library: MTLLibrary) -> (compute: MTLComputePipelineState, render: MTLComputePipelineState, reset: MTLComputePipelineState) {
        guard let computeFunction = library.makeFunction(name: "pingPong"),
              let renderFunction = library.makeFunction(name: "render"),
              let resetFunction = library.makeFunction(name: "reset") else {
                fatalError("The kernel functions could not be created.")
        }
        
        guard let computePipeline = try? device.makeComputePipelineState(function: computeFunction),
              let renderPipeline = try? device.makeComputePipelineState(function: renderFunction),
              let resetPipeline = try? device.makeComputePipelineState(function: resetFunction) else {
                fatalError("The pipelines could not be created.")
        }
        
        return (computePipeline, renderPipeline, resetPipeline)
    }
    
    /// We only need to use an .rg32Float texture here.
    static func setupTextures(device: MTLDevice) -> (read: MTLTexture, write: MTLTexture) {
        // Pass in uniforms to the function to access the resolution?
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rg32Float, width: 1024, height: 1024, mipmapped: false)
        
        descriptor.usage = [.shaderWrite, .shaderRead]
        
        guard let textureA = device.makeTexture(descriptor: descriptor),
              let textureB = device.makeTexture(descriptor: descriptor) else {
                fatalError("The textures couldn't be created.")
        }
        
        return (textureA, textureB)
    }
    
    static func loadTexture(device: MTLDevice, name: String) -> MTLTexture {
        let textureLoader = MTKTextureLoader(device: device)
        
        let options = [MTKTextureLoader.Option.SRGB: false]
        
        guard let texture = try? textureLoader.newTexture(name: name, scaleFactor: 1.0, bundle: Bundle.main, options: options) else {
            fatalError("Could not load the source image.")
        }
        
        return texture
    }
}

// MTKView uses the delegate pattern to inform your app when it should draw
extension Renderer: MTKViewDelegate {
    /**
     This function is where you can update any parameters that are relative to the size of the view.
     It is unused in this application but still required for protocol conformance.
    */
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    /// In the draw function I write directly to the texture of the current drawable using a compute shader.
    func draw(in view: MTKView) {

        let commandBuffer = self.metal.queue.makeCommandBuffer()!
        
        for _ in 0...1 {
            pingPong(commandBuffer: commandBuffer)
        }
        
        if reset {
            // This function simply uses a compute shader to set
            // the rg components of the Ping-pong textures to 0
            reset(commandBuffer: commandBuffer)
            reset = false
        }
        
        if let drawable = view.currentDrawable {
            render(commandBuffer: commandBuffer, drawable: drawable.texture)
            
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
    
    func pingPong(commandBuffer: MTLCommandBuffer) {
        let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
        computeEncoder.setComputePipelineState(states.compute)
        
        computeEncoder.setTexture(textures.read, index: textureBufferIndex[0])
        computeEncoder.setTexture(textures.write, index: textureBufferIndex[1])
        computeEncoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        
        // Declare the number of threads per thread group and threads per grid
        var width = states.compute.threadExecutionWidth
        var height = states.compute.maxTotalThreadsPerThreadgroup / width
        let threadsPerThreadGroup = MTLSizeMake(width, height, 1)
        
        width = Int(textures.read.width)
        height = Int(textures.read.height)
        let threadsPerGrid = MTLSizeMake(width, height, 1)
        
        computeEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadGroup)
        computeEncoder.endEncoding()
        
        textureBufferIndex.swapAt(0, 1)
    }
    
    func render(commandBuffer: MTLCommandBuffer, drawable: MTLTexture) {
        let renderEncoder = commandBuffer.makeComputeCommandEncoder()!
        renderEncoder.setComputePipelineState(states.render)
        
        renderEncoder.setTexture(image, index: 0)
        renderEncoder.setTexture(drawable, index: 1)
        renderEncoder.setTexture(textures.read, index: 2)
        
        renderEncoder.setSamplerState(textureSampler, index: 0)

        // Declare the number of threads per thread group and threads per grid
        var width = states.render.threadExecutionWidth
        var height = states.render.maxTotalThreadsPerThreadgroup / width
        let threadsPerThreadGroup = MTLSizeMake(width, height, 1)
        
        // Since we
        width = Int(drawable.width)
        height = Int(drawable.height)
        let threadsPerGrid = MTLSizeMake(width, height, 1)

        renderEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadGroup)
        renderEncoder.endEncoding()
    }
    
    func reset(commandBuffer: MTLCommandBuffer) {
        let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
        computeEncoder.setComputePipelineState(states.reset)
        
        computeEncoder.setTexture(textures.read, index: 0)
        computeEncoder.setTexture(textures.write, index: 1)
        
        // Declare the number of threads per thread group and threads per grid
        var width = states.compute.threadExecutionWidth
        var height = states.compute.maxTotalThreadsPerThreadgroup / width
        let threadsPerThreadGroup = MTLSizeMake(width, height, 1)
        
        width = Int(textures.read.width)
        height = Int(textures.read.height)
        let threadsPerGrid = MTLSizeMake(width, height, 1)
        
        computeEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadGroup)
        computeEncoder.endEncoding()
    }
}
