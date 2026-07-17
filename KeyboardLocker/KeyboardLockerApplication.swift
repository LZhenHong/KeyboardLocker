@main
enum KeyboardLockerApplication {
  @MainActor
  static func main() {
    _ = AgentRegistrar.ensureEnabled()
  }
}
