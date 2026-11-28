import SwiftUI

// MARK: - Preview Studio
//
// An isolated sandbox: mix & match any item (owned or not), tap the real tap
// button skin, fire PERFECT / MISS / life lost / game over effects and sounds.
//
// Isolation contract (INTEGRATION_CONTRACT §3 rule 5, tested in CosmeticShopTests):
//  * no GameViewModel, no scoring, no stats / coins / quests / achievements /
//    leaderboards / analytics economy events;
//  * the draft loadout lives only in `CosmeticPreviewModel`; the stored loadout
//    and `ownedItems` change only through an explicit "Equip owned" or a
//    confirmed purchase;
//  * preview sounds are stopped when the sheet disappears.

/// What the Studio asks the sheet to start with.
struct CosmeticPreviewRequest: Identifiable {
    enum Focus {
        case equipped
        case item(CosmeticItem)
        case collection(CosmeticCollection)
    }

    let id = UUID()
    var focus: Focus = .equipped
}

@MainActor
final class CosmeticPreviewModel: ObservableObject {

    static let maxLives = 3

    @Published private(set) var draft: CosmeticLoadout
    @Published private(set) var lives = CosmeticPreviewModel.maxLives
    @Published private(set) var trigger: CosmeticEffectTrigger?
    /// Fires the pre-Studio particles when the Classic PERFECT effect is drafted.
    @Published private(set) var legacyParticleTrigger = UUID()
    @Published private(set) var legacyParticleAccuracy: TapAccuracy?

    /// The loadout the sheet opened with (what the player has equipped).
    let startingLoadout: CosmeticLoadout

    private var sequence = 0
    private let playSound: (CosmeticEvent, String) -> Void
    private let stopSound: () -> Void
    private let playHaptic: (CosmeticEvent, String) -> Void

    init(start: CosmeticLoadout,
         playSound: @escaping (CosmeticEvent, String) -> Void = { SoundEngine.shared.previewSound($0, packID: $1) },
         stopSound: @escaping () -> Void = { SoundEngine.shared.stopPreview() },
         playHaptic: @escaping (CosmeticEvent, String) -> Void = { event, style in
             if let outcome = HapticsEngine.previewOutcome(for: event) {
                 HapticsEngine.shared.previewTapOutcome(outcome, styleID: style)
             }
         }) {
        self.startingLoadout = start
        self.draft = start
        self.playSound = playSound
        self.stopSound = stopSound
        self.playHaptic = playHaptic
    }

    /// Starts from what gameplay renders now (ownership-validated), then applies the focus.
    convenience init(equipped: ResolvedCosmetics, focus: CosmeticPreviewRequest.Focus = .equipped) {
        var loadout = CosmeticLoadout()
        for slot in CosmeticSlot.allCases { loadout.selections[slot] = equipped.item(for: slot).id }
        self.init(start: loadout)
        switch focus {
        case .equipped: break
        case .item(let item): draft.select(item)
        case .collection(let collection): draft.apply(collection: collection)
        }
    }

    /// The draft resolved WITHOUT ownership checks (preview only).
    var resolved: ResolvedCosmetics { CosmeticLoadoutStore.previewResolved(draft) }

    func item(for slot: CosmeticSlot) -> CosmeticItem { resolved.item(for: slot) }

    func isSelected(_ item: CosmeticItem) -> Bool { draft.itemID(for: item.slot) == item.id }

    // MARK: Draft editing (never persisted)

    func select(_ item: CosmeticItem) {
        draft.select(item)
        // Immediate feedback for what was just picked.
        switch item.slot {
        case .tapSound:       fire(.perfect)
        case .tapEffect:      fire(.good)
        case .perfectEffect:  fire(.perfect)
        case .missEffect:     fire(.miss)
        case .lifeLostEffect: fire(.lifeLost)
        case .gameOverEffect: fire(.gameOver)
        case .tapButton, .lifeIcon, .haptics: break
        }
    }

    func tryCollection(_ collection: CosmeticCollection) {
        draft.apply(collection: collection)
        fire(.perfect)
    }

    func resetDraft() {
        draft = startingLoadout
        resetLives()
    }

    // MARK: Mock gameplay moments (QA-08: the preview plays what gameplay plays)

    /// The gameplay moment a preview control imitates. Gameplay never emits
    /// `.tap` (every scored tap has a grade), so the tap button stands for a
    /// GOOD tap — the most common real tap.
    static func gameplayEvent(forPreview event: CosmeticEvent) -> CosmeticEvent {
        event == .tap ? .good : event
    }

