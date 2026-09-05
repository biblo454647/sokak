import SwiftUI

private let ink = Color(red: 0.055, green: 0.09, blue: 0.10)
private let pearl = Color(red: 0.89, green: 0.93, blue: 0.91)
private let sea = Color(red: 0.65, green: 0.82, blue: 0.80)

struct MenuView: View {
    @ObservedObject var model: AppModel
    var height: CGFloat = 710
    var body: some View {
        VStack(spacing: 0) {
            if model.libraryVisible { library } else { controls }
            footer
        }
        .frame(width: 390, height: height)
        .background(ink)
        .foregroundStyle(pearl)
        .tint(sea)
        .preferredColorScheme(.dark)
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                hero
                HStack(spacing: 8) {
                    ForEach(Weather.allCases) { weather in
                        Button { model.chooseWeather(weather) } label: {
                            VStack(spacing: 7) {
                                Image(systemName: weather.symbol).font(.system(size: 22, weight: .light))
                                Text(weather.title).font(.system(size: 12, weight: .medium))
                            }
                            .frame(maxWidth: .infinity).frame(height: 67)
                            .foregroundStyle(model.preferences.weather == weather ? ink : pearl.opacity(0.7))
                            .background(model.preferences.weather == weather ? sea : Color.white.opacity(0.045))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(weather.title) weather")
                        .accessibilityAddTraits(model.preferences.weather == weather ? [.isSelected] : [])
                    }
                }
                VStack(alignment: .leading, spacing: 9) {
                    eyebrow("YOUR VIEW")
                    Picker("Backdrop", selection: $model.preferences.backdrop) {
                        Text("Over my windows").tag(Backdrop.desktop)
                        Text("An Istanbul street").tag(Backdrop.istanbul)
                    }.pickerStyle(.segmented).labelsHidden()
                    if model.preferences.backdrop == .istanbul {
                        Button { model.libraryVisible = true } label: {
                            HStack(spacing: 10) {
                                if let scene = model.scene, let image = model.thumbnail(scene) {
                                    Image(nsImage: image).resizable().scaledToFill().frame(width: 48, height: 37).clipped().cornerRadius(6)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(model.scene?.title ?? "Choose a street").font(.system(size: 12, weight: .semibold))
                                    Text(model.scene?.subtitle ?? "Offline photograph library").font(.system(size: 10)).foregroundStyle(pearl.opacity(0.55))
                                }
                                Spacer()
                                Image(systemName: "square.grid.2x2").foregroundStyle(sea)
                            }.padding(9).background(Color.white.opacity(0.045)).cornerRadius(10)
                        }.buttonStyle(.plain).accessibilityLabel("Choose Istanbul photograph")
                    } else {
                        Text("Weather floats above your work. Click and type as usual.")
                            .font(.system(size: 10)).foregroundStyle(pearl.opacity(0.5))
                    }
                }
                VStack(spacing: 11) {
                    slider("Intensity", symbol: "drop", value: $model.preferences.intensity, ending: model.preferences.intensity < 0.33 ? "Light" : model.preferences.intensity < 0.7 ? "Steady" : "Heavy")
                    slider("Wind", symbol: "wind", value: $model.preferences.wind, ending: model.preferences.wind < 0.33 ? "Calm" : model.preferences.wind < 0.7 ? "Breezy" : "Gusty")
                }
                Divider().overlay(Color.white.opacity(0.05))
                VStack(spacing: 10) {
                    HStack {
                        Image(systemName: model.preferences.sound ? "speaker.wave.2" : "speaker.slash").frame(width: 20).foregroundStyle(sea)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Ambient sound").font(.system(size: 12, weight: .medium))
                            Text(model.preferences.weather.soundDescription).font(.system(size: 10)).foregroundStyle(pearl.opacity(0.5))
                        }
                        Spacer()
                        Toggle("Ambient sound", isOn: $model.preferences.sound).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                    if model.preferences.sound {
                        slider("Volume", symbol: "speaker.wave.1", value: $model.preferences.volume, ending: "\(Int(model.preferences.volume * 100))%")
                    }
                }
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        eyebrow("DISPLAY")
                        Picker("Display", selection: $model.preferences.display) {
                            Text("Current display").tag("current")
                            Text("All displays").tag("all")
                            ForEach(model.displays, id: \.id) { display in Text(display.name).tag(display.id) }
                        }.labelsHidden().controlSize(.small)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        eyebrow("SLEEP TIMER")
                        Picker("Sleep timer", selection: $model.preferences.timerMinutes) {
                            Text("No timer").tag(0)
                            ForEach([15,30,60,120], id: \.self) { Text("\($0) min").tag($0) }
                        }.labelsHidden().controlSize(.small)
                    }
                }
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Low power · 30 fps", isOn: $model.preferences.economical)
                        Toggle("Match photos to the season", isOn: $model.preferences.matchSeason)
                        slider("Dimming", symbol: "moon", value: $model.preferences.dimming, ending: "\(Int(model.preferences.dimming * 100))%", range: 0...0.65)
                        Text("Pauses when your screen sleeps or your session locks. ⌃⌥⌘S starts or stops; ⌃⌥⌘M mutes.")
                            .font(.system(size: 10)).foregroundStyle(pearl.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
                    }.font(.system(size: 11)).toggleStyle(.switch).controlSize(.mini).padding(.top, 9)
                } label: { Text("A few little details").font(.system(size: 11)).foregroundStyle(pearl.opacity(0.6)) }
                if let error = model.error {
                    Text(error).font(.system(size: 11)).foregroundStyle(Color(red: 1, green: 0.75, blue: 0.57)).fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    model.toggle()
                    if model.running { model.closePopover?() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: model.running ? "pause.fill" : "play.fill").font(.system(size: 11))
                        Text(model.running ? "Pause for now" : "Let the weather in").font(.system(size: 13, weight: .semibold))
                        if let remaining = model.remaining { Text("· \((remaining + 59) / 60)m left").font(.system(size: 11)) }
                    }.frame(maxWidth: .infinity).frame(height: 43).background(sea).foregroundStyle(ink).cornerRadius(11)
                }.buttonStyle(.plain).accessibilityLabel(model.running ? "Pause weather" : "Start weather")
            }.padding(20)
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            if let scene = model.scene, let image = model.thumbnail(scene) {
                Image(nsImage: image).resizable().scaledToFill().frame(width: 350, height: 108).clipped()
            }
            LinearGradient(colors: [.black.opacity(0.12), ink.opacity(0.94)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .lastTextBaseline) {
                    Text("sokak").font(.system(size: 31, weight: .regular, design: .serif)).tracking(-0.8)
                    Spacer()
                    HStack(spacing: 5) {
                        Circle().fill(model.running ? sea : pearl.opacity(0.4)).frame(width: 5, height: 5)
                        Text(model.running ? "A MOMENT AWAY" : "A QUIETER MOMENT").font(.system(size: 8, weight: .semibold)).tracking(1.1)
                    }.foregroundStyle(pearl.opacity(0.8))
                }
                Text("A little weather. A little home.").font(.system(size: 11)).foregroundStyle(pearl.opacity(0.75))
            }.padding(15)
        }.frame(height: 108).clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button { model.libraryVisible = false } label: { Label("Back", systemImage: "chevron.left") }.buttonStyle(.plain)
                Spacer()
                Button { model.importPhoto() } label: { Label("Your photo", systemImage: "plus") }.buttonStyle(.plain)
            }.font(.system(size: 12)).foregroundStyle(sea)
            VStack(alignment: .leading, spacing: 5) {
                Text("Somewhere familiar.").font(.system(size: 26, weight: .regular, design: .serif))
                Text("Real Istanbul photographs, kept here offline.").font(.system(size: 11)).foregroundStyle(pearl.opacity(0.6))
            }
            Picker("Photo season", selection: $model.winterOnly) {
                Text("All streets").tag(false)
                Text("Winter streets").tag(true)
            }.pickerStyle(.segmented).labelsHidden()
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 13) {
                    ForEach(model.scenes.filter { !model.winterOnly || $0.winter }) { scene in
                        Button { model.select(scene) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                ZStack(alignment: .topTrailing) {
                                    if let image = model.thumbnail(scene) {
                                        Image(nsImage: image).resizable().scaledToFill().frame(width: 166, height: 108).clipped()
                                    }
                                    if scene.winter { Image(systemName: "snowflake").font(.system(size: 10, weight: .bold)).padding(6).background(.black.opacity(0.5)).clipShape(Circle()).padding(6) }
                                    if model.preferences.sceneID == scene.id {
                                        RoundedRectangle(cornerRadius: 8).stroke(sea, lineWidth: 3)
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(sea).padding(6).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                                    }
                                }.frame(height: 108).clipShape(RoundedRectangle(cornerRadius: 8))
                                Text(scene.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                Text(scene.subtitle).font(.system(size: 10)).foregroundStyle(pearl.opacity(0.6)).lineLimit(1)
                                Text(scene.resolution).font(.system(size: 9, design: .monospaced)).foregroundStyle(pearl.opacity(0.4))
                            }.frame(width: 166, alignment: .leading)
                        }.buttonStyle(.plain).accessibilityLabel("\(scene.title), \(scene.subtitle), \(scene.resolution)\(model.preferences.sceneID == scene.id ? ", selected" : "")")
                    }
                }.padding(.vertical, 3)
            }
            if let scene = model.scene {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(scene.title) · \(scene.subtitle)").font(.system(size: 11, weight: .medium))
                    Text("Photo: \(scene.author) · \(scene.license)").font(.system(size: 9)).foregroundStyle(pearl.opacity(0.55)).lineLimit(2)
                    if let url = URL(string: scene.sourceURL), url.scheme == "https" {
                        Link("Photograph & license ↗", destination: url).font(.system(size: 10)).foregroundStyle(sea)
                    }
                }
            }
            Button { model.libraryVisible = false; model.preferences.backdrop = .istanbul } label: {
                Text("Stay on this street").font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 39).foregroundStyle(ink).background(sea).cornerRadius(10)
            }.buttonStyle(.plain)
        }.padding(20)
    }

    private var footer: some View {
        HStack {
            Text("İSTANBUL, AT YOUR PACE").font(.system(size: 8, weight: .medium)).tracking(1.25).foregroundStyle(pearl.opacity(0.35))
            Spacer()
            Menu {
                Button("Browse Istanbul photographs") { model.libraryVisible = true }
                Button("Add your own photograph…") { model.importPhoto() }
                Button("Photograph credits") { NSWorkspace.shared.open(Assets.root.appendingPathComponent("PHOTO-CREDITS.md")) }
                Button("Help & installation") { NSWorkspace.shared.open(Assets.root.appendingPathComponent("HELP.html")) }
                Divider()
                Button("Quit Sokak") { NSApp.terminate(nil) }
            } label: { Image(systemName: "ellipsis.circle").font(.system(size: 15)).foregroundStyle(pearl.opacity(0.55)) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 20).accessibilityLabel("Help and more")
        }.padding(.horizontal, 20).frame(height: 35)
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text).font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundStyle(pearl.opacity(0.45))
    }
    private func slider(_ title: String, symbol: String, value: Binding<Double>, ending: String, range: ClosedRange<Double> = 0...1) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(sea.opacity(0.8)).frame(width: 20)
            Text(title).font(.system(size: 11)).frame(width: 49, alignment: .leading)
            Slider(value: value, in: range).controlSize(.mini).accessibilityLabel(title)
            Text(ending).font(.system(size: 10, design: .monospaced)).foregroundStyle(pearl.opacity(0.5)).frame(width: 40, alignment: .trailing)
        }
    }
}
