# Rust Ecosystem Crates Analysis & Architectural Placement Guide

This document provides a comprehensive technical analysis of every recommended Rust crate for the Startup Studio ecosystem. It outlines **what** each crate does, **where** in the directory structure it belongs, **why** it was chosen over alternatives, and **which compilation targets** it supports.

---

## 1. Quick Reference: Crate Distribution by Studio Tier

| Crate | Studio Tier / Location | Compilation Target | Primary Role |
| :--- | :--- | :--- | :--- |
| **`thiserror`** | `./my-kit/crates/my-kit-core` | Universal (`wasm32` + Native) | Strongly-typed library domain errors |
| **`ulid`** | `./my-kit/crates/my-kit-core` | Universal (`wasm32` + Native) | Monotonic sortable 128-bit IDs |
| **`compact_str`** | `./my-kit/crates/my-kit-core` | Universal (`wasm32` + Native) | Zero-allocation small string storage |
| **`validator`** | `./my-kit/crates/my-kit-core` | Universal (`wasm32` + Native) | Declarative form & payload validation |
| **`secrecy`** / **`zeroize`** | `./my-kit/crates/my-kit-core` | Universal (`wasm32` + Native) | Zero-leak cryptographic memory sanitization |
| **`postcard`** | `./my-kit/crates/my-kit-core` | Universal (`wasm32` + Native) | Compact zero-copy binary serialization |
| **`indexed_db_futures`** | `./my-kit/crates/my-kit-core` | Web (`wasm32-unknown-unknown`) | High-capacity (>5MB) browser persistence |
| **`redb`** | `./my-kit/crates/my-kit-core` | Native Desktop (Win/macOS/Linux) | Pure-Rust embedded ACID key-value engine |
| **`dioxus-free-icons`** | `./my-kit/crates/my-kit-ui` | Universal UI | Semantic SVG icon components |
| **`arboard`** | `./my-kit/crates/my-kit-ui` | Native Desktop | Cross-platform OS clipboard access |
| **`tracing`** | Universal (`my-kit` + clients) | Universal | Structured diagnostics and span instrumentation |
| **`tracing-subscriber`** | `./my-kit/crates/my-kit-template`, desktop | Native Desktop | Console & rotating file log subscribers |
| **`tracing-web`** | `./my-kit/crates/my-kit-template`, web | Web (`wasm32`) | Browser DevTools console bridge |
| **`rust_decimal`** | `./clients/ecommerce/repo` | Universal (`wasm32` + Native) | Exact 128-bit currency math |
| **`async-stripe`** | `./clients/ecommerce/repo` | Native / Backend | Checkout sessions, webhooks, portals |
| **`reqwest`** | `./clients/ecommerce/repo` | Universal (Native TLS + `fetch`) | Carrier shipping APIs & headless inventory |
| **`image`** | `./clients/photo-studio/repo` | Universal (`wasm32` + Native) | Pixel decoding, encoding, and thumbnail resampling |
| **`kamadak-exif`** | `./clients/photo-studio/repo` | Universal (`wasm32` + Native) | Pure-Rust EXIF camera & orientation parser |
| **`oxipng`** | `./clients/photo-studio/repo` | Native Desktop | Multithreaded lossless PNG preview optimizer |
| **`rfd`** | `./clients/photo-studio/repo` | Native Desktop | Non-blocking native OS file/folder pickers |
| **`imageproc`** | `./clients/photo-studio/repo` | Universal (`wasm32` + Native) | Watermarking & copyright overlay rendering |
| **`anyhow`** | `./clients/*/repo`, CLI tooling | Native Binaries | Context-rich error propagation in app runners |

---

## 2. Core Foundation & Data Ergonomics (`./my-kit/crates/my-kit-core`)

The core engine contains zero UI dependencies and must compile cleanly to both native architectures and `wasm32-unknown-unknown`. Crates here must have zero-cost abstractions, minimal dependencies, and strict memory safety.

---

### `thiserror` (v2.0+)
- **Exact File Placement:** `./my-kit/crates/my-kit-core/Cargo.toml`
- **Target Platform:** Universal (`wasm32` + Native)
- **Problem Solved:** Hand-crafting `std::fmt::Display` and `std::error::Error` implementations for domain errors produces hundreds of lines of repetitive boilerplate and inconsistent error messages.
- **Where It Is Needed:**
  - `./my-kit/crates/my-kit-core/src/base/result.rs`: Core `AppError`.
  - `./my-kit/crates/my-kit-core/src/storage.rs`: `StorageError` variants (`NotFound`, `SerializationFailed`, `QuotaExceeded`, `Io`).
  - `./my-kit/crates/my-kit-core/src/auth.rs`: `AuthError` variants (`ExpiredToken`, `InvalidSignature`, `MissingClaim`).
