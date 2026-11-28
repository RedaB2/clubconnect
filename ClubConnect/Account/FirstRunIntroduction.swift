import SwiftUI

struct FirstRunIntroduction: View {
    @Environment(\.brandTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 41
    @AccessibilityFocusState private var focusedHeading: Int?
    @State private var page = 0

    let onFinish: () -> Void

    // These examples are available offline and are independent of the signed-in club.
    private static let sample = CommunityState.sample()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image("ClubMark").resizable().scaledToFit().frame(width: 28, height: 28)
                    .accessibilityLabel("Club Connect")
                    .accessibilityHidden(!typeSize.isAccessibilitySize)
                if !typeSize.isAccessibilitySize {
                    Text("Club Connect").font(.headline).foregroundStyle(theme.ink)
                }
                Spacer(minLength: 8)
                Button(action: onFinish) {
                    Text("Skip").font(.subheadline.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityIdentifier("intro-skip")
            }
            .frame(maxWidth: 1000)
            .padding(.horizontal, 24)

            GeometryReader { geometry in
                TabView(selection: $page) {
                    introduction(0, title: "See what’s on at your club.",
                        detail: "Browse upcoming meetups, find the time and place, and add one to your calendar.",
                        size: geometry.size) {
                        if let event = Self.sample.events.first {
                            IntroductionEvent(club: Self.sample.club, event: event)
                        }
                    }
                    .tag(0)
                    introduction(1, title: "Keep your ticket handy.",
                        detail: "RSVP to get your ticket and show it at the door. On iPhone, you can keep the pass in Apple Wallet.",
                        size: geometry.size) {
                        if let event = Self.sample.events.first, let attendee = Self.sample.members.first(where: { $0.id == Self.sample.myID }) {
                            IntroductionTicket(club: Self.sample.club, event: event, attendee: attendee.name)
                        }
                    }
                    .tag(1)
                    introduction(2, title: "Meet your club’s alumni.",
                        detail: "Find students and alumni by major or interest, open a profile, and send a private message.",
                        size: geometry.size) {
                        if let member = Self.sample.members.first(where: { $0.id == "demo-yasmin" }) {
                            IntroductionConversation(member: member)
                        }
                    }
                    .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }

            VStack(spacing: 4) {
                IntroductionPageIndicator(page: page, select: move)
                    .frame(width: 100, height: 44)
                HStack(spacing: 12) {
                    if page > 0 {
                        Button { move(to: page - 1) } label: {
                            Image(systemName: "chevron.backward").font(.headline)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.bordered).buttonBorderShape(.circle)
                        .accessibilityLabel("Back")
                        .accessibilityIdentifier("intro-back")
                    }
                    if page < 2 {
                        AccountAction("Next", systemImage: "arrow.forward") { move(to: page + 1) }
                            .accessibilityIdentifier("intro-next")
                    } else {
                        AccountAction("Get started", action: onFinish)
                            .accessibilityIdentifier("intro-finish")
                    }
                }
            }
            .frame(maxWidth: 440)
            .padding(.horizontal, 24)
            .padding(.bottom, 10)
        }
        .padding(.top, 4)
        .background(theme.canvas.ignoresSafeArea())
        .tint(theme.accent)
        .onChange(of: page) { _, newPage in focusedHeading = newPage }
    }

    private func move(to value: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) { page = value }
    }

    private func introduction<Preview: View>(_ index: Int, title: LocalizedStringKey, detail: LocalizedStringKey,
                                              size: CGSize, @ViewBuilder preview: () -> Preview) -> some View {
        let columns = size.width >= 740 && !typeSize.isAccessibilitySize
        let heading = VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: titleSize, weight: .semibold, design: .serif))
                .tracking(-0.8)
                .foregroundStyle(theme.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("intro-page-" + String(index))
                .accessibilityFocused($focusedHeading, equals: index)
            Text(detail).font(.body).foregroundStyle(theme.ink.opacity(0.8))
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)

        return ScrollView {
            Group {
                if columns {
                    HStack(spacing: 44) {
                        heading.frame(maxWidth: 360)
                        preview().frame(maxWidth: 440)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 26) {
                        if typeSize.isAccessibilitySize { heading }
                        preview()
                        if !typeSize.isAccessibilitySize { heading }
                    }
                    .frame(maxWidth: 440)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, columns ? 44 : 24)
            .padding(.vertical, 16)
            .frame(minHeight: size.height, alignment: .center)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityHidden(page != index)
    }
}

/// UIPageControl provides the native adjustable VoiceOver action as well as direct dot navigation.
private struct IntroductionPageIndicator: UIViewRepresentable {
    @Environment(\.brandTheme) private var theme
    let page: Int
    let select: (Int) -> Void

    final class Coordinator: NSObject {
        var select: (Int) -> Void

        init(select: @escaping (Int) -> Void) { self.select = select }

        @objc func changed(_ control: UIPageControl) { select(control.currentPage) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(select: select) }

    func makeUIView(context: Context) -> UIPageControl {
        let control = UIPageControl()
        control.numberOfPages = 3
        control.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        return control
    }

