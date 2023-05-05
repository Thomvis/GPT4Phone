import CryptoKit
import OpenAIClient
import XCTest
import Yams

final class PhoneGPTTests: XCTestCase {
    @MainActor
    func testExample() async throws {
        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] else {
            fatalError("OPENAI_API_KEY must be set")
        }

        guard let task = ProcessInfo.processInfo.environment["TASK"] else {
            fatalError("TASK must be set")
        }
        let openAIClient = OpenAIClient.live(apiKey: apiKey)

        let cache = UserDefaults(suiteName: "me.thomasvisser.gpt4phonecache")

        var request = ChatCompletionRequest(
            model: .gpt4,
            messages: [
                .init(role: .system, content: """
                You control my iPhone through me to achieve a task I give you. I give you a textual description of the UI and you respond with the next action. This is repeated until the task is done.

                Task: \(task)

                You can use all apps and content on my phone to complete the task. Personal information must be observed using my phone. Do not make this up.
                """)
            ],
            maxTokens: 256,
            temperature: 0
        )

        var app = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        app.activate()

        loop: while true {
            let element = try build(app.snapshot())

            guard let description = element?.description else {
                print("Could not make description of app")
                try await Task.sleep(for: .seconds(1))
                continue
            }

            if app.otherElements["AppSwitcherContentView"].exists {
                // we're in the appswitcher because an app was launched from the home screen
                if let match = description.matches(of: #/card:([a-zA-Z0-9\.]+):sceneID/#).last  {
                    app = XCUIApplication(bundleIdentifier: String(match.output.1))
                    app.activate()
                    continue
                } else {
                    print("Did not find app in app switcher...")

                    app = XCUIApplication(bundleIdentifier: "com.apple.springboard")
                    app.activate()

                    try await Task.sleep(for: .seconds(1))

                    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.0))
                        .press(
                            forDuration: 0.2,
                            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                        )

                    try await Task.sleep(for: .seconds(1))
                    continue
                }
            }

            print("\n\nDESCRIPTION:\n\(description)")

            let nextPrompt = """
                UI description:
                \(description)

                Respond with a single action in YAML with its required arguments.

                Possible actions (with required arguments):
                - tap (id: the id of the view to tap)
                - tap_hold (id: the id of the view to tap and hold for 1 second)
                - type (id: the id of the view to enter text in, text: the text to enter)
                - home (to go back to the home screen)
                - done (when you are sure the task was completed)

                Other required arguments:
                - observation: a description of the screen, noting anything that's relevant to the task at hand
                - thought: think about what needs to be done to achieve the task step by step
                - action_description: a short description of the action you take

                Example response:

                ```
                observation: "I'm on the home screen where I can add a document."
                thought: "I first need to look up X, then do Y."
                action_description: "I tap on the button with label \"New\""
                action: tap
                id: 1
                ```
            """

            request.messages.append(.init(role: .user, content: nextPrompt))

            let cacheKey = try? SHA256.hash(data: JSONEncoder().encode(request))

            let response: String
            if let cacheKey, let cachedResponse = cache?.value(forKey: cacheKey.description) as? String {
                response = cachedResponse

                try await Task.sleep(for: .seconds(1))
            } else {
                do {
                    response = try await openAIClient.stream(request: request).reduce("", +)
                } catch {
                    print("Failed streaming response: \(error)")
                    try await Task.sleep(for: .seconds(1))
                    continue
                }
            }

            print("\n\nRESPONSE:\n\(response)")

            try await Task.sleep(for: .seconds(0.5))

            let rawPayload: Any?
            do {
                rawPayload = try Yams.load(yaml: response)
            } catch {
                print("Could not parse response: \(error)")
                break
            }

            guard let payload = rawPayload as? [String: Any] else {
                print("Parsed YAML is not a dictionary: \(String(describing: rawPayload))")
                break
            }

            switch payload["action"] as? String {
            case "tap":
                guard let id = payload["id"] as? Int else {
                    print("Failed to interpret tap action: \(payload)")
                    break loop
                }

                element?.element(for: id, in: app).tap()
            case "tap_hold":
                guard let id = payload["id"] as? Int else {
                    print("Failed to interpret tap action: \(payload)")
                    break loop
                }

                let e = element?.element(for: id, in: app)
                e?.press(forDuration: 1.0)
            case "type":
                guard let id = payload["id"] as? Int, let text = payload["text"] as? String else {
                    print("Failed to interpret type action: \(payload)")
                    break loop
                }

                var target = element?.element(for: id, in: app)
                target?.tap()
                for c in text {
                    target?.typeText(String(c))
                    target = element?.element(for: id, in: app) // target query might change because value of field changes
                }
            case "home":
                XCUIDevice.shared.press(.home)
            case "done":
                print("GPT is done")
                break loop
            default:
                print("Failed to interpret action: \(payload)")
                break
            }

            if let cacheKey {
                print("Caching response for key \(cacheKey.description)")
                cache?.set(response, forKey: cacheKey.description)
            }

            // remove the view description (to save costs) and add action summary
            request.messages.removeLast()
            request.messages.append(.init(role: .user, content: "(UI description omitted)"))
            request.messages.append(.init(role: .assistant, content: response))

            try await Task.sleep(for: .seconds(1))

            if app.state != .runningForeground {
                app = XCUIApplication(bundleIdentifier: "com.apple.springboard")
                app.activate()
            }
        }

    }

    let includeList: [XCUIElement.ElementType] = [.button, .cell, .icon, .link, .navigationBar, .scrollView, .searchField, .tabBar, .textField, .textView, .staticText]
    let excludeList: [XCUIElement.ElementType] = [.statusBar]
    func build(_ snapshot: XCUIElementSnapshot, n: inout Int) -> Element? {
        let childElements = snapshot.children.compactMap { build($0, n: &n) }

        guard !excludeList.contains(snapshot.elementType) else { return nil }

        if includeList.contains(snapshot.elementType) || childElements.count > 1 || snapshot.identifier.nonEmptyString != nil {
            n += 1
            return Element(
                number: n-1,
                attributes: snapshot,
                children: childElements
            )
        } else if let single = childElements.single {
            return single
        } else {
            return nil
        }
    }

    func build(_ snapshot: XCUIElementSnapshot) -> Element? {
        var n = 0
        return build(snapshot, n: &n)
    }
}