- **Why Chosen over Alternatives:**
  - *vs. `anyhow`:* `anyhow` uses dynamic heap allocation (`Box<dyn Error>`) which erases the concrete error type. Libraries must provide matchable enums so consumers can programmatically handle specific errors (e.g., refreshing an expired token on `AuthError::ExpiredToken`).
  - *vs. Manual `Display`:* `thiserror` adds zero runtime overhead—it expands directly into standard `Display` and `Error` trait implementations at compile time.

---

### `ulid` (v1.1+)
- **Exact File Placement:** `./my-kit/crates/my-kit-core/Cargo.toml`
- **Target Platform:** Universal (`wasm32` + Native, with `features = ["wasm-bindgen"]`)
- **Problem Solved:** Random UUIDv4 identifiers cannot be naturally sorted by time, causing database index fragmentation and requiring secondary timestamp columns to sort orders or gallery uploads chronologically.
- **Where It Is Needed:**
  - `./my-kit/crates/my-kit-core/src/base/id.rs`: Base identifier generator.
  - `./clients/ecommerce/repo/src/domain/order.rs`: Order IDs (`ord_01ARZ3NDEKTSV4RRFFQ69G5FAV`).
  - `./clients/photo-studio/repo/src/domain/asset.rs`: Image asset and upload session IDs.
- **Why Chosen over Alternatives:**
  - *vs. UUIDv4:* ULIDs are 128-bit compatible with UUIDs, but the most significant 48 bits encode a UNIX millisecond timestamp. New records naturally sort in ascending order without an extra `created_at` index query.
  - *vs. UUIDv7:* ULID produces a 26-character URL-safe Crockford Base32 string (no hyphens), which is shorter and easier to pass in URLs and barcodes than standard 36-character hyphenated UUID strings.

---

### `compact_str` (v0.8+)
- **Exact File Placement:** `./my-kit/crates/my-kit-core/Cargo.toml`
- **Target Platform:** Universal (`wasm32` + Native)
- **Problem Solved:** Standard `std::string::String` allocates 24 bytes on the stack plus a separate heap allocation for even a 1-character string. In reactive web applications with thousands of form fields and validation tags, this causes severe heap fragmentation and garbage collection pauses in WebAssembly.
- **Where It Is Needed:**
  - `./my-kit/crates/my-kit-core/src/forms.rs`: Form field names, validation error messages, and input keys.
  - `./my-kit/crates/my-kit-core/src/auth.rs`: User roles, permissions, and session status strings.
- **Why Chosen over Alternatives:**
  - *vs. `smol_str`:* `compact_str` stores up to 24 bytes entirely on the stack (on 64-bit systems) without touching the heap allocator at all. It seamlessly dereferences to `&str` and converts into standard `String` only when length exceeds 24 bytes.
  - *vs. `String`:* Zero heap allocations for short labels, error messages, and form keys drastically reduces memory pressure on memory-constrained WASM runtimes.

---

### `validator` (v0.18+)
- **Exact File Placement:** `./my-kit/crates/my-kit-core/Cargo.toml` (with `features = ["derive"]`)
- **Target Platform:** Universal (`wasm32` + Native)
- **Problem Solved:** Writing imperative validation logic (`if email.contains('@') ... if len < 8 ...`) across every struct leads to duplicated code and inconsistent error formats between client and server.
- **Where It Is Needed:**
  - `./my-kit/crates/my-kit-core/src/forms.rs`: Declarative schema validation for form submissions.
  - `./clients/ecommerce/repo/src/domain/checkout.rs`: Customer email, shipping address, postal code, and cart quantity bounds.
- **Why Chosen over Alternatives:**
  - *vs. Manual validation functions:* Annotates structs directly with attributes (`#[validate(email)]`, `#[validate(length(min = 1, max = 100))]`), producing standardized, serializable validation error structures out-of-the-box.

---

