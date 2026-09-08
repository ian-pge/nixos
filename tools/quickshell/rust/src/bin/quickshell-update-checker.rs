fn main() {
    quickshell_helpers::main_result(|runner| {
        let paths = quickshell_helpers::update::Paths::from_env()?;
        let force = std::env::args().nth(1).as_deref() == Some("force");
        quickshell_helpers::output(&quickshell_helpers::update::check(&paths, runner, force)?)
    });
}
