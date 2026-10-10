// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "ArcanineDependencies", platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/warrenm/GLTFKit2.git", revision: "be89e833aa85bde67bd27d4ecff3b7816c58ce56")],
    targets: [.executableTarget(name: "ArcanineDependencies", dependencies: [.product(name: "GLTFKit2", package: "GLTFKit2")], path: "Sources")])