### `secrecy` (v0.8+) & `zeroize` (v1.8+)
- **Exact File Placement:** `./my-kit/crates/my-kit-core/Cargo.toml` (with `features = ["serde", "zeroize"]`)
- **Target Platform:** Universal (`wasm32` + Native)
- **Problem Solved:** Plaintext passwords, JWT secrets, and API keys can easily leak into log outputs via accidental `println!("{:?}", user)` or crash dumps. Furthermore, deallocated memory remains in RAM until overwritten, leaving keys vulnerable to memory scrapers.
- **Where It Is Needed:**
  - `./my-kit/crates/my-kit-core/src/auth.rs`: JWT signing secrets and session refresh tokens.
  - `./clients/ecommerce/repo/src/services/stripe.rs`: Stripe Secret Key and webhook signing secret.
- **Why Chosen over Alternatives:**
  - `secrecy::Secret<T>` explicitly redacts the value in `Debug` and `Display` implementations (printing `[REDACTED]`).
  - `zeroize` overwrites the underlying memory buffer with zeroes immediately upon `Drop`, preventing sensitive keys from lingering in deallocated memory pages.

---

## 3. Storage & High-Capacity Persistence (`./my-kit/crates/my-kit-core/src/storage`)

v0.1.0 implemented basic `MemoryStorage`, `FileStorage` (native), and `LocalStorage` (WASM). To support enterprise workflows, the storage architecture requires high-capacity caching and structured embedded databases.

---

### `indexed_db_futures` (v0.6+)
- **Exact File Placement:** `./my-kit/crates/my-kit-core/Cargo.toml` (under `[target.'cfg(target_arch = "wasm32")'.dependencies]`)
- **Target Platform:** Web (`wasm32-unknown-unknown`)
- **Problem Solved:** Browser `localStorage` has a hard synchronous limit of ~5 MB per origin and blocks the main browser thread during read/write operations. Storing image thumbnails or offline product catalogs quickly causes `QuotaExceededError`.
- **Where It Is Needed:**
  - `./my-kit/crates/my-kit-core/src/storage/indexed_db.rs`: Enterprise web persistence implementation of the `AsyncKeyValueStore` trait.
  - `./clients/photo-studio/repo`: Offline thumbnail caching in web client gallery.
  - `./clients/ecommerce/repo`: Offline product catalog and shopping cart persistence.
- **Why Chosen over Alternatives:**
  - *vs. Raw `web-sys` IndexedDB:* The native browser IndexedDB API uses complex callback-based event targets (`onsuccess`, `onerror`, `onupgradeneeded`). `indexed_db_futures` wraps these in native Rust `Future`s, enabling clean `async`/`await` syntax.
  - *Capacity:* IndexedDB provides access to hundreds of megabytes (or up to 80% of free disk space depending on browser permissions), removing the 5 MB ceiling.

---

### `redb` (v2.1+)
- **Exact File Placement:** `./my-kit/crates/my-kit-core/Cargo.toml` (under `[target.'cfg(not(target_arch = "wasm32"))'.dependencies]`)
- **Target Platform:** Native Desktop (Windows, macOS, Linux)
- **Problem Solved:** Native desktop applications need an embedded, crash-safe, zero-configuration database that doesn't require compiling C libraries or external database servers.
- **Where It Is Needed:**
  - `./my-kit/crates/my-kit-core/src/storage/redb_store.rs`: Native desktop implementation of `KeyValueStore` and structured collection tables.
  - `./clients/photo-studio/repo`: Fast indexed metadata storage for tens of thousands of imported photos (indexing tags, rating, aperture, lens, file path).
- **Why Chosen over Alternatives:**
  - *vs. `rusqlite` / SQLite:* SQLite requires compiling C code via `cc` or `vcpkg`, creating toolchain friction on Windows and cross-compilation headaches. `redb` is written in 100% safe Rust, has zero C dependencies, and compiles instantly.
  - *vs. RocksDB / Sled:* RocksDB is a heavy C++ library with complex tuning. Sled is inactive. `redb` provides clean ACID MVCC transactions, b-tree tables, and crash-resilient write-ahead logging.

---

### `postcard` (v1.0+)
- **Exact File Placement:** `./my-kit/crates/my-kit-core/Cargo.toml` (with `features = ["alloc"]`)
- **Target Platform:** Universal (`wasm32` + Native)
- **Problem Solved:** Serializing large structures (e.g. hundreds of photo metadata items or cart records) to JSON text introduces high string parsing overhead and wastes 40–70% of storage space.
- **Where It Is Needed:**
  - `./my-kit/crates/my-kit-core/src/storage.rs`: Binary serialization layer for `KeyValueStore::set_binary` and `get_binary`.
  - Serializing cached thumbnail byte streams and offline catalog state into IndexedDB and `redb`.
