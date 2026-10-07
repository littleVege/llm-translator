import AppKit
import Combine
import Foundation

struct TranslationPlan {
    /// Language name used inside the prompt ("English", "the source language", …).
    let fromPromptName: String
    /// Label shown in the UI ("English", "Auto", …).
    let fromDisplay: String
    let target: Language
}

enum Translator {
    /// Resolves the effective language pair. With "Auto" as source the
    /// language is detected locally; if the text is already in the target
    /// language it is translated to the alternate target instead.
    static func plan(for text: String, from: Language?, to: Language?) -> TranslationPlan {
        let settings = AppSettings.shared
        let from = from ?? Language.byCode(settings.sourceCode) ?? .auto
        let to = to ?? Language.byCode(settings.targetCode) ?? Language.byCode("en")!
        let alt = Language.byCode(settings.altTargetCode) ?? Language.byCode("en")!

        guard from.code == Language.auto.code else {
            return TranslationPlan(fromPromptName: from.englishName, fromDisplay: from.displayName, target: to)
        }
        guard let detected = LanguageDetector.detect(text) else {
            return TranslationPlan(fromPromptName: "the source language", fromDisplay: "Auto", target: to)
        }
        if detected.code == to.code && alt.code != to.code {
            return TranslationPlan(fromPromptName: detected.englishName, fromDisplay: detected.displayName, target: alt)
        }
        return TranslationPlan(fromPromptName: detected.englishName, fromDisplay: detected.displayName, target: to)
    }

    static func systemPrompt(for plan: TranslationPlan) -> String {
        AppSettings.shared.promptTemplate
            .replacingOccurrences(of: "{from}", with: plan.fromPromptName)
            .replacingOccurrences(of: "{to}", with: plan.target.englishName)
    }
}

/// Drives one streaming translation; shared by the popup and the input bar.
@MainActor
final class TranslationSession: ObservableObject {
    enum Phase: Equatable {
        case idle
        case noSelection
        case needsPermission
        case translating
        case done
        case failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var output = ""
    @Published var pairLabel = ""

    private var task: Task<Void, Never>?
    private var publishTask: Task<Void, Never>?
    private var pendingOutput = ""
    private var generation = 0

    func start(text rawText: String?, from: Language? = nil, to: Language? = nil) {
        task?.cancel()
        publishTask?.cancel()
        publishTask = nil
        pendingOutput = ""
        generation &+= 1
        let requestGeneration = generation
        output = ""

        let trimmed = rawText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            pairLabel = ""
            phase = .noSelection
            return
        }

        // Keep requests bounded even for huge selections.
        let text = String(trimmed.prefix(10_000))
        let plan = Translator.plan(for: text, from: from, to: to)
        pairLabel = "\(plan.fromDisplay) → \(plan.target.displayName)"
        phase = .translating

        let system = Translator.systemPrompt(for: plan)
        task = Task { [weak self] in
            do {
                for try await delta in LLMClient.stream(system: system, user: text) {
                    guard let self,
                          self.generation == requestGeneration,
                          !Task.isCancelled else { return }
                    self.receive(delta, for: requestGeneration)
                }
                guard let self,
                      self.generation == requestGeneration,
                      !Task.isCancelled else { return }
                self.flushPendingOutput(for: requestGeneration)
                self.phase = self.output.isEmpty
                    ? .failed("Empty response from the model. Check that the endpoint supports streaming.")
                    : .done
            } catch {
                guard let self,
                      self.generation == requestGeneration,
                      !Task.isCancelled else { return }
                if error is CancellationError { return }
                if let urlError = error as? URLError, urlError.code == .cancelled { return }
                self.flushPendingOutput(for: requestGeneration)
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    private func receive(_ delta: String, for requestGeneration: Int) {
        // The first token is visible immediately. Later token bursts are
        // coalesced into a bounded 40 ms window to avoid excessive SwiftUI
        // layout work on long responses.
        if output.isEmpty && pendingOutput.isEmpty {
            output.append(delta)
            return
        }

        pendingOutput.append(delta)
        guard publishTask == nil else { return }
        publishTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 40_000_000)
            } catch {
                return
            }
            guard let self, self.generation == requestGeneration else { return }
            self.publishTask = nil
            self.flushPendingOutput(for: requestGeneration)
        }
    }

    private func flushPendingOutput(for requestGeneration: Int) {
        guard generation == requestGeneration else { return }
        publishTask?.cancel()
        publishTask = nil
        guard !pendingOutput.isEmpty else { return }
        output.append(pendingOutput)
        pendingOutput.removeAll(keepingCapacity: true)
    }

    func showNeedsPermission() {
        cancel()
        output = ""
        pairLabel = ""
        phase = .needsPermission
    }

    func cancel() {
        task?.cancel()
        publishTask?.cancel()
        publishTask = nil
        pendingOutput = ""
        generation &+= 1
    }

    func copyOutput() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(output, forType: .string)
    }
}
