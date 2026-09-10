fn main() {
    quickshell_update::main_result(|runner| {
        let result = quickshell_update::update::Paths::from_env()
            .and_then(|paths| quickshell_update::update::install(&paths, runner));
        if let Err(error) = &result {
            let _ = quickshell_update::update::event("error", &format!("{error:#}"));
        }
        result
    });
}