- **Why Chosen over Alternatives:**
  - *vs. `serde_json`:* `postcard` produces variable-length binary encoding, drastically reducing disk and IndexedDB payload size while executing significantly faster.
  - *vs. `bincode`:* `postcard` was engineered with `no_std` and embedded safety in mind, preventing malicious or corrupted payloads from triggering unbounded memory allocations.

---

## 4. Photography & Asset Processing (`./clients/photo-studio/repo`)

`photo-studio` operates as a hybrid desktop asset manager and responsive web client gallery. It requires high-performance image decoding, metadata extraction, native OS integration, and non-destructive image manipulation.

---

### `image` (v0.25+)
- **Exact File Placement:** `./clients/photo-studio/repo/Cargo.toml` (with `default-features = false`, `features = ["jpeg", "png", "webp", "avif"]`)
- **Target Platform:** Universal (`wasm32` + Native)
- **Problem Solved:** Fast decoding and downscaling of multi-megapixel camera files into responsive preview thumbnails without external dependencies like ImageMagick.
- **Where It Is Needed:**
  - `./clients/photo-studio/repo/src/pipeline/thumbnails.rs`: Downsampling raw JPEG/PNG images into pyramid sizes:
    - Micro thumbnail: `128x128` (grid scrolling)
    - Preview size: `512x512` (inspect view)
    - Full client proof: `1024x1024` (proofing gallery)
- **Why Chosen over Alternatives:**
  - Pure-Rust image library with zero C-bindings, compiling seamlessly across both native Windows/macOS and WebAssembly.
  - Built-in Lanczos3 and Triangle resampling filters provide sharp, artifact-free downsampling for professional photo displays.

---

### `kamadak-exif` (v0.5+)
- **Exact File Placement:** `./clients/photo-studio/repo/Cargo.toml`
- **Target Platform:** Universal (`wasm32` + Native)
- **Problem Solved:** Photos shot in portrait or inverted orientations must be displayed correctly according to their EXIF `Orientation` tag, and professional photographers require camera metadata (camera body, lens, focal length, ISO, shutter speed, aperture).
- **Where It Is Needed:**
  - `./clients/photo-studio/repo/src/pipeline/metadata.rs`: Reading EXIF blocks directly from file headers without loading the full image into memory.
  - Auto-rotating thumbnail matrices prior to rendering in `./clients/photo-studio/repo/src/views/gallery.rs`.
- **Why Chosen over Alternatives:**
  - *vs. `rexif`:* `kamadak-exif` is actively maintained, pure Rust, and allows streaming EXIF parsing directly from a `std::io::BufReader` or byte slice without reading the entire raw image file into RAM.

---

### `oxipng` (v9.1+)
- **Exact File Placement:** `./clients/photo-studio/repo/Cargo.toml`
- **Target Platform:** Native Desktop
- **Problem Solved:** Exporting proofing galleries and client preview packages consumes significant cloud storage (AWS S3 / Cloudflare R2) and slows down client proofing approvals over mobile connections.
- **Where It Is Needed:**
  - `./clients/photo-studio/repo/src/pipeline/optimizer.rs`: Lossless compression pass on exported PNG preview assets before upload.
- **Why Chosen over Alternatives:**
  - Multithreaded PNG optimization written in Rust that achieves 10–30% smaller files than standard `libpng` or Photoshop exports without any visual degradation.

---

### `rfd` (Rust File Dialog - v0.14+)
- **Exact File Placement:** `./clients/photo-studio/repo/Cargo.toml`
- **Target Platform:** Native Desktop (Windows, macOS, Linux)
- **Problem Solved:** Desktop photo management software must let users select entire SD cards or photoshoot directories via the operating system's native file explorer dialog.
- **Where It Is Needed:**
  - `./clients/photo-studio/repo/src/views/import_dialog.rs`: "Import Shoot Folder" and "Select Export Directory" buttons.
- **Why Chosen over Alternatives:**
  - Native cross-platform dialog integration (Windows Win32 IFileDialog, macOS NSOpenPanel, Linux XDG Desktop Portal) with full `async` support that does not freeze the Dioxus UI thread.

---

### `imageproc` (v0.25+)
- **Exact File Placement:** `./clients/photo-studio/repo/Cargo.toml`
- **Target Platform:** Universal (`wasm32` + Native)
- **Problem Solved:** Unpaid client proofing galleries require diagonal copyright watermarks or tiled logo overlays to prevent unauthorized screenshots.
- **Where It Is Needed:**
  - `./clients/photo-studio/repo/src/pipeline/watermark.rs`: Compositing semi-transparent copyright text and proofing grids onto exported client gallery previews.
