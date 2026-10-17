//
//  StoreScenePDF.swift
//  OpenIntelligence
//
//  The lease PDF the App Store listing's page scene opens (DEBUG only, 5.7).
//

#if DEBUG
    import Foundation

    /// The page scene's sheet: a cited passage on its PDF page.
    struct StoreScenePage: Identifiable {
        let document: Document
        let page: Int
        let passage: String
        let chunk: RetrievedChunk
        var id: String { "\(document.id.uuidString)-\(page)" }
    }

    #if os(iOS)
        import UIKit

        /// An eight-page residential lease, drawn for `--screenshot-store page`. The staged answer cites page 7 (Termination)
        /// and page 8 (Early Termination), so those pages carry the cited sentences word for word and the page view finds them
        /// in the text layer; the other pages hold ordinary lease clauses so the document reads as one. Nothing here ships.
        enum StoreScenePDF {
            static func lease(termination: String, earlyTermination: String) -> URL? {
                let pages: [(title: String, body: [String])] = [
                    ("Residential Lease Agreement", [
                        "This Residential Lease Agreement is made between Harbor View Properties (Landlord) and the Tenant named below for the apartment at 418 Alder Street, Unit 3B.",
                        "The Landlord rents the apartment to the Tenant, and the Tenant rents it from the Landlord, on the terms in this lease.",
                    ]),
                    ("1. Term", [
                        "The initial term of this lease is twelve (12) months, beginning on the first day of the month after it is signed.",
                        "After the initial term the lease continues from month to month until either party ends it as this lease provides.",
                    ]),
                    ("2. Rent", [
                        "Rent is $1,850 a month, due on the first day of each month at the management office or through the resident portal.",
                        "Rent received after the fifth day of the month carries a late fee of $75.",
                    ]),
                    ("3. Security Deposit", [
                        "The Tenant pays a security deposit of $1,850 when signing this lease.",
                        "The Landlord returns the deposit, less any lawful deductions, within twenty-one (21) days after the Tenant moves out.",
                    ]),
                    ("4. Utilities", [
                        "The Tenant pays for electricity, internet and gas. The Landlord pays for water, sewer and trash.",
                    ]),
                    ("5. Maintenance and Repairs", [
                        "The Tenant keeps the apartment clean and reports any needed repair to the management office in writing.",
                        "The Landlord makes repairs within a reasonable time after notice.",
                    ]),
                    ("6. Termination", [
                        termination,
                        "Notice given in the middle of a month takes effect at the end of the following full month.",
                    ]),
                    ("7. Early Termination", [
                        earlyTermination,
                        "The fee is due with the notice, and rent is owed through the move-out date.",
                    ]),
                ]

                let size = CGSize(width: 612, height: 792)
                let margin: CGFloat = 72
                let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size))
                let data = renderer.pdfData { context in
                    for (index, page) in pages.enumerated() {
                        context.beginPage()
                        var y = margin
                        let width = size.width - margin * 2
                        func draw(_ text: String, _ font: UIFont, after spacing: CGFloat) {
                            let style = NSMutableParagraphStyle()
                            style.lineSpacing = 4
                            let attributed = NSAttributedString(
                                string: text,
                                attributes: [.font: font, .foregroundColor: UIColor.black, .paragraphStyle: style])
                            let height = attributed.boundingRect(
                                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil
                            ).height
                            attributed.draw(in: CGRect(x: margin, y: y, width: width, height: ceil(height)))
                            y += ceil(height) + spacing
                        }
                        draw(page.title, .systemFont(ofSize: index == 0 ? 20 : 15, weight: .semibold), after: 14)
                        for paragraph in page.body { draw(paragraph, .systemFont(ofSize: 12), after: 10) }
                        let footer = NSAttributedString(
                            string: "Page \(index + 1) of \(pages.count)",
                            attributes: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.gray])
                        footer.draw(at: CGPoint(x: margin, y: size.height - margin / 2))
                    }
                }
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("Apartment Lease.pdf")
                do {
                    try data.write(to: url, options: .atomic)
                    return url
                } catch {
                    return nil
                }
            }
        }
    #endif
#endif
