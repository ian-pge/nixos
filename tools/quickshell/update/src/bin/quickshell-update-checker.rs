fn main() {
    quickshell_update::main_result(|runner| {
        let paths = quickshell_update::update::Paths::from_env()?;
        let force = std::env::args().nth(1).as_deref() == Some("force");
        quickshell_update::output(&quickshell_update::update::check(&paths, runner, force)?)
    });
}