- **Why Chosen over Alternatives:**
  - Pure-Rust 2D image processing primitives (drawing text, lines, polygons, and alpha compositing) that execute cleanly without native canvas or GPU dependencies.

---

## 5. Digital Commerce & Financials (`./clients/ecommerce/repo`)

Financial software requires absolute precision, secure third-party payment integration, and robust external API communication.

---

### `rust_decimal` & `rust_decimal_macros` (v1.36+)
- **Exact File Placement:** `./clients/ecommerce/repo/Cargo.toml` (with `features = ["serde", "maths"]`)
- **Target Platform:** Universal (`wasm32` + Native)
- **Problem Solved:** Standard floating-point numbers (`f32`, `f64`) use binary representation, causing rounding bugs (`0.1 + 0.2 == 0.30000000000000004`). In financial transactions, this leads to accounting drift, incorrect tax calculations, and payment gateway rejections.
- **Where It Is Needed:**
  - `./clients/ecommerce/repo/src/domain/price.rs`: Product prices, tax calculations, discounts, coupon subtotals, and checkout grand totals.
  - Inlining constants via `dec!(19.99)`.
- **Why Chosen over Alternatives:**
  - 128-bit fixed-point decimal arithmetic representing numbers up to 28–29 significant digits with exact base-10 precision. Fully integrates with `serde` for JSON/database serialization.

---

### `async-stripe` (v0.37+)
- **Exact File Placement:** `./clients/ecommerce/repo/Cargo.toml` (with `features = ["checkout", "webhook-events"]`)
- **Target Platform:** Native / Server / Backend Runtime
- **Problem Solved:** Processing credit card payments, generating hosted checkout sessions, and safely verifying webhook signatures against tampering.
- **Where It Is Needed:**
  - `./clients/ecommerce/repo/src/services/stripe.rs`:
    - Creating Stripe Checkout Sessions (`stripe::CheckoutSession::create`).
    - Verifying incoming Stripe webhook signatures (`stripe::Webhook::construct_event`).
    - Managing customer billing portals.
- **Why Chosen over Alternatives:**
  - The leading asynchronous, strongly-typed Rust SDK for the Stripe API. It automatically maps Stripe JSON event payloads into type-safe Rust structs and handles webhook HMAC signature verification securely.

---

### `reqwest` (v0.12+)
- **Exact File Placement:** `./clients/ecommerce/repo/Cargo.toml` (with `default-features = false`, `features = ["json", "rustls-tls"]`)
- **Target Platform:** Universal (Native sockets + browser `fetch` via `wasm32`)
- **Problem Solved:** Communicating with external logistics APIs (EasyPost, ShipStation) for shipping rate calculation, tracking, and third-party inventory sync.
- **Where It Is Needed:**
  - `./clients/ecommerce/repo/src/services/shipping.rs`: Fetching real-time carrier shipping quotes during checkout.
  - `./clients/ecommerce/repo/src/services/tax.rs`: Automated sales tax calculations (TaxJar / Stripe Tax).
- **Why Chosen over Alternatives:**
  - Seamlessly compiles to both native targets (using modern memory-safe `rustls`) and WebAssembly (automatically switching to browser `window.fetch` without code changes).

---

## 6. UI, Reactive Components & Observability (`./my-kit/crates/my-kit-ui`)

`my-kit-ui` provides the shared presentation layer, design tokens, hooks, and desktop/web UI utilities across all ventures.

---

### `dioxus-free-icons` (v0.8+)
- **Exact File Placement:** `./my-kit/crates/my-kit-ui/Cargo.toml` (with `features = ["lucide"]`)
- **Target Platform:** Universal UI
- **Problem Solved:** Embedding raw inline SVG XML strings into RSX components bloats the codebase, makes icons difficult to style, and creates visual inconsistency across ventures.
- **Where It Is Needed:**
  - `./my-kit/crates/my-kit-ui/src/components/navigation.rs`: Shopping cart icon, user avatar, search magnifying glass.
  - `./clients/photo-studio/repo/src/views/toolbar.rs`: Zoom, rotate, export, and delete icons.
- **Why Chosen over Alternatives:**
  - Provides thousands of Lucide icons as native Dioxus RSX components with full prop support (`size`, `color`, `stroke_width`) and automatic dead-code elimination (tree-shaking).

