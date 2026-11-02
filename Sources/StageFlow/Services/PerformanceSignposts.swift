import Foundation
import os
import OSLog

/// Инструмент маркировки событий и интервалов производительности для Instruments (E12.2).
public final class PerformanceSignposts: Sendable {
    public static let shared = PerformanceSignposts()
    
    public let signposter: OSSignposter
    
    public init() {
        self.signposter = OSSignposter(subsystem: "com.stageflow.app", category: "StageFlowPerformance")
    }
    
    // MARK: - Интервалы
    
    public func beginInterval(_ name: StaticString) -> OSSignpostIntervalState {
        let signpostID = signposter.makeSignpostID()
        return signposter.beginInterval(name, id: signpostID)
    }
    
    public func endInterval(_ name: StaticString, state: OSSignpostIntervalState) {
        signposter.endInterval(name, state)
    }
    
    // MARK: - Точечные события
    
    public func emitEvent(_ name: StaticString) {
        let signpostID = signposter.makeSignpostID()
        signposter.emitEvent(name, id: signpostID)
    }
}
