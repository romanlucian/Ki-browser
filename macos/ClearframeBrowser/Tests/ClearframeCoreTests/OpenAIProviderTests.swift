import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import ClearframeCore

final class OpenAIProviderTests: XCTestCase {
    override func tearDown() {
        ProviderURLProtocol.handler = nil
        super.tearDown()
    }

    func testIncompleteResponseProducesAUsefulError() async throws {
        let provider = OpenAIPageIntelligenceProvider(
            configuration: OpenAIProviderConfiguration(apiKey: "test", safetyIdentifier: "test"),
            session: makeSession { _ in
                Self.response(
                    status: 200,
                    body: #"{"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"output":[]}"#
                )
            }
        )

        do {
            _ = try await provider.translate(text: "Text.", sourceLanguage: "en", targetLanguage: "French")
            XCTFail("Expected an incomplete-response error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("incomplete"))
            XCTAssertTrue(error.localizedDescription.contains("max_output_tokens"))
        }

        let failedProvider = OpenAIPageIntelligenceProvider(
            configuration: OpenAIProviderConfiguration(apiKey: "test", safetyIdentifier: "test"),
            session: makeSession { _ in
                Self.response(
                    status: 200,
                    body: #"{"status":"failed","error":{"message":"Provider processing failed."},"output":[]}"#
                )
            }
        )
        do {
            _ = try await failedProvider.translate(text: "Text.", sourceLanguage: "en", targetLanguage: "French")
            XCTFail("Expected a failed-status error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Provider processing failed"))
        }
    }

    func testRefusalIsReportedWithoutTryingToDecodeItAsJSON() async throws {
        let provider = OpenAIPageIntelligenceProvider(
            configuration: OpenAIProviderConfiguration(apiKey: "test", safetyIdentifier: "test"),
            session: makeSession { _ in
                Self.response(
                    status: 200,
                    body: #"{"status":"completed","output":[{"type":"message","content":[{"type":"refusal","refusal":"No."}]}]}"#
                )
            }
        )

        do {
            _ = try await provider.translate(text: "Text.", sourceLanguage: "en", targetLanguage: "French")
            XCTFail("Expected a refusal error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("declined"))
        }
    }

    func testUnavailableModelErrorDirectsTheUserToSettings() async throws {
        let provider = OpenAIPageIntelligenceProvider(
            configuration: OpenAIProviderConfiguration(apiKey: "test", safetyIdentifier: "test"),
            session: makeSession { _ in
                Self.response(
                    status: 404,
                    body: #"{"error":{"message":"The requested model does not exist.","type":"invalid_request_error","code":"model_not_found"}}"#
                )
            }
        )

        do {
            _ = try await provider.translate(text: "Text.", sourceLanguage: "en", targetLanguage: "French")
            XCTFail("Expected a model-unavailable error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Open Settings"))
            XCTAssertTrue(error.localizedDescription.contains("local analysis is still available"))
            XCTAssertFalse(error.localizedDescription.contains("404"))
        }
    }

    func testDefaultModelMatchesTheSharedProviderContract() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "provider-contract", withExtension: "json"))
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: String]
        )
        XCTAssertEqual(OpenAIProviderDefaults.model, json["defaultModel"])
    }

    private func makeSession(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        ProviderURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProviderURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func requestBody(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
            if count == 0 { break }
            result.append(buffer, count: count)
        }
        return result
    }

    private static func response(status: Int, body: String) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/responses")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(body.utf8))
    }
}

private final class ProviderURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let handler = try XCTUnwrap(Self.handler)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