---

### `arboard` (v3.4+)
- **Exact File Placement:** `./my-kit/crates/my-kit-ui/Cargo.toml`
- **Target Platform:** Native Desktop (Windows, macOS, Linux)
- **Problem Solved:** Users need to copy share links, promo codes, and rendered image buffers to their operating system clipboard in desktop applications.
- **Where It Is Needed:**
  - `./my-kit/crates/my-kit-ui/src/hooks/use_clipboard.rs`: Cross-platform clipboard hook.
  - "Copy Tracking Number" and "Copy Shareable Gallery Link" buttons.
- **Why Chosen over Alternatives:**
  - *vs. `clipboard`:* `clipboard` is unmaintained. `arboard` is actively maintained and supports copying both UTF-8 text and raw RGBA image pixel buffers to and from the OS clipboard.

---

### `tracing`, `tracing-subscriber`, and `tracing-web`
- **Exact File Placement:**
  - `tracing`: Universal in `./my-kit/crates/my-kit-core/Cargo.toml` and `./my-kit/crates/my-kit-ui/Cargo.toml`
  - `tracing-subscriber`: `./my-kit/crates/my-kit-template/Cargo.toml` (desktop)
  - `tracing-web`: `./my-kit/crates/my-kit-template/Cargo.toml` (web)
- **Target Platform:** Universal (Native + WASM)
- **Problem Solved:** Raw `println!` statements are unstructured, lack execution context, cannot be filtered by log level, and do not show up cleanly in browser DevTools.
- **Where It Is Needed:**
  - All async operations (checkout flows, image import pipelines, storage transactions).
  - Native desktop: Routes formatted logs to console and rotating log files.
  - Web: Routes structured events directly into browser `console.log` / `console.error` with colored spans.
- **Why Chosen over Alternatives:**
  - The de-facto Rust standard for diagnostic instrumentation. Spans track asynchronous tasks across `.await` points, giving clear visibility into async execution timings.

---

## 7. Studio Automation & Developer Tooling (`./studio.ps1` & CLI)

---

### `anyhow` (v1.0+)
- **Exact File Placement:** `./clients/*/repo/Cargo.toml` and CLI tools
- **Target Platform:** Native Binaries
- **Problem Solved:** Application binaries and CLI scripts do not need matchable error enums; they need clear, chained contextual descriptions when an operation fails (e.g., `Failed to load config -> File not found`).
- **Where It Is Needed:**
  - `./clients/ecommerce/repo/src/main.rs`
  - `./clients/photo-studio/repo/src/main.rs`
- **Why Chosen over Alternatives:**
  - Simple `.context("...")` chaining that prints readable, formatted error traces for end users and developers.

---

## 8. Summary Architecture Matrix

```mermaid
flowchart TD
    subgraph Core Engine ["my-kit-core (Universal)"]
        thiserror["thiserror (Typed Domain Errors)"]
        ulid["ulid (Monotonic 128-bit IDs)"]
        compact_str["compact_str (Stack Strings)"]
        validator["validator (Schema Rules)"]
        secrecy["secrecy + zeroize (Safe Memory)"]
        postcard["postcard (Binary Serde)"]
    end

    subgraph Storage V2 ["Storage Engine Layer"]
        idb["indexed_db_futures (WASM >5MB)"]
        redb["redb (Desktop Native ACID)"]
    end

    subgraph UI Layer ["my-kit-ui (Dioxus 0.7)"]
        icons["dioxus-free-icons (Lucide)"]
        arboard["arboard (OS Clipboard)"]
        tracing["tracing + tracing-web"]
    end

    subgraph ECommerce ["clients/ecommerce"]
        decimal["rust_decimal (Exact Currency)"]
        stripe["async-stripe (Checkout/Webhooks)"]
        reqwest["reqwest (Carriers / Taxes)"]
    end

    subgraph PhotoStudio ["clients/photo-studio"]
        image["image (Thumbnail Pyramids)"]
        exif["kamadak-exif (Metadata & Orient)"]
        oxipng["oxipng (Lossless Optimizer)"]
        rfd["rfd (Native File Dialogs)"]
        imageproc["imageproc (Watermarking)"]
    end

    Core Engine --> Storage V2
    Core Engine --> UI Layer
    Storage V2 --> ECommerce
    Storage V2 --> PhotoStudio
    UI Layer --> ECommerce
    UI Layer --> PhotoStudio
```

