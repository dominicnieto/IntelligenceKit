
import Foundation
import FoundationModels
import Swarm
import PlaygroundSupport

PlaygroundSupport.PlaygroundPage.current.needsIndefiniteExecution = true

struct ResearchAgent: LegacyAgent {
    var provider: any InferenceProvider {
        
    }
    
    var instructions: String {
        "You are a careful research agent."
    }
    
    

    var loop: some AgentLoop {
        
        Generate()

    }
}


Task {
    print("Starting")
    do {
        let response = try await ResearchAgent().run("Hello").output
        print("LegacyAgent Response: ", response)
    } catch {
        print("Error: \(error)")
    }
    var greeting = "Hello, playground"
}

