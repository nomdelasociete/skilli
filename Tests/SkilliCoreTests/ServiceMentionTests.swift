import XCTest
@testable import SkilliCore

final class ServiceMentionTests: XCTestCase {
    let services = ["nimbus-deployment", "nimbus-review", "linear", "google-calendar", "storyline"]

    func testNamedServices() {
        XCTAssertEqual(ServiceMention.named(in: "j'ai des taches nimbus deployment en cours ?", services: services), ["nimbus-deployment"])
        XCTAssertEqual(ServiceMention.named(in: "quoi de neuf sur nimbus ?", services: services), ["nimbus-deployment", "nimbus-review"])
        XCTAssertEqual(ServiceMention.named(in: "j'ai des tâches Nimbus-Deployment ?", services: services).first, "nimbus-deployment")
        XCTAssertEqual(ServiceMention.named(in: "mes issues Linear de la semaine", services: services), ["linear"])
        XCTAssertEqual(ServiceMention.named(in: "cherche sur google le prix", services: services), [], "a common first word is not enough")
        XCTAssertEqual(ServiceMention.named(in: "mon agenda google calendar demain", services: services), ["google-calendar"])
        XCTAssertEqual(ServiceMention.named(in: "explique ce texte", services: services), [])
    }

    func testNamesSaidWhole() {
        let names = ["portfolio", "nimbus-api", "Restart Wi-Fi", "Log Water", "api", "notes", "skilli"]
        XCTAssertEqual(ServiceMention.said(in: "ouvre mon portfolio", names: names), ["portfolio"])
        XCTAssertEqual(ServiceMention.said(in: "ouvre le projet skilli dans cursor", names: names), ["skilli"])
        XCTAssertEqual(ServiceMention.said(in: "ouvre nimbus-api", names: names), ["nimbus-api"])
        XCTAssertEqual(ServiceMention.said(in: "je veux bosser sur l'api nimbus", names: names), [], "the words, not in order; a short name alone")
        XCTAssertEqual(ServiceMention.said(in: "relance le wifi", names: names), [])
        XCTAssertEqual(ServiceMention.said(in: "log water", names: names), ["Log Water"])
        XCTAssertEqual(ServiceMention.said(in: "ouvre mes notes", names: names), [], "a common word is not a name said")
    }

    func testToolWordsAndDescription() {
        let tools = ["whoami", "listDeployments", "getTask", "listTasks", "create_milestone", "updateUserEmail"]
        XCTAssertEqual(ServiceMention.toolWords(in: "liste mes deployments en retard", tools: tools), ["deployment"])
        XCTAssertEqual(ServiceMention.toolWords(in: "my open tasks", tools: tools), ["task"])
        XCTAssertEqual(ServiceMention.toolWords(in: "les milestones du projet", tools: tools), ["milestone"])
        XCTAssertEqual(ServiceMention.toolWords(in: "bonjour", tools: tools), [])
        XCTAssertEqual(ServiceMention.words("listDeployments"), ["list", "deployments"])
        let text = ServiceMention.describe([(name: "nimbus-deployment", tools: tools), (name: "linear", tools: [])], toolsEach: 3)
        XCTAssertEqual(text, "Connected services the agent can use, with some of their tools:\n- nimbus-deployment: whoami, listDeployments, getTask\n- linear")
        XCTAssertEqual(ServiceMention.describe([]), "")
    }
}