struct Element {
    let number: Int
    let attributes: XCUIElementAttributes
    let children: [Element]
}

let uuidRegex = #/[0-9a-fA-F]{8}\b-[0-9a-fA-F]{4}\b-[0-9a-fA-F]{4}\b-[0-9a-fA-F]{4}\b-[0-9a-fA-F]{12}/#
extension Element {
    var description: String {
        var result = "\(attributes.elementType.description), id: \(number)"
        if let id = attributes.identifier.nonEmptyString, id.firstMatch(of: uuidRegex) == nil || id.hasPrefix("card") {
            result += ", name: \"\(id)\""
        }
        if let label = attributes.label.nonEmptyString, label.firstMatch(of: uuidRegex) == nil {
            result += ", label: \"\(label)\""
        }
        if let value = attributes.value {
            result += ", value: \"\(value)\""
        }
        if !attributes.isEnabled {
            result += ", disabled"
        }
        if attributes.isSelected {
            result += ", selected"
        }

        for child in children {
            result += "\n" + child.description.indented
        }
        return result
    }

    func element(for n: Int, in app: XCUIApplication) -> XCUIElement {
        for child in children {
            if child.number >= n {
                return child.element(for: n, in: app.descendants(matching: child.attributes.elementType))
            }
        }
        fatalError()
    }

    func element(for n: Int, in query: XCUIElementQuery) -> XCUIElement {
        var query = query

        var predicates: [NSPredicate] = []
        if let id = attributes.identifier.nonEmptyString {
            predicates.append(NSPredicate(format: "identifier == '\(id)'"))
        }

        if let label = attributes.label.nonEmptyString {
            predicates.append(NSPredicate(format: "label == '\(label)'"))
        }

        if let value = (attributes.value as? String)?.nonEmptyString {
            predicates.append(NSPredicate(format: "value == '\(value)'"))
        }

        if !predicates.isEmpty {
            query = query.matching(NSCompoundPredicate(type: .and, subpredicates: predicates))
        }

        if number == n {
            return query.element
        }

        for child in children {
            if child.number >= n {
                return child.element(for: n, in: query.descendants(matching: child.attributes.elementType))
            }
        }
        fatalError()
    }
}

extension String {
    var indented: String {
        replacing("\n", with: "\n  ")
    }
}

extension XCUIElement.ElementType {
    var description: String {
        switch self {
        case .application: return "Application"
        case .button: return "Button"
        case .cell: return "Cell"
        case .icon: return "Icon"
        case .link: return "Link"
        case .navigationBar: return "Navigation Bar"
        case .scrollView: return "Scroll View"
        case .searchField: return "Search Field"
        case .tabBar: return "Tab Bar"
        case .textField: return "TextField"
        case .textView: return "TextView"
        case .staticText: return "Text"
        default: return "Other"
        }
    }
}
