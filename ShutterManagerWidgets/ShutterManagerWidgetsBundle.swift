//
//  ShutterManagerWidgetsBundle.swift
//  ShutterManagerWidgets
//
//  The widget extension's entry point. It holds one thing: the running timers' Live Activity.
//

import SwiftUI
import WidgetKit

@main
struct ShutterManagerWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TimerLiveActivity()
    }
}
