import Foundation

/// A curated, hand-picked list of popular SF Symbols, grouped by category.
///
/// Apple doesn't expose a public API to enumerate all ~6,000 SF Symbols, so
/// `SymbolPickerView`'s "SF Symbols" source browses this static list instead
/// (docs/FEATURES.md section 2, "all ~6,000 SF Symbols via system APIs" — approximated
/// here with the ~400 most broadly useful names for folder overlays). Every
/// name below is a base or `.fill` symbol available since SF Symbols 2/3
/// (macOS 11-12), matching this app's macOS 14+ minimum deployment target.
struct SFSymbolCategory: Identifiable {
    let name: String
    let symbols: [String]
    var id: String { name }
}

enum SFSymbolCatalog {
    static let categories: [SFSymbolCategory] = [
        SFSymbolCategory(name: "Objects", symbols: [
            "folder", "folder.fill", "doc", "doc.fill", "doc.text", "doc.on.doc",
            "trash", "trash.fill", "archivebox", "archivebox.fill",
            "tray", "tray.fill", "tray.full", "externaldrive", "internaldrive",
            "opticaldiscdrive", "printer", "scanner",
            "briefcase", "briefcase.fill", "suitcase", "suitcase.fill",
            "bag", "bag.fill", "cart", "cart.fill",
            "creditcard", "creditcard.fill", "wallet.pass", "gift", "gift.fill",
            "cube", "cube.fill", "shippingbox", "shippingbox.fill",
            "book", "book.fill", "books.vertical", "books.vertical.fill",
            "bookmark", "bookmark.fill", "newspaper", "newspaper.fill",
            "graduationcap", "graduationcap.fill",
            "pencil", "pencil.circle", "highlighter", "eraser", "ruler",
            "paperclip", "paperplane", "paperplane.fill", "scissors",
            "lock", "lock.fill", "lock.open", "lock.open.fill", "key", "key.fill",
            "gearshape", "gearshape.fill", "gearshape.2",
            "wrench", "wrench.fill", "hammer", "hammer.fill", "screwdriver",
            "paintbrush", "paintbrush.fill", "eyedropper", "wand.and.stars",
            "puzzlepiece", "puzzlepiece.fill",
            "flag", "flag.fill", "flag.checkered",
            "pin", "pin.fill", "mappin", "mappin.circle", "mappin.circle.fill",
            "map", "map.fill", "location", "location.fill", "location.north",
            "safari", "compass.drawing", "globe", "network",
            "antenna.radiowaves.left.and.right",
        ]),
        SFSymbolCategory(name: "Arrows", symbols: [
            "arrow.up", "arrow.down", "arrow.left", "arrow.right",
            "arrow.up.left", "arrow.up.right", "arrow.down.left", "arrow.down.right",
            "arrow.up.circle", "arrow.down.circle", "arrow.left.circle", "arrow.right.circle",
            "arrow.up.circle.fill", "arrow.down.circle.fill",
            "arrow.left.circle.fill", "arrow.right.circle.fill",
            "arrow.clockwise", "arrow.counterclockwise",
            "arrow.triangle.2.circlepath", "arrow.up.arrow.down", "arrow.left.arrow.right",
            "arrow.uturn.left", "arrow.uturn.right", "arrow.uturn.up", "arrow.uturn.down",
            "arrowshape.turn.up.left", "arrowshape.turn.up.right",
            "chevron.up", "chevron.down", "chevron.left", "chevron.right",
            "chevron.up.chevron.down", "chevron.left.chevron.right",
            "arrow.up.and.down", "arrow.left.and.right",
            "arrow.up.to.line", "arrow.down.to.line",
            "repeat", "shuffle", "arrow.turn.up.right", "arrow.turn.down.right",
            "arrow.merge", "arrow.triangle.branch", "arrow.up.right.circle",
            "arrow.up.forward", "arrow.down.backward",
        ]),
        SFSymbolCategory(name: "People", symbols: [
            "person", "person.fill", "person.2", "person.2.fill",
            "person.3", "person.3.fill",
            "person.circle", "person.circle.fill",
            "person.crop.circle", "person.crop.square",
            "figure.walk", "figure.run", "figure.wave", "figure.stand",
            "figure.rolling", "figure.child",
            "hand.raised", "hand.raised.fill",
            "hand.thumbsup", "hand.thumbsup.fill", "hand.thumbsdown", "hand.thumbsdown.fill",
            "hand.wave", "hand.point.up", "hand.point.right",
            "eye", "eye.fill", "eye.slash", "ear", "nose", "mouth", "brain",
            "person.badge.plus", "person.badge.minus", "crown", "crown.fill",
        ]),
        SFSymbolCategory(name: "Media", symbols: [
            "play", "play.fill", "pause", "pause.fill", "stop", "stop.fill",
            "backward", "backward.fill", "forward", "forward.fill",
            "backward.end", "forward.end", "record.circle",
            "speaker", "speaker.fill", "speaker.wave.1", "speaker.wave.2",
            "speaker.wave.3", "speaker.slash",
            "mic", "mic.fill", "mic.slash", "headphones",
            "music.note", "music.note.list", "music.mic", "waveform",
            "film", "film.fill", "tv", "tv.fill",
            "camera", "camera.fill", "camera.rotate",
            "video", "video.fill",
            "photo", "photo.fill", "photo.on.rectangle",
            "square.and.arrow.up", "square.and.arrow.down",
            "airplayvideo", "airplayaudio",
        ]),
        SFSymbolCategory(name: "Tools", symbols: [
            "wrench.and.screwdriver", "level", "toolbox", "gauge",
            "stethoscope", "syringe", "cross.case",
            "bandage", "pills", "testtube.2", "flask", "atom",
            "leaf", "flame", "flame.fill", "bolt", "bolt.fill",
            "battery.100", "battery.25", "powerplug",
            "lightbulb", "lightbulb.fill", "lamp.desk", "fan", "thermometer",
        ]),
        SFSymbolCategory(name: "Transport", symbols: [
            "car", "car.fill", "car.side", "bus", "bus.fill",
            "tram", "tram.fill", "bicycle", "figure.outdoor.cycle",
            "airplane", "sailboat", "sailboat.fill",
            "ferry", "ferry.fill",
            "fuelpump", "fuelpump.fill", "steeringwheel",
            "truck.box", "bus.doubledecker",
            "train.side.front.car", "scooter", "parkingsign",
        ]),
        SFSymbolCategory(name: "Nature", symbols: [
            "sun.max", "sun.max.fill", "moon", "moon.fill", "moon.stars",
            "cloud", "cloud.fill", "cloud.rain", "cloud.rain.fill",
            "cloud.snow", "cloud.bolt", "cloud.bolt.fill",
            "wind", "tornado", "hurricane", "snowflake",
            "drop", "drop.fill", "flame.circle",
            "leaf.fill", "tree", "tortoise", "hare",
            "pawprint", "pawprint.fill", "ant", "ladybug",
            "fish", "fish.fill", "bird", "bird.fill", "cat", "cat.fill", "dog", "dog.fill",
            "mountain.2", "mountain.2.fill",
        ]),
        SFSymbolCategory(name: "Health", symbols: [
            "heart", "heart.fill", "heart.circle", "heart.circle.fill",
            "cross", "cross.fill", "cross.circle",
            "bandage.fill", "pills.fill",
            "figure.strengthtraining.traditional", "figure.yoga", "figure.pool.swim",
            "sportscourt", "dumbbell", "dumbbell.fill",
            "figure.cooldown", "bed.double", "bed.double.fill",
            "lungs", "lungs.fill", "waveform.path.ecg", "brain.head.profile",
        ]),
        SFSymbolCategory(name: "Food", symbols: [
            "fork.knife", "fork.knife.circle",
            "cup.and.saucer", "cup.and.saucer.fill",
            "wineglass", "wineglass.fill", "mug", "mug.fill",
            "birthday.cake", "carrot", "carrot.fill",
            "takeoutbag.and.cup.and.straw", "popcorn", "fish.fill",
        ]),
        SFSymbolCategory(name: "Communication", symbols: [
            "message", "message.fill", "bubble.left", "bubble.left.fill",
            "bubble.right", "bubble.right.fill", "bubble.left.and.bubble.right",
            "phone", "phone.fill", "phone.circle", "phone.circle.fill",
            "envelope", "envelope.fill", "envelope.open",
            "at", "number", "bell", "bell.fill", "bell.slash",
            "megaphone", "megaphone.fill", "quote.bubble",
        ]),
        SFSymbolCategory(name: "Devices", symbols: [
            "desktopcomputer", "laptopcomputer", "keyboard", "computermouse",
            "printer.fill", "server.rack", "wifi", "cpu", "memorychip",
            "sdcard", "simcard", "iphone", "ipad", "applewatch",
            "airpods", "homepod", "display", "tv.and.mediabox",
            "gamecontroller", "gamecontroller.fill",
        ]),
        SFSymbolCategory(name: "Home", symbols: [
            "house", "house.fill", "building", "building.fill",
            "building.2", "building.2.fill", "building.columns", "building.columns.fill",
            "storefront", "storefront.fill", "sofa", "sofa.fill",
            "lamp.floor", "lamp.floor.fill", "door.left.hand.open",
            "window.horizontal", "stairs", "tent", "tent.fill", "signpost.right",
        ]),
        SFSymbolCategory(name: "Time", symbols: [
            "clock", "clock.fill", "alarm", "alarm.fill",
            "timer", "stopwatch", "stopwatch.fill",
            "calendar", "calendar.circle", "calendar.circle.fill", "hourglass",
        ]),
        SFSymbolCategory(name: "Shapes", symbols: [
            "star", "star.fill", "star.circle", "star.circle.fill",
            "circle", "circle.fill", "square", "square.fill",
            "triangle", "triangle.fill", "diamond", "diamond.fill",
            "hexagon", "hexagon.fill", "seal", "seal.fill",
            "checkmark", "checkmark.circle", "checkmark.circle.fill", "checkmark.seal",
            "xmark", "xmark.circle", "xmark.circle.fill",
            "plus", "plus.circle", "plus.circle.fill",
            "minus", "minus.circle",
            "exclamationmark", "exclamationmark.triangle", "exclamationmark.circle",
            "questionmark", "questionmark.circle", "infinity", "asterisk",
        ]),
        SFSymbolCategory(name: "Text", symbols: [
            "textformat", "bold", "italic", "underline", "strikethrough",
            "textformat.size", "list.bullet", "list.number",
            "text.alignleft", "text.aligncenter", "text.alignright",
            "doc.text.magnifyingglass", "magnifyingglass", "magnifyingglass.circle",
        ]),
    ]

    /// Flattened, de-duplicated list of every symbol name across categories,
    /// used by the picker's search field.
    static let all: [String] = {
        var seen = Set<String>()
        var result: [String] = []
        for category in categories {
            for symbol in category.symbols where seen.insert(symbol).inserted {
                result.append(symbol)
            }
        }
        return result
    }()
}
