fn main() {
    quickshell_helpers::main_result(|runner| {
        quickshell_helpers::output(&quickshell_helpers::brightness::run(
            &std::env::args().skip(1).collect::<Vec<_>>(),
            runner,
        )?)
    });
}
