import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    // Ekrany sa projektowane pod kolumne telefonu (390 dp), wiec okno ma taki ksztalt.
    self.title = "NEUROtchi"
    self.contentMinSize = NSSize(width: 390, height: 640)
    self.setContentSize(NSSize(width: 430, height: 900))
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