    /// The scored-tap outcome gameplay would hand the audio policy for `event`
    /// (nil for game over, which is not a tap).
    static func gameplayOutcome(for event: CosmeticEvent) -> TapSoundOutcome? {
        switch gameplayEvent(forPreview: event) {
        case .tap, .good: return TapSoundOutcome(accuracy: .good)
        case .great:      return TapSoundOutcome(accuracy: .great)
        case .perfect:    return TapSoundOutcome(accuracy: .perfect)
        case .miss:       return TapSoundOutcome(accuracy: .miss)
        case .lifeLost:   return TapSoundOutcome(accuracy: .miss, lostLife: true)
        case .gameOver:   return nil
        }
    }

    /// The pack event to preview for `event`: whatever `CosmeticAudioPolicy`
    /// picks for the same gameplay moment with `packID` (nil = gameplay is
    /// silent there, e.g. the classic pack's game over). Never `.tap`.
    static func soundEvent(forPreview event: CosmeticEvent, packID: String) -> CosmeticEvent? {
        let cue: SoundCue
        if let outcome = gameplayOutcome(for: event) {
            cue = CosmeticAudioPolicy.cue(for: outcome, packID: packID)
        } else {
            cue = CosmeticAudioPolicy.gameOverCue(packID: packID)
        }
        switch cue {
        case .pack(let packEvent): return packEvent
        case .silent:              return nil
        case .tone(let tone):
            // Classic pack: previewSound maps these events back to the same tone
            // (CosmeticAudioPolicy.defaultPreviewTone).
            switch tone {
            case .perfect, .comboMilestone: return .perfect
            case .great:                    return .great
            case .miss, .comboBreak:        return .miss
            default:                        return .good
            }
        }
    }

    func fire(_ requested: CosmeticEvent) {
        let event = Self.gameplayEvent(forPreview: requested)
        sequence += 1
        trigger = CosmeticEffectTrigger(event: event, sequence: sequence)
        if event == .perfect, item(for: .perfectEffect).assets.effectStyle == .legacyParticles {
            legacyParticleAccuracy = .perfect
            legacyParticleTrigger = UUID()
        }
        let packID = resolved.soundPackID
        if let sound = Self.soundEvent(forPreview: event, packID: packID) {
            playSound(sound, packID)
        }
        // Haptic styles are sold too, so they must be feelable here (QA-03).
        playHaptic(event, resolved.hapticStyleID)
    }

    /// The preview tap button: a GOOD tap, exactly as in gameplay.
    func tap() { fire(.good) }

    func loseLife() {
        guard lives > 0 else { return }
        lives -= 1
        fire(.lifeLost)
    }

    func resetLives() { lives = Self.maxLives }

    func stop() { stopSound() }

    // MARK: Ownership split (for the bottom bar)

    /// Draft items the player does not own (defaults are always owned).
    func unownedItems(isOwned: (CosmeticItem) -> Bool) -> [CosmeticItem] {
        CosmeticSlot.allCases.map(item(for:)).filter { !$0.isDefault && !isOwned($0) }
    }

    /// Draft items that can be equipped now (owned or free defaults).
    func ownedItems(isOwned: (CosmeticItem) -> Bool) -> [CosmeticItem] {
        CosmeticSlot.allCases.map(item(for:)).filter { $0.isDefault || isOwned($0) }
    }

    /// Applies only the owned draft items, through `equip` (explicit player action).
    @discardableResult
    func equipOwned(isOwned: (CosmeticItem) -> Bool, equip: (CosmeticItem) -> Bool) -> [String] {
        ownedItems(isOwned: isOwned).filter(equip).map(\.id)
    }

    /// Draft differs from what the player has equipped.
    var hasChanges: Bool {
        CosmeticSlot.allCases.contains { draft.itemID(for: $0) != startingLoadout.itemID(for: $0) }
    }
}

// MARK: - View

