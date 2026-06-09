//
//  ContentView.swift
//  BoulderBikeRouter Watch App Watch App
//
//  Created by MBP on 6/8/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = WatchNavigationViewModel()

    var body: some View {
        NavigationStack {
            content
                .containerBackground(.black, for: .navigation)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.snapshot.status {
        case .inactive, .ended:
            inactiveView
        case .offRoute:
            offRouteView
        case .arrived:
            arrivedView
        case .navigating:
            navigationView
        }
    }

    private var navigationView: some View {
        VStack(spacing: 8) {
            Image(systemName: viewModel.snapshot.maneuverIconName)
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.mint)
                .frame(height: 48)

            Text(WatchNavigationDistanceFormatter.shortDistance(viewModel.snapshot.distanceToManeuverMeters))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(viewModel.snapshot.instruction)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 0)

            footer
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var offRouteView: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.yellow)

            Text("Off route")
                .font(.title3.weight(.bold))

            Text("Check iPhone")
                .font(.headline)
                .foregroundStyle(.secondary)

            footer
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 8)
    }

    private var arrivedView: some View {
        VStack(spacing: 10) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.mint)

            Text("Arrived")
                .font(.title3.weight(.bold))

            Text("End on iPhone")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 8)
    }

    private var inactiveView: some View {
        VStack(spacing: 12) {
            Image(systemName: "iphone")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.mint)

            Text("Start navigation on iPhone")
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(3)

            if !viewModel.isConnectedToPhone {
                Text("Waiting for phone")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
    }

    @ViewBuilder
    private var footer: some View {
        let remaining = viewModel.snapshot.remainingDistanceText
        let eta = viewModel.snapshot.etaText

        HStack(spacing: 6) {
            if let remaining {
                Text(remaining)
            }
            if remaining != nil, eta != nil {
                Text("•")
            }
            if let eta {
                Text(eta)
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(viewModel.isSnapshotStale ? .orange : .secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

#Preview {
    ContentView()
}
