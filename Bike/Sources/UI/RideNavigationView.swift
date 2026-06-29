import SwiftUI
import MapKit
import UIKit
import CyclingDomain

/// 逐向导航页：转向卡 + 跟随地图 + 结束。语音在 RideNavigator 里。
struct RideNavigationView: View {
    @State private var navigator: RideNavigator
    @State private var showArrival = false
    @State private var showAudioHint = true
    @Environment(\.dismiss) private var dismiss

    init(plan: RoutePlan, destination: GeoCoordinate) {
        _navigator = State(initialValue: RideNavigator(plan: plan, destination: destination))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Map {
                let cs = navigator.coords.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                }
                if cs.count >= 2 { MapPolyline(coordinates: cs).stroke(.tint, lineWidth: 5) }
                UserAnnotation()
            }
            .mapControls { MapUserLocationButton() }
            .ignoresSafeArea()

            VStack(spacing: 8) {
                turnCard
                if showAudioHint {
                    Label("请关闭静音按钮，以听到语音导航", systemImage: "bell.slash.fill")
                        .font(.footnote)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.horizontal)
                        .transition(.opacity)
                }
            }

            VStack {
                Spacer()
                Button(role: .destructive) {
                    navigator.stop()
                    dismiss()
                } label: {
                    Label("结束导航", systemImage: "xmark.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.red).padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            navigator.start()
        }
        .task {
            try? await Task.sleep(for: .seconds(6))
            withAnimation { showAudioHint = false }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            navigator.stop()
        }
        .onChange(of: navigator.arrived) { _, arrived in showArrival = arrived }
        .alert("已到达目的地", isPresented: $showArrival) {
            Button("完成") { dismiss() }
        }
    }

    private var turnCard: some View {
        HStack(spacing: 12) {
            Image(systemName: icon(navigator.progress?.nextTurn?.direction))
                .font(.system(size: 30, weight: .bold))
            VStack(alignment: .leading, spacing: 2) {
                if let p = navigator.progress, let t = p.nextTurn, t.direction != .arrive {
                    Text("\(Int(p.distanceToNextTurnMeters)) 米").font(.title3.bold())
                    Text(phrase(t.direction)).font(.subheadline)
                } else {
                    Text("沿路线前进").font(.headline)
                }
            }
            Spacer()
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding()
    }

    private func icon(_ d: TurnDirection?) -> String {
        switch d {
        case .left, .slightLeft, .sharpLeft: return "arrow.turn.up.left"
        case .right, .slightRight, .sharpRight: return "arrow.turn.up.right"
        case .uTurn: return "arrow.uturn.down"
        case .arrive: return "flag.checkered"
        default: return "arrow.up"
        }
    }

    private func phrase(_ d: TurnDirection) -> String {
        switch d {
        case .left, .slightLeft: return "向左"
        case .sharpLeft: return "向左急转"
        case .right, .slightRight: return "向右"
        case .sharpRight: return "向右急转"
        case .uTurn: return "掉头"
        case .straight: return "直行"
        case .arrive: return "到达"
        }
    }
}
