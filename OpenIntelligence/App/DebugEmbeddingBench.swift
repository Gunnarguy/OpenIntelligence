#if DEBUG
    import CoreML
    import Foundation

    #if canImport(CoreAI)
        import CoreAI
    #endif

    /// Development builds only. Times the bundled embedding model on the device the app is running
    /// on, under each compute option Core AI and Core ML offer, with one, two and four calls in
    /// flight, and writes the numbers to `Documents/embedding_bench.json`.
    ///
    /// It exists because the compute options were measured on a Mac only, and a Mac's ranking says
    /// nothing certain about an iPhone's. It loads its own copies of the models and touches neither
    /// provider. It runs when the app is launched with `-embeddingBench`, or when a file named
    /// `run_embedding_bench` is in the app's Documents folder at launch (the file is removed first,
    /// so it runs once).
    nonisolated enum DebugEmbeddingBench {
        static let flagName = "run_embedding_bench"
        static let resultName = "embedding_bench.json"
        private static let sequenceLength = 512
        /// Real tokens in the timed input. Records from a large JSON Lines file are packed toward
        /// 420 tokens, so this is the shape a long import sends.
        private static let realTokens = 420

        static func runIfRequested() {
            guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            else { return }
            let flag = documents.appendingPathComponent(flagName)
            let requested =
                FileManager.default.fileExists(atPath: flag.path)
                || ProcessInfo.processInfo.arguments.contains("-embeddingBench")
            guard requested else { return }
            try? FileManager.default.removeItem(at: flag)
            let resultURL = documents.appendingPathComponent(resultName)
            Task.detached(priority: .userInitiated) {
                // The first screen and the provider's own load come first.
                try? await Task.sleep(for: .seconds(8))
                await run(resultURL: resultURL)
            }
        }

        private static func seconds(_ duration: Duration) -> Double {
            Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        }

        private static func thermal() -> String {
            switch ProcessInfo.processInfo.thermalState {
            case .nominal: return "nominal"
            case .fair: return "fair"
            case .serious: return "serious"
            case .critical: return "critical"
            @unknown default: return "unknown"
            }
        }

        private static func tokenIDs() -> (ids: [Int32], mask: [Int32]) {
            var ids: [Int32] = []
            var mask: [Int32] = []
            for position in 0..<sequenceLength {
                if position == 0 {
                    ids.append(101)
                } else if position == realTokens - 1 {
                    ids.append(102)
                } else if position < realTokens {
                    ids.append(Int32(1000 + (position * 37) % 20000))
                } else {
                    ids.append(0)
                }
                mask.append(position < realTokens ? 1 : 0)
            }
            return (ids, mask)
        }

        private static func save(_ rows: [[String: Any]], finished: Bool, to url: URL) {
            let report: [String: Any] = [
                "finished": finished,
                "writtenAt": ISO8601DateFormatter().string(from: Date()),
                "lowPowerMode": ProcessInfo.processInfo.isLowPowerModeEnabled,
                "activeProcessors": ProcessInfo.processInfo.activeProcessorCount,
                "realTokens": realTokens,
                "sequenceLength": sequenceLength,
                "rows": rows,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: url, options: .atomic)
            }
        }

        static func run(resultURL: URL) async {
            var rows: [[String: Any]] = []
            save(rows, finished: false, to: resultURL)
            #if canImport(CoreAI)
                if #available(iOS 27.0, macOS 27.0, *) {
                    await runCoreAI(into: &rows, resultURL: resultURL)
                }
            #endif
            await runCoreML(into: &rows, resultURL: resultURL)
            save(rows, finished: true, to: resultURL)
            Log.info("[EmbeddingBench] Finished: \(rows.count) row(s) in \(resultName)", category: .embedding)
        }

        #if canImport(CoreAI)
            @available(iOS 27.0, macOS 27.0, *)
            private static func runCoreAI(into rows: inout [[String: Any]], resultURL: URL) async {
                let source =
                    OpenIntelligenceResourceBundle.url(forResource: "EmbeddingModel", withExtension: "bundle")
                    ?? OpenIntelligenceResourceBundle.url(forResource: "main", withExtension: "mlirb")?
                    .deletingLastPathComponent()
                guard let source else {
                    rows.append(["framework": "Core AI", "error": "model not in the bundle"])
                    return
                }
                let link = FileManager.default.temporaryDirectory.appendingPathComponent("EmbeddingModelBench.aimodel")
                try? FileManager.default.removeItem(at: link)
                try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)

                let clock = ContinuousClock()
                let (ids, mask) = tokenIDs()
                let inputIDs = NDArray(scalars: ids, shape: [1, sequenceLength])
                let inputMask = NDArray(scalars: mask, shape: [1, sequenceLength])
                let kinds = "\(ComputeUnitKind.availableKinds)"

                let variants: [(name: String, options: SpecializationOptions, runs: Int)] = [
                    ("default", .default, 96),
                    ("prefer gpu", SpecializationOptions(preferredComputeUnitKind: .gpu), 96),
                    ("prefer neuralEngine", SpecializationOptions(preferredComputeUnitKind: .neuralEngine), 96),
                    ("cpuOnly", .cpuOnly, 12),
                ]
                for variant in variants {
                    var row: [String: Any] = [
                        "framework": "Core AI", "option": variant.name, "availableKinds": kinds,
                        "thermalBefore": thermal(),
                    ]
                    do {
                        var loaded: AIModel?
                        let loadTime = try await clock.measure {
                            loaded = try await AIModel(contentsOf: link, options: variant.options)
                        }
                        row["loadSeconds"] = seconds(loadTime)
                        guard let model = loaded,
                            let function = (try? model.loadFunction(named: "forward"))
                                ?? (try? model.loadFunction(named: "main"))
                                ?? (try? model.loadFunction(named: "encode"))
                        else {
                            row["error"] = "no function"
                            rows.append(row)
                            continue
                        }
                        for _ in 0..<3 {
                            _ = try await function.run(inputs: ["input_ids": inputIDs, "attention_mask": inputMask])
                        }
                        let runs = variant.runs
                        let sequential = try await clock.measure {
                            for _ in 0..<runs {
                                _ = try await function.run(inputs: [
                                    "input_ids": inputIDs, "attention_mask": inputMask,
                                ])
                            }
                        }
                        row["sequentialMsEach"] = seconds(sequential) / Double(runs) * 1000
                        row["sequentialPerSecond"] = Double(runs) / seconds(sequential)
                        for inFlight in [2, 4] {
                            let each = runs / inFlight
                            let elapsed = try await clock.measure {
                                try await withThrowingTaskGroup(of: Void.self) { group in
                                    for _ in 0..<inFlight {
                                        group.addTask {
                                            for _ in 0..<each {
                                                _ = try await function.run(inputs: [
                                                    "input_ids": inputIDs, "attention_mask": inputMask,
                                                ])
                                            }
                                        }
                                    }
                                    try await group.waitForAll()
                                }
                            }
                            row["inFlight\(inFlight)PerSecond"] = Double(each * inFlight) / seconds(elapsed)
                        }
                    } catch {
                        row["error"] = String(String(describing: error).prefix(300))
                    }
                    row["thermalAfter"] = thermal()
                    rows.append(row)
                    save(rows, finished: false, to: resultURL)
                }
                try? FileManager.default.removeItem(at: link)
            }
        #endif

        private static func runCoreML(into rows: inout [[String: Any]], resultURL: URL) async {
            guard
                let url = OpenIntelligenceResourceBundle.url(forResource: "EmbeddingModel", withExtension: "mlmodelc")
            else {
                rows.append(["framework": "Core ML", "error": "model not in the bundle"])
                return
            }
            let clock = ContinuousClock()
            let (ids, mask) = tokenIDs()
            let variants: [(name: String, units: MLComputeUnits, runs: Int)] = [
                ("cpuOnly", .cpuOnly, 48),
                ("cpuAndGPU", .cpuAndGPU, 96),
                ("cpuAndNeuralEngine", .cpuAndNeuralEngine, 96),
                ("all", .all, 96),
            ]
            for variant in variants {
                var row: [String: Any] = [
                    "framework": "Core ML", "option": variant.name, "thermalBefore": thermal(),
                ]
                do {
                    let configuration = MLModelConfiguration()
                    configuration.computeUnits = variant.units
                    var loaded: MLModel?
                    let loadTime = try clock.measure {
                        loaded = try MLModel(contentsOf: url, configuration: configuration)
                    }
                    row["loadSeconds"] = seconds(loadTime)
                    guard let model = loaded else { continue }
                    let shape = [1, NSNumber(value: sequenceLength)]
                    let idArray = try MLMultiArray(shape: shape, dataType: .int32)
                    let maskArray = try MLMultiArray(shape: shape, dataType: .int32)
                    let typeArray = try MLMultiArray(shape: shape, dataType: .int32)
                    for position in 0..<sequenceLength {
                        idArray[position] = NSNumber(value: ids[position])
                        maskArray[position] = NSNumber(value: mask[position])
                        typeArray[position] = 0
                    }
                    let inputs = try MLDictionaryFeatureProvider(dictionary: [
                        "input_ids": MLFeatureValue(multiArray: idArray),
                        "attention_mask": MLFeatureValue(multiArray: maskArray),
                        "token_type_ids": MLFeatureValue(multiArray: typeArray),
                    ])
                    for _ in 0..<3 { _ = try await model.prediction(from: inputs) }
                    let runs = variant.runs
                    let sequential = try await clock.measure {
                        for _ in 0..<runs { _ = try await model.prediction(from: inputs) }
                    }
                    row["sequentialMsEach"] = seconds(sequential) / Double(runs) * 1000
                    row["sequentialPerSecond"] = Double(runs) / seconds(sequential)
                    for inFlight in [2, 4] {
                        let each = runs / inFlight
                        let elapsed = try await clock.measure {
                            try await withThrowingTaskGroup(of: Void.self) { group in
                                for _ in 0..<inFlight {
                                    group.addTask {
                                        for _ in 0..<each { _ = try await model.prediction(from: inputs) }
                                    }
                                }
                                try await group.waitForAll()
                            }
                        }
                        row["inFlight\(inFlight)PerSecond"] = Double(each * inFlight) / seconds(elapsed)
                    }
                } catch {
                    row["error"] = String(String(describing: error).prefix(300))
                }
                row["thermalAfter"] = thermal()
                rows.append(row)
                save(rows, finished: false, to: resultURL)
            }
        }
    }
#endif