struct CosmeticPreviewStudioView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.effectsLevel) private var effects
    @EnvironmentObject private var themeManager: ThemeManager
    @StateObject private var model: CosmeticPreviewModel
    @StateObject private var flow = CosmeticPurchaseFlow()
    @State private var profile: PlayerProfile = EconomyManager.shared.currentProfile()
    @State private var equipNote: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let relay: IndicatorRelay = {
        let r = IndicatorRelay()
        r.position = 0.47
        return r
    }()

    init(request: CosmeticPreviewRequest = CosmeticPreviewRequest()) {
        _model = StateObject(wrappedValue: CosmeticPreviewModel(
            equipped: CosmeticLoadoutStore.shared.resolved, focus: request.focus))
    }

    private var spendable: Int { EconomyManager.shared.service.spendableBalance(profile: profile) }
    private var fallbackColors: [Color] { [themeManager.current.barGradient.0, themeManager.current.barGradient.1] }
    private var isLarge: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        // Ownership + prices once per render (QA-17); chips read plain values.
        let state = CosmeticStudioRenderState.live(profile: profile, loadout: CosmeticLoadoutStore.shared.loadout,
                                                   spendable: spendable)
        return ZStack {
            StudioStyle.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        stage
                        momentButtons
                        collectionChips
                        ForEach(CosmeticSlot.allCases) { slot in
                            slotPicker(slot, state: state)
                        }
                        StudioDebugPriceNote()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                bottomBar(state: state)
            }
        }
        .preferredColorScheme(.dark)
        .cosmeticPurchaseFlow(flow)
        .alert(equipNote ?? "", isPresented: Binding(get: { equipNote != nil }, set: { if !$0 { equipNote = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .onAppear {
            flow.onChange = { profile = EconomyManager.shared.currentProfile() }
        }
        .onDisappear { model.stop() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("PREVIEW STUDIO")
                    .font(.subheadline.weight(.black)).tracking(3)
                    .foregroundColor(.white)
                Text("Try anything. Nothing changes until you equip or unlock.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .accessibilityLabel("Close preview")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: Mini gameplay mock (static; no GameViewModel)

    private var stage: some View {
        let resolved = model.resolved
        return VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text("SCORE").font(.caption2.weight(.bold)).foregroundColor(.white.opacity(0.4))
                    Text("1,240").font(.title3.weight(.black)).foregroundColor(.white)
                }
                .accessibilityHidden(true)
                Spacer()
                CosmeticLivesView(item: resolved.item(for: .lifeIcon), maxLives: CosmeticPreviewModel.maxLives,
                                  lives: model.lives)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Lives preview")
                    .accessibilityValue("\(model.lives) of \(CosmeticPreviewModel.maxLives)")
            }
            TapBarView(indicatorRelay: relay, theme: themeManager.current, glowStrength: effects.glowStrength)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            Button { model.tap() } label: { EmptyView() }
                .buttonStyle(SkinPressStyle(item: resolved.item(for: .tapButton), colors: fallbackColors))
                .accessibilityLabel("Tap button preview")
                .accessibilityHint("Plays what a GOOD tap plays in a game: effect, sound and haptic")
        }
        .padding(14)
        .background(themeManager.current.backgroundColor)
        .overlay(effectOverlay)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(StudioStyle.stroke))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var effectOverlay: some View {
        ZStack {
            CosmeticEffectLayer(resolved: model.resolved, trigger: model.trigger,
                                origin: origin(for: model.trigger?.event))
            if effects.showsParticles {
                ParticleEffectView(accuracy: model.legacyParticleAccuracy, trigger: model.legacyParticleTrigger,
                                   equippedFX: profile.equippedTapFX,
                                   themeColors: themeManager.current.particleColors)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Same anchors as gameplay: tap-accuracy bursts start at the button
    /// (GameView uses y 0.79), a lost life at the lives HUD.
    private func origin(for event: CosmeticEvent?) -> UnitPoint {
        switch event {
        case .lifeLost: return UnitPoint(x: 0.85, y: 0.15)
        case .gameOver: return UnitPoint(x: 0.5, y: 0.5)
        default:        return UnitPoint(x: 0.5, y: 0.78)
        }
    }

    /// One button per gameplay moment; each plays exactly what that moment
    /// plays in a game (QA-08, AUDIO_POLICY §1a).
    private var momentButtons: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: isLarge ? 1 : 3)
        return LazyVGrid(columns: columns, spacing: 8) {
            momentButton("Good", "hand.tap.fill", StudioStyle.green) { model.fire(.good) }
            momentButton("Great", "hand.thumbsup.fill", Color(red: 0.22, green: 0.58, blue: 0.98)) { model.fire(.great) }
            momentButton("Perfect", "star.fill", StudioStyle.purple) { model.fire(.perfect) }
            momentButton("Miss", "xmark.circle.fill", Color(red: 0.92, green: 0.27, blue: 0.27)) { model.fire(.miss) }
            momentButton("Lose a life", "heart.slash.fill", .pink) { model.loseLife() }
                .disabled(model.lives == 0)
            momentButton("Game Over", "flag.checkered", .white.opacity(0.7)) { model.fire(.gameOver) }
            momentButton("Reset lives", "arrow.counterclockwise", .white.opacity(0.7)) { model.resetLives() }
        }
    }

    private func momentButton(_ title: String, _ icon: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.bold))
                .foregroundColor(color)
                .lineLimit(isLarge ? 2 : 1).minimumScaleFactor(isLarge ? 1 : 0.7)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: Pickers

    private var collectionChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Try whole collection", icon: "square.stack.3d.up.fill")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CosmeticCatalog.collections) { collection in
                        Button { model.tryCollection(collection) } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(LinearGradient(colors: StudioStyle.palette(collection.palette),
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 16, height: 16)
                                Text(collection.name).font(.caption.weight(.bold)).fixedSize()
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(StudioStyle.card)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(StudioStyle.stroke))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .accessibilityLabel("Try the whole \(collection.name) collection")
                    }
                }
            }
        }
    }

    private func slotPicker(_ slot: CosmeticSlot, state: CosmeticStudioRenderState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(slot.title, icon: slot.systemImage)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CosmeticCatalog.items(in: slot).filter { $0.availability != .hidden || state.isOwned($0) }) { item in
                        chip(item, owned: state.isOwned(item), price: state.price(item))
                    }
                }
            }
        }
    }

    private func chip(_ item: CosmeticItem, owned: Bool, price: Int) -> some View {
        let selected = model.isSelected(item)
        let collectionName = CosmeticCatalog.collection(id: item.collectionID)?.name ?? ""
        return Button { model.select(item) } label: {
            VStack(spacing: 4) {
                CosmeticItemArt(item: item, fallbackColors: fallbackColors, compact: true)
                    .frame(width: 92)
                HStack(spacing: 3) {
                    if !owned { Image(systemName: "lock.fill").font(.system(size: 9, weight: .bold)) }
                    Text(item.name).lineLimit(1).minimumScaleFactor(0.7)
                }
                .font(.caption2.weight(.bold))
                .foregroundColor(owned ? .white : .white.opacity(0.6))
            }
            .padding(8)
            .frame(minWidth: 108, minHeight: 44)
            .background(selected ? StudioStyle.gold.opacity(0.12) : StudioStyle.card)
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(selected ? StudioStyle.gold.opacity(0.8) : StudioStyle.stroke, lineWidth: selected ? 2 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityLabel("\(item.name), \(collectionName)")
        .accessibilityValue(owned ? (item.isDefault ? "Free" : "Owned") : "Locked, \(CoinFormat.coins(price))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title.uppercased(), systemImage: icon)
            .font(.caption2.weight(.black)).tracking(1)
            .foregroundColor(.white.opacity(0.5))
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Bottom bar

    private func bottomBar(state: CosmeticStudioRenderState) -> some View {
        let unowned = model.unownedItems(isOwned: state.isOwned)
        let price = EconomyManager.shared.cheaperBundle(for: unowned, in: profile)?.quote.completionPrice
            ?? EconomyManager.shared.cosmeticItemsPrice(unowned, in: profile)
        let equipButton = StudioActionButton(title: "Equip owned", systemImage: "checkmark.circle.fill",
                                             color: StudioStyle.green, expand: isLarge) {
            let equipped = model.equipOwned(isOwned: state.isOwned) { EconomyManager.shared.equipCosmetic($0) }
            equipNote = unowned.isEmpty
                ? "Equipped. Your next game uses this look."
                : "Equipped \(equipped.count) owned item\(equipped.count == 1 ? "" : "s"). Locked items stay as they were."
        }
        .accessibilityHint("Applies only the items you own")
        let unlockTitle = "Unlock \(unowned.count) item\(unowned.count == 1 ? "" : "s")"
        let unlock = Group {
            if !unowned.isEmpty {
                if flow.purchasesAvailable {
                    StudioActionButton(title: unlockTitle, systemImage: "lock.open.fill",
                                       color: state.spendable >= price ? StudioStyle.gold : .gray,
                                       expand: isLarge, coins: price) {
                        flow.requestItems(unowned, profile: profile, spendable: spendable)
                    }
                    .disabled(flow.isPurchasing)
                    .accessibilityLabel("\(unlockTitle), \(CoinFormat.coins(price))")
                } else {
                    StudioPreviewOnlyLabel()
                }
            }
        }
        return VStack(spacing: 6) {
            if isLarge {
                VStack(spacing: 8) { equipButton; unlock }
            } else {
                HStack(spacing: 10) { equipButton; unlock }
            }
            if model.hasChanges {
                Button("Back to my equipped look") { model.resetDraft() }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.35))
    }
}

/// The real tap-button skin as a press-able control (preview only).
private struct SkinPressStyle: ButtonStyle {
    let item: CosmeticItem
    let colors: [Color]

    func makeBody(configuration: Configuration) -> some View {
        CosmeticTapButtonSkin(item: item, fallbackColors: colors, isPressed: configuration.isPressed)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