    func updateUIView(_ control: UIPageControl, context: Context) {
        context.coordinator.select = select
        control.currentPage = page
        control.currentPageIndicatorTintColor = UIColor(theme.accent)
        control.pageIndicatorTintColor = UIColor(theme.ink.opacity(0.32))
    }
}

private struct IntroductionEvent: View {
    @Environment(\.brandTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    let club: Club
    let event: ClubEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.aspectRatio(1.85, contentMode: .fit)
                .overlay { Image("Gathering").resizable().scaledToFill() }
                .clipped().accessibilityHidden(true)
            HStack(alignment: .center, spacing: 13) {
                if !typeSize.isAccessibilitySize { EventDateTile(date: event.startsAt) }
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(club.name) · Sample event")
                        .font(.caption.weight(.semibold)).foregroundStyle(theme.accent)
                    Text(event.title)
                        .font(.system(.title2, design: .serif, weight: .semibold)).foregroundStyle(theme.ink)
                    Text(event.location)
                        .font(.subheadline).foregroundStyle(theme.ink.opacity(0.78))
                    Text(event.startsAt.formatted(date: typeSize.isAccessibilitySize ? .abbreviated : .omitted, time: .shortened))
                        .font(.footnote.weight(.medium)).foregroundStyle(theme.ink.opacity(0.78))
                }
            }
            .padding(16)
        }
        .background(theme.surface)
        .clipShape(.rect(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(theme.ink.opacity(0.12), lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }
}

private struct IntroductionTicket: View {
    @Environment(\.brandTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    let club: Club
    let event: ClubEvent
    let attendee: String

    // This encodes a plain sample description and cannot be used for admission.
    private static let code = TicketBarcode.image(payload: "Club Connect sample ticket")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text(club.name).font(.headline)
                    Spacer()
                    Label("Sample ticket", systemImage: "ticket").font(.subheadline)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(club.name).font(.headline)
                    Label("Sample ticket", systemImage: "ticket").font(.subheadline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.vertical, 14)
            .foregroundStyle(BrandTheme.label(on: theme.accent))
            .background(theme.accent)

            VStack(alignment: .leading, spacing: 6) {
                Text(event.title).font(.system(.title, design: .serif, weight: .semibold))
                    .foregroundStyle(theme.ink)
                Text(event.startsAt.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().hour().minute()))
                    .font(.subheadline.weight(.medium)).foregroundStyle(theme.ink)
                Text(event.location).font(.subheadline).foregroundStyle(theme.ink.opacity(0.76))
            }
            .padding(20)

            Canvas { context, size in
                var line = Path()
                line.move(to: CGPoint(x: 0, y: 0.5))
                line.addLine(to: CGPoint(x: size.width, y: 0.5))
                context.stroke(line, with: .color(theme.ink.opacity(0.36)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .frame(height: 1)
            .overlay(alignment: .leading) { notch.offset(x: -8) }
            .overlay(alignment: .trailing) { notch.offset(x: 8) }
            .accessibilityHidden(true)

            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(spacing: 18))
            layout {
                if let code = Self.code {
                    Image(decorative: code, scale: 1)
                        .interpolation(.none).resizable().scaledToFit().padding(5)
                        .frame(width: 74, height: 74)
                        .background(.white, in: .rect(cornerRadius: 6))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Label("Going", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(theme.accent)
                    Text(attendee).font(.headline).foregroundStyle(theme.ink)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 13)
        }
        .background(theme.surface)
        .clipShape(.rect(cornerRadius: 19))
        .overlay {
            RoundedRectangle(cornerRadius: 19).strokeBorder(theme.ink.opacity(0.14), lineWidth: 1)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    private var notch: some View {
        Circle().fill(theme.canvas).frame(width: 16, height: 16)
    }
}

private struct IntroductionConversation: View {
    @Environment(\.brandTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    let member: Member

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(spacing: 14))
            layout {
                MemberPortrait(name: member.name, imageData: member.photoData, diameter: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sample conversation").font(.caption.weight(.semibold)).foregroundStyle(theme.accent)
                    Text(member.name)
                        .font(.system(.title3, design: .serif, weight: .semibold))
                    Text("\(member.major) · Alumni")
                        .font(.subheadline.weight(.medium)).foregroundStyle(theme.ink.opacity(0.82))
                }
            }
            .foregroundStyle(theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(theme.wash)

            VStack(spacing: 11) {
                message("How did you find your first engineering role?", fromStudent: true)
                message("I met a mentor at a club event. Happy to share what helped!", fromStudent: false)
            }
            .padding(17)
        }
        .background(theme.surface)
        .clipShape(.rect(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(theme.ink.opacity(0.12), lineWidth: 1) }
        .accessibilityElement(children: .contain)
    }

    private func message(_ text: LocalizedStringKey, fromStudent: Bool) -> some View {
        let margin: CGFloat = typeSize.isAccessibilitySize ? 8 : 32
        let shape = UnevenRoundedRectangle(topLeadingRadius: 17, bottomLeadingRadius: fromStudent ? 17 : 4,
            bottomTrailingRadius: fromStudent ? 4 : 17, topTrailingRadius: 17)
        return HStack(spacing: 0) {
            if fromStudent { Spacer(minLength: margin) }
            Text(text)
                .font(.subheadline)
                .foregroundStyle(fromStudent ? BrandTheme.label(on: theme.accent) : theme.ink)
                .padding(.horizontal, 13).padding(.vertical, 9)
                .background(fromStudent ? theme.accent : theme.canvas, in: shape)
                .accessibilityLabel(fromStudent ? Text("Student") : Text(member.name))
                .accessibilityValue(Text(text))
            if !fromStudent { Spacer(minLength: margin) }
        }
    }
}
