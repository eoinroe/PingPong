import Cocoa
import MetalKit

class ViewController: NSViewController {
    @IBOutlet weak var metalView: MTKView!
    
    var renderer: Renderer?

    override func viewDidLoad() {
        super.viewDidLoad()
        
        renderer = Renderer(view: metalView)
    }
    
    @IBAction func adjustNoiseScale(sender: NSSlider) {
        self.renderer?.uniforms.noiseScale = sender.floatValue
    }
    
    @IBAction func adjustOffset(sender: NSSlider) {
        // 0.0002 was the original value used to scale the noise offset
        self.renderer?.uniforms.noiseOffset = sender.floatValue * 0.0002
    }
    
    @IBAction func resetTextures(sender: NSButton) {
        self.renderer?.reset = (sender.state == .on) ? true : false
        sender.state = .off
    }
}
