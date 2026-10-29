import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    // Szerokie okno (od 900 dp) wlacza uklad desktopowy ekranu glownego;
    // pozostale ekrany sa kolumna telefonu (390 dp).
    self.title = "NEUROtchi"
    self.contentMinSize = NSSize(width: 390, height: 640)
    self.setContentSize(NSSize(width: 1100, height: 780))
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
