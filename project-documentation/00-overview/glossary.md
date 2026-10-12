# Glossary

| Term | Meaning in this project |
|---|---|
| **AGX** | Apple's GPU family and its driver. The Mac and the iPhone both use it, which is why Metal can be passed through. |
| **App ID / bundle ID** | The identity of an iOS app (e.g. `research.machprobe.CP2077`). The app's data folder belongs to it; installing another app under the same ID can replace or wipe that data. |
| **AppKit** | The macOS UI framework (`NSApplication`, `NSWindow`, `NSEvent`). It doesn't exist on iOS; machprobe implements the parts games use on top of **UIKit**. |
| **arm64** | The 64-bit ARM instruction set used by Apple-silicon Macs and iPhones. Same instructions on both, so no emulation. |
| **Autorelease pool** | Objective-C's deferred-free mechanism. Objects are released when the pool drains; a loop with no pool can grow memory. |
| **Chained fixups** | Modern Mach-O format for pointers that must be adjusted (rebased) or bound to symbols at load time. The loader walks these chains. |
| **Container (guest container)** | A signed iOS dylib that carries an untouched game image inside a `__TEXT,__guest` section, so iOS code signing accepts it. |
| **devicectl** | Xcode's command-line tool for installing apps and copying files to a phone over USB. |
| **dyld** | Apple's dynamic linker. machprobe's loader does dyld's job for guest images. |
| **Entitlement** | A permission baked into the signature, e.g. `com.apple.developer.kernel.increased-memory-limit`. |
| **Export trie** | The compressed lookup structure in a Mach-O that lists the symbols an image exports. |
| **Footprint (phys_footprint)** | The memory number iOS uses to decide when to kill an app. Purgeable volatile memory isn't counted. |
| **Guest** | The unmodified macOS program being run (the game). |
| **Host** | The signed iOS app that contains machprobe and the guest (`CP2077Host`). |
| **Initializer** | Code that runs before `main` (C++ static constructors, `+load`). Listed in `__init_offsets`. |
| **Interpose / policy** | Replacing a function the guest imports (e.g. `mmap`, `sysctlbyname`) with machprobe's own version. |
| **Jetsam** | iOS's memory killer. When an app's footprint passes its limit, the app is killed without a crash report. |
| **Mach-O** | The executable format of macOS and iOS. |
| **Metal heap** | A large GPU memory block that resources are carved from. iOS charges the whole heap to the app, so machprobe grows heaps on demand. |
| **MetalFX** | Apple's upscaler. Deliberately *not* used: the goal is real optimization at native resolution. |
| **Provisioning profile** | The file that allows an app signed by a developer to run on specific devices. Free accounts get 7-day profiles. |
| **RED Engine** | Cyberpunk 2077's engine. Its allocator reserves 16/64/32 GB address regions up front. |
| **Sideloading** | Installing an app outside the App Store, here with a free developer profile over USB. |
| **TLS / TLV** | Thread-local storage / thread-local variables. Each thread gets its own copy; Mach-O uses descriptors with a thunk function. |
| **TPIDRRO_EL0** | ARM register holding the current thread's pointer; used by the TLS fast path. |
| **UIKit** | The iOS UI framework. |
| **VA (virtual address) space** | The range of addresses a process can use. iOS gives an app about 64 GB plus a little low memory, much less than macOS. |
| **VM tag** | A label on memory regions (2 = `MALLOC_SMALL`, 100 = `IOACCELERATOR` GPU memory). Used to see where RAM goes. |
| **vphone / iOS VM** | The virtual iPhone used in phases 2–6 before moving to the physical phone. |
| **VSync list** | Cyberpunk's dynamic list of valid VSync values on this display ("120", "30", …). Writing an invalid value like "60" silently caps the game at 30 fps. |
