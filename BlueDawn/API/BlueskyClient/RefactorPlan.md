# BlueskyClient Refactor Plan

## Current observations (code review)
- **Monolithic type**: `BlueskyClient` currently holds configuration, request helpers, mapping, decoding models, and endpoint logic in a single 800+ line file, making navigation and targeted edits difficult.
- **Mixed concerns**: Networking concerns (authorization headers, HTTP verbs) are interleaved with domain-level behaviors (timeline filtering, post mapping) and low-level model definitions, reducing readability and testability.
- **Nested helpers**: Inline helper functions (e.g., `getSession`, `getFollowingSet` inside `fetchHomeTimeline`) hide reusable logic and make it harder to share functionality or test in isolation.
- **Redundant request building**: Each endpoint constructs `URLComponents` and `URLRequest` manually, with repeated header setup and error handling patterns that could be centralized.
- **Tightly coupled models**: Endpoint-specific response models live alongside unrelated behaviors, complicating reuse and making it harder to evolve API coverage without growing the single file further.
- **Limited surface for testing**: The lack of dependency injection for HTTP transport and date decoding makes it difficult to unit test behaviors (e.g., timeline filtering, embed parsing) without hitting the network.

## Proposed modular structure
Place the Bluesky implementation in `BlueDawn/API/BlueskyClient/` to keep related pieces together while allowing small, focused files. Suggested files and responsibilities:

- `BlueskyClient.swift`
  - Core client type with initialization, shared configuration (PDS URL, tokens), and public protocol conformance.
  - Dependency hooks (e.g., injectable `URLSession`/transport, decoder factories) to ease testing.

- `Endpoints/TimelineEndpoints.swift`
  - Timeline-related calls (`fetchHomeTimeline`, `fetchThread`, `fetchAncestors`) and any timeline-specific filtering helpers.

- `Endpoints/ProfileEndpoints.swift`
  - Profile and author feed APIs (`fetchUserProfile`, `fetchAuthorFeed`).

- `Endpoints/EngagementEndpoints.swift`
  - Like/repost/reply and follow/unfollow operations, consolidating shared request body builders.

- `Networking/RequestBuilder.swift`
  - Reusable helpers for constructing `URLComponents`, `URLRequest`, authorization headers, and response validation.
  - Centralize error handling and status-code checks.

- `Mapping/PostMapping.swift`
  - Conversion logic from Bluesky wire models to `UnifiedPost`, `ThreadItem`, and `QuotedPost`, including embed/media helpers.

- `Models/` (folder)
  - Decodable models grouped by domain (e.g., `TimelineModels.swift`, `ProfileModels.swift`, `EmbedModels.swift`).
  - Shared utility types (`DynamicCodingKeys`, `Facet`, `Embed`, etc.) can be separated for reuse.

- `Utilities/TextParsing.swift`
  - Rich-text helpers (`attributedFromBsky`, `indexAtByteOffset`, fallback link detection) to isolate string/AttributedString handling.

## Implementation notes
- Extract nested helpers (session fetch, following set lookup) into private methods or dedicated services so multiple endpoints can reuse them.
- Introduce a single JSONDecoder factory to standardize date decoding and reduce per-call setup.
- Consider injecting a protocol-based transport (wrapping `URLSession`) to enable unit tests for each endpoint without live network calls.
- Keep public API surface stable by using extensions on `BlueskyClient` in the endpoint files so call sites remain unchanged.
- Migrate gradually: start by moving pure helpers/mapping code, then split endpoints one group at a time to minimize risk.

## Benefits
- Smaller, role-focused files improve readability and discoverability for future changes.
- Shared request/response handling reduces duplication and the risk of inconsistent headers or error handling.
- Clear separation of concerns (networking vs. mapping vs. endpoints) makes it easier to extend coverage and write unit tests.
- Modular structure supports future enhancements (e.g., caching, retry logic, additional endpoints) without growing a single file.
