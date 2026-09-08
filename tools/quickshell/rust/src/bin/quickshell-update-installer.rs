fn main() {
    quickshell_helpers::main_result(|runner| {
        let result = quickshell_helpers::update::Paths::from_env()
            .and_then(|paths| quickshell_helpers::update::install(&paths, runner));
        if let Err(error) = &result {
            let _ = quickshell_helpers::update::event("error", &format!("{error:#}"));
        }
        result
    });
}
