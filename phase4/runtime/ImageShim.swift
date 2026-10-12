import SwiftUI
import UIKit
// Native Swift calling convention and SwiftUI return-value handling are emitted
// by the host compiler. The object is our NSImage compatibility representation.
@_silgen_name("$s7SwiftUI5ImageV02nsC0ACSo7NSImageC_tcfC")
public func mpImageFromNSImage(_ image: MPCompatImage) -> Image {
    Image(uiImage: image.uiImage)
}
@_silgen_name("$sSo7NSSoundC6AppKitE4beepyyFZ")
public func mpSoundBeep() { MPCompatSound.beep() }
