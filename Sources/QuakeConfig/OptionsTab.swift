import SwiftUI

// MARK: - Widoki

struct OptionRow: View {
    @ObservedObject var model: ConfigModel
    let option: CvarOption

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            control
            if let help = option.help {
                Text(help).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var control: some View {
        switch option.kind {
        case .toggle(let on, let off):
            Toggle(option.label, isOn: model.boolBinding(option, on: on, off: off))
        case .slider(let range, let step):
            HStack {
                Text(option.label)
                Spacer()
                Slider(value: model.doubleBinding(option), in: range, step: step).frame(width: 200)
                Text(model.values[option.cvar] ?? option.defaultValue)
                    .monospacedDigit().frame(width: 48, alignment: .trailing)
            }
        case .choice(let items):
            Picker(option.label, selection: model.stringBinding(option)) {
                ForEach(items) { Text($0.label).tag($0.value) }
            }
        case .text(let placeholder):
            HStack {
                Text(option.label)
                Spacer()
                TextField(placeholder, text: model.stringBinding(option))
                    .frame(width: 200).multilineTextAlignment(.trailing)
            }
        }
    }
}

struct OptionsTab: View {
    @ObservedObject var model: ConfigModel
    let sections: [String]

    var body: some View {
        Form {
            ForEach(sections, id: \.self) { section in
                Section(section) {
                    ForEach(ALL_OPTIONS.filter { $0.section == section }) { option in
                        OptionRow(model: model, option: option)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Podgląd tekstu prawdziwą czcionką konsoli Quake'a, na czarnym tle jak w grze.
struct QuakeTextPreview: View {
    let text: String
    let font: QuakeFont?
    var scale: CGFloat = 3

    var body: some View {
        HStack {
            if let font, let image = font.image(for: text) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: image.size.width * scale, height: image.size.height * scale)
            } else {
                Text(text.isEmpty ? " " : text)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.white)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
