import Foundation
import Observation

public enum OCamlDemoScreen: String, Codable {
    case counter
    case todo
    case search
}

public struct OCamlDemoTodo: Codable, Identifiable {
    public let id: Int
    public let title: String
    public let completed: Bool
}

public struct OCamlDemoSnapshot: Decodable {
    public let revision: Int
    public let screen: OCamlDemoScreen
    public let count: Int?
    public let draft: String?
    public let items: [OCamlDemoTodo]?
    public let query: String?
    public let results: [String]?
}

public struct OCamlDemoCoreError: Decodable, Equatable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public struct OCamlDemoRPCResponse: Decodable {
    public let apiVersion: Int
    public let ok: Bool
    public let result: OCamlDemoSnapshot?
    public let error: OCamlDemoCoreError?
}

public struct OCamlDemoRPCParams: Encodable {
    public let screen: String
    public let action: String?
    public let payload: String?

    public init(screen: String, action: String?, payload: String?) {
        self.screen = screen
        self.action = action
        self.payload = payload
    }
}

public struct OCamlDemoRPCRequest: Encodable {
    public let apiVersion: Int
    public let method: String
    public let params: OCamlDemoRPCParams

    public init(apiVersion: Int, method: String, params: OCamlDemoRPCParams) {
        self.apiVersion = apiVersion
        self.method = method
        self.params = params
    }
}

@Observable public final class OCamlDemoStore {
    public private(set) var snapshot: OCamlDemoSnapshot?
    public private(set) var lastError: OCamlDemoCoreError?

    private let callCore: (String) -> String

    public init(call: @escaping (String) -> String) {
        callCore = call
    }

    public func load(_ screen: OCamlDemoScreen) {
        perform(
            OCamlDemoRPCRequest(
                apiVersion: 1,
                method: "snapshot",
                params: OCamlDemoRPCParams(
                    screen: screen.rawValue,
                    action: nil,
                    payload: nil
                )
            )
        )
    }

    public func dispatch(
        screen: OCamlDemoScreen,
        action: String,
        payload: String? = nil
    ) {
        perform(
            OCamlDemoRPCRequest(
                apiVersion: 1,
                method: "dispatch",
                params: OCamlDemoRPCParams(
                    screen: screen.rawValue,
                    action: action,
                    payload: payload
                )
            )
        )
    }

    private func perform(_ request: OCamlDemoRPCRequest) {
        do {
            let requestData = try JSONEncoder().encode(request)
            guard let requestJSON = String(data: requestData, encoding: .utf8) else {
                lastError = OCamlDemoCoreError(
                    code: "request_encoding",
                    message: "Could not encode the core request as UTF-8"
                )
                return
            }
            let responseJSON = callCore(requestJSON)
            let responseData = Data(responseJSON.utf8)
            let response = try JSONDecoder().decode(
                OCamlDemoRPCResponse.self,
                from: responseData
            )
            if response.ok, let result = response.result {
                snapshot = result
                lastError = nil
            } else {
                lastError =
                    response.error
                    ?? OCamlDemoCoreError(
                        code: "invalid_response",
                        message: "The core returned neither a result nor an error"
                    )
            }
        } catch {
            lastError = OCamlDemoCoreError(
                code: "transport_error",
                message: "\(error)"
            )
        }
    }
}
